--[[

CoverageReporter

Formats coverage as a bordered table followed by a tree-style threshold result. Rows are
sorted by coverage percentage or by hit lines, modules without executable lines are left
out, and rows past the limit are folded into a single summary row.

--]]

const Ansi = require("../Ansi")
const Config = require("../Config")
const Coverage = require("../Coverage")
const DisplayWidth = require("../DisplayWidth")
const TableRenderer = require("../TableRenderer")
const TestEnum = require("../TestEnum")
const TextReporter = require("./TextReporter")
const ALIGNMENTS: { TableRenderer.Alignment } = { "Left", "Right", "Right", "Right" }
const ELLIPSIS = "..."
const FLOOR_EPSILON = 1e-9
const GREEN_FROM = 75
const IS_LUNE = Ansi.isLune()
const MAX_PATH_LENGTH = 40
const YELLOW_FROM = 25

-- How the table orders its rows and how many file rows it lists before the summary row.
export type Layout = {
    Rows: number,
    Sort: Config.CoverageSort,
}

-- The layout from before rows and order were configurable.
const DEFAULT_LAYOUT: Layout = { Rows = 20, Sort = "Percentage" }

const CoverageReporter = {}

--[[
    Keeps the end of text that fits within the given number of terminal columns.
]]
const function keepEnd(text: string, columns: number): string
    const characters = {}
    for _, codepoint in utf8.codes(text) do
        table.insert(characters, utf8.char(codepoint))
    end
    local width = 0
    local first = #characters + 1
    for index = #characters, 1, -1 do
        width += DisplayWidth.measure(characters[index])
        if width > columns then
            break
        end
        first = index
    end
    return table.concat(characters, "", first)
end

--[[
    Shortens a path to at most MAX_PATH_LENGTH columns. Whole folders are dropped from the
    front first, and a file name that can't fit on its own keeps only its end.
]]
function CoverageReporter.formatPath(path: string, color: boolean): (string, string)
    assert(type(path) == "string")
    assert(type(color) == "boolean")
    local raw = path:gsub("\\", "/")
    if DisplayWidth.measure(raw) > MAX_PATH_LENGTH then
        const parts = string.split(raw, "/")
        raw = table.remove(parts) :: string
        if DisplayWidth.measure(raw) + #ELLIPSIS + 1 > MAX_PATH_LENGTH then
            raw = `{ELLIPSIS}{keepEnd(raw, MAX_PATH_LENGTH - #ELLIPSIS)}`
        else
            for index = #parts, 1, -1 do
                const candidate = `{parts[index]}/{raw}`
                if DisplayWidth.measure(candidate) + #ELLIPSIS + 1 > MAX_PATH_LENGTH then
                    break
                end
                raw = candidate
            end
            raw = `{ELLIPSIS}/{raw}`
        end
    end
    const directory, filename = raw:match("^(.+/)([^/]+)$")
    return if color and directory then `{Ansi.dim(directory)}{filename}` else raw, raw
end

--[[
    Formats a whole number with comma thousands separators (e.g., 543126 → "543,126").
]]
function CoverageReporter.formatCount(count: number): string
    assert(type(count) == "number")
    local text = tostring(math.floor(count))
    while true do
        const grouped, replacements = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replacements == 0 then
            return text
        end
        text = grouped
    end
end

--[[
    Formats a percentage with one decimal, or two below 1% so tiny totals stay visible.
    Values are floored so the text never claims more coverage than was measured. The
    small epsilon keeps values that are already exact hundredths, like 0.57, from losing
    a digit because their binary form sits just below the boundary.
]]
function CoverageReporter.formatPercentage(value: number): string
    assert(type(value) == "number")
    if value > 0 and value < 1 then
        return string.format("%.2f%%", math.floor(value * 100 + FLOOR_EPSILON) / 100)
    end
    return string.format("%.1f%%", math.floor(value * 10 + FLOOR_EPSILON) / 10)
end

--[[
    Returns the files worth listing, ordered by percentage or by hit lines as the sort
    asks, then executable lines, then path. Files without executable lines are left out.
    The input is not modified. Without a sort, files are ordered by percentage.
]]
function CoverageReporter.sortFiles(
    files: { Coverage.FileCoverage },
    sortOverride: Config.CoverageSort?
): { Coverage.FileCoverage }
    assert(type(files) == "table")
    assert(sortOverride == nil or sortOverride == "HitLines" or sortOverride == "Percentage")
    const sort = sortOverride or "Percentage"
    const sorted = {}
    for _, file in files do
        if file.ExecutableLines > 0 then
            table.insert(sorted, file)
        end
    end
    table.sort(sorted, function(a, b)
        const first = if sort == "HitLines" then a.HitLines else a.Percentage
        const second = if sort == "HitLines" then b.HitLines else b.Percentage
        if first ~= second then
            return first > second
        end
        if a.ExecutableLines ~= b.ExecutableLines then
            return a.ExecutableLines > b.ExecutableLines
        end
        return a.Path < b.Path
    end)
    return sorted
end

const percentage = CoverageReporter.formatPercentage

--[[
    Colors a file's percentage by band with the terminal's stock colors. Below 25% is red,
    from 25% up to 75% is yellow, and 75% or more is green.
]]
function CoverageReporter.colorPercentage(value: number, text: string): string
    assert(type(value) == "number")
    assert(type(text) == "string")
    if value < YELLOW_FROM then
        return Ansi.brightRed(text)
    elseif value < GREEN_FROM then
        return Ansi.brightYellow(text)
    end
    return Ansi.brightGreen(text)
