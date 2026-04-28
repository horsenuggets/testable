--[[

CoverageReporter

Formats and prints code coverage results to standard output using a bordered table,
followed by a tree-style threshold result.

--]]

local Ansi = require("../Ansi")
local Coverage = require("../Coverage")
local TableRenderer = require("../TableRenderer")
local TestEnum = require("../TestEnum")
local TextReporter = require("./TextReporter")

local IS_LUNE = Ansi.isLune()

local SEPARATOR = string.rep("─", 64)
local MAX_PATH_LENGTH = 40

local CoverageReporter = {}

local function formatPercentage(pct: number, threshold: number): (string, string)
    local raw = string.format("%.1f%%", pct)
    if not IS_LUNE then
        return raw, raw
    end
    return (if pct >= threshold then Ansi.brightGreen(raw) else Ansi.dim(raw)), raw
end

local function formatTotalPercentage(pct: number, threshold: number): (string, string)
    local raw = string.format("%.1f%%", pct)
    if not IS_LUNE then
        return raw, raw
    end
    return (if pct >= threshold then Ansi.brightGreen(raw) else Ansi.brightRed(raw)), raw
end

local function bold(text: string): string
    return if IS_LUNE then Ansi.bold(text) else text
end

local function dim(text: string): string
    return if IS_LUNE then Ansi.dim(text) else text
end

local function separator()
    print("")
    print(if IS_LUNE then Ansi.dim(SEPARATOR) else SEPARATOR)
    print("")
end

--[[
    Formats a file path for display. The directory portion is dim and the
    filename is default (white). Paths longer than MAX_PATH_LENGTH are
    truncated from the start with dim ellipsis.

    @param path - The full file path (e.g. "Source/Testable/Reporters/TextReporter.luau")
    @return colored - The ANSI-colored path string
    @return raw - The plain text path string (for width calculation)
]]
local function formatPath(path: string): (string, string)
    -- Truncate if too long
    local raw = path
    if #raw > MAX_PATH_LENGTH then
        raw = `...{raw:sub(#raw - MAX_PATH_LENGTH + 4)}`
    end

    if not IS_LUNE then
        return raw, raw
    end

    -- Split into directory and filename
    local dir, filename = raw:match("^(.+/)([^/]+)$")
    if dir then
        return `{dim(dir)}{filename}`, raw
    end

    -- No directory — check if truncated (starts with ...)
    local ellipsis, rest = raw:match("^(%.%.%.)(.*)")
    if ellipsis then
        return `{dim(ellipsis)}{rest}`, raw
    end

    return raw, raw
end

--[[
    Reports coverage results to standard output.

    @param report - The coverage report from Coverage.collect
    @param threshold - The minimum coverage percentage to pass
]]
function CoverageReporter.report(report: Coverage.CoverageReport, threshold: number)
    separator()

    print(bold("Code Coverage"))
    print("")

    local headers = { "Script", "Executable Lines", "Hit", "Percent" }
    local rows: { TableRenderer.TableRow } = {}

    for _, file in report.Files do
        local coloredPct, rawPct = formatPercentage(file.Percentage, threshold)
        local rawLines = tostring(file.ExecutableLines)
        local rawHit = tostring(file.HitLines)
        local coloredPath, rawPath = formatPath(file.Path)

        table.insert(rows, {
            Raw = { rawPath, rawLines, rawHit, rawPct },
            Colored = { coloredPath, rawLines, rawHit, coloredPct },
        })
    end

    -- Total row with separator and bold styling
    local totalColoredPct, totalRawPct = formatTotalPercentage(report.TotalPercentage, threshold)
    local totalRawLines = tostring(report.TotalExecutableLines)
    local totalRawHit = tostring(report.TotalHitLines)

    table.insert(rows, {
        Raw = { "Total", totalRawLines, totalRawHit, totalRawPct },
        Colored = {
            bold("Total"),
            bold(totalRawLines),
            bold(totalRawHit),
            bold(totalColoredPct),
        },
        Separator = true,
    })

    TableRenderer.render(headers, rows)

    -- Show threshold result as a mini test tree
    local passed = report.TotalPercentage >= threshold
    local status = if passed then TestEnum.TestStatus.Success else TestEnum.TestStatus.Failure

    -- Use boldInline so the bold doesn't reset the surrounding green/red color
    local pctBold = if IS_LUNE then Ansi.boldInline(string.format("%.1f%%", report.TotalPercentage)) else string.format("%.1f%%", report.TotalPercentage)
    local thresholdBold = if IS_LUNE then Ansi.boldInline(string.format("%.1f%%", threshold)) else string.format("%.1f%%", threshold)
    local message = if passed
        then `Coverage {pctBold} meets threshold of {thresholdBold}.`
        else `Coverage {pctBold} is below threshold of {thresholdBold}.`

    local mockResults = {
        planNode = { phrase = "Root" },
        children = {
            {
                planNode = { phrase = "Code Coverage" },
                status = nil,
                children = {
                    {
                        planNode = { phrase = message },
                        status = status,
                        children = {},
                    },
                },
            },
        },
    }

    print("")
    TextReporter.renderTree(mockResults)

    separator()
end

return CoverageReporter
