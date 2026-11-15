--[[

CoverageReporter

Formats coverage as a bordered table followed by a tree-style threshold result.

--]]

const Ansi = require("../Ansi")
const Config = require("../Config")
const Coverage = require("../Coverage")
const DisplayWidth = require("../DisplayWidth")
const TableRenderer = require("../TableRenderer")
const TestEnum = require("../TestEnum")
const TextReporter = require("./TextReporter")
const IS_LUNE = Ansi.isLune()
const MAX_PATH_LENGTH = 40

const CoverageReporter = {}

const function formatPath(path: string, color: boolean): (string, string)
    const normalized = path:gsub("\\", "/")
    local raw = normalized
    if DisplayWidth.measure(raw) > MAX_PATH_LENGTH then
        const parts = string.split(raw, "/")
        raw = table.remove(parts) :: string
        for index = #parts, 1, -1 do
            const candidate = `{parts[index]}/{raw}`
            if DisplayWidth.measure(candidate) + 4 > MAX_PATH_LENGTH then
                break
            end
            raw = candidate
        end
        raw = `.../{raw}`
    end
    const directory, filename = raw:match("^(.+/)([^/]+)$")
    return if color and directory then `{Ansi.dim(directory)}{filename}` else raw, raw
end

const function percentage(value: number): string
    return string.format("%.1f%%", value)
end

--[[
    Returns formatted lines without emitting output. The color argument makes terminal
    and plain output independently testable.
]]
function CoverageReporter.format(
    report: Coverage.CoverageReport,
    threshold: number,
    color: boolean,
    indent: string
): { string }
    assert(type(report) == "table")
    assert(type(threshold) == "number")
    assert(type(color) == "boolean")
    assert(type(indent) == "string")
    const lines = TextReporter.formatSeparator(color)
    table.insert(lines, if color then Ansi.bold("Code Coverage") else "Code Coverage")
    table.insert(lines, "")
    const rows: { TableRenderer.TableRow } = {}
    for _, file in report.Files do
        const path, rawPath = formatPath(file.Path, color)
        const pct = percentage(file.Percentage)
        const styledPct = if not color
            then pct
            else if file.Percentage >= threshold then Ansi.brightGreen(pct) else Ansi.dim(pct)
        const executable = tostring(file.ExecutableLines)
        const hit = tostring(file.HitLines)
        table.insert(rows, {
            Colored = { path, executable, hit, styledPct },
            Raw = { rawPath, executable, hit, pct },
        })
    end
    const passed = report.TotalPercentage >= threshold
    const totalPct = percentage(report.TotalPercentage)
    const totalExecutable = tostring(report.TotalExecutableLines)
    const totalHit = tostring(report.TotalHitLines)
    const styledTotalPct = if not color
        then totalPct
        else if passed then Ansi.brightGreen(totalPct) else Ansi.brightRed(totalPct)
    table.insert(rows, {
        Colored = if color
            then { Ansi.bold("Total"), Ansi.bold(totalExecutable), Ansi.bold(totalHit), Ansi.bold(styledTotalPct) }
            else { "Total", totalExecutable, totalHit, totalPct },
        Raw = { "Total", totalExecutable, totalHit, totalPct },
        Separator = true,
    })
    for _, line in TableRenderer.format({ "Script", "Executable Lines", "Hit", "Percent" }, rows, color) do
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

function CoverageReporter.report(report: Coverage.CoverageReport, threshold: number)
    assert(type(report) == "table")
    assert(type(threshold) == "number")
    for _, line in CoverageReporter.format(report, threshold, IS_LUNE, Config.Indent) do
        print(line)
    end
end

return CoverageReporter