end

--[[
    Returns formatted lines without emitting output. The color argument makes terminal
    and plain output independently testable, and the layout picks the row order and how
    many file rows to list before folding the rest into a summary row. Without a layout,
    it lists 20 rows by percentage, so the output never depends on configuration.
]]
function CoverageReporter.format(
    report: Coverage.CoverageReport,
    threshold: number,
    color: boolean,
    indent: string,
    layoutOverride: Layout?
): { string }
    assert(type(report) == "table")
    assert(type(threshold) == "number")
    assert(type(color) == "boolean")
    assert(type(indent) == "string")
    assert(layoutOverride == nil or type(layoutOverride) == "table")
    const layout = layoutOverride or DEFAULT_LAYOUT
    assert(type(layout.Rows) == "number" and layout.Rows >= 1 and layout.Rows % 1 == 0)
    const maxRows = layout.Rows
    const lines = TextReporter.formatSeparator(color)
    table.insert(lines, if color then Ansi.bold("Code Coverage") else "Code Coverage")
    table.insert(lines, "")
    const rows: { TableRenderer.TableRow } = {}
    const sorted = CoverageReporter.sortFiles(report.Files, layout.Sort)
    for index = 1, math.min(#sorted, maxRows) do
        const file = sorted[index]
        const path, rawPath = CoverageReporter.formatPath(file.Path, color)
        const pct = percentage(file.Percentage)
        const styledPct = if color then CoverageReporter.colorPercentage(file.Percentage, pct) else pct
        const executable = CoverageReporter.formatCount(file.ExecutableLines)
        const hit = CoverageReporter.formatCount(file.HitLines)
        table.insert(rows, {
            Colored = { path, executable, hit, styledPct },
            Raw = { rawPath, executable, hit, pct },
        })
    end
    const hiddenCount = #sorted - maxRows
    if hiddenCount > 0 then
        local hiddenExecutable = 0
        local hiddenHit = 0
        for index = maxRows + 1, #sorted do
            hiddenExecutable += sorted[index].ExecutableLines
            hiddenHit += sorted[index].HitLines
        end
        const raw = {
            `{CoverageReporter.formatCount(hiddenCount)} more {if hiddenCount == 1 then "module" else "modules"}`,
            CoverageReporter.formatCount(hiddenExecutable),
            CoverageReporter.formatCount(hiddenHit),
            percentage(Coverage.percentage(hiddenHit, hiddenExecutable)),
        }
        const colored = {}
        for _, cell in raw do
            table.insert(colored, if color then Ansi.dim(cell) else cell)
        end
        table.insert(rows, { Colored = colored, Raw = raw, Separator = true })
    end
    const passed = report.TotalPercentage >= threshold
    const totalPct = percentage(report.TotalPercentage)
    const totalExecutable = CoverageReporter.formatCount(report.TotalExecutableLines)
    const totalHit = CoverageReporter.formatCount(report.TotalHitLines)
    const styledTotalPct = if not color
        then totalPct
        else if passed then Ansi.brightGreen(totalPct) else Ansi.brightRed(totalPct)
    table.insert(rows, {
        Colored = if color
            then { Ansi.bold("Total"), Ansi.bold(totalExecutable), Ansi.bold(totalHit), Ansi.bold(styledTotalPct) }
            else { "Total", totalExecutable, totalHit, totalPct },
        Raw = { "Total", totalExecutable, totalHit, totalPct },
        Separator = hiddenCount <= 0,
    })
    for _, line in TableRenderer.format({ "Script", "Executable Lines", "Hit", "Percent" }, rows, color, ALIGNMENTS) do
        table.insert(lines, line)
    end
    const pctText = if color then Ansi.boldInline(totalPct) else totalPct
    const thresholdText = if color then Ansi.boldInline(percentage(threshold)) else percentage(threshold)
    const message = if passed
        then `Coverage {pctText} meets threshold of {thresholdText}.`
        else `Coverage {pctText} is below threshold of {thresholdText}.`
    const results = {
        children = {
            {
                children = {
                    {
                        children = {},
                        planNode = { phrase = message },
                        status = if passed then TestEnum.TestStatus.Success else TestEnum.TestStatus.Failure,
                    },
                },
                planNode = { phrase = "Code Coverage" },
            },
        },
    }
    table.insert(lines, "")
    for _, line in
        TextReporter.formatTree(
            results,
            { AlphabeticalSort = false, Color = color, Indent = indent, PrintSkipped = false }
        )
    do
        table.insert(lines, line)
    end
    for _, line in TextReporter.formatSeparator(color) do
        table.insert(lines, line)
    end
    return lines
end

--[[
    Prints the formatted report. Without a layout, it uses the configured row limit and
    row order.
]]
function CoverageReporter.report(report: Coverage.CoverageReport, threshold: number, layout: Layout?)
    assert(type(report) == "table")
    assert(type(threshold) == "number")
    assert(layout == nil or type(layout) == "table")
    const resolved = layout or { Rows = Config.CoverageRows, Sort = Config.CoverageSort }
    for _, line in CoverageReporter.format(report, threshold, IS_LUNE, Config.Indent, resolved) do
        print(line)
    end
end

return CoverageReporter
