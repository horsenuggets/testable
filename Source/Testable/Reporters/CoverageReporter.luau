--[[

CoverageReporter

Formats and prints code coverage results to standard output.

--]]

local Ansi = require("../Ansi")
local Coverage = require("../Coverage")

local IS_LUNE = Ansi.isLune()

local CoverageReporter = {}

local function formatStatus(pct: number, threshold: number): string
    if pct >= threshold then
        return if IS_LUNE then Ansi.brightGreen("PASS") else "PASS"
    elseif pct >= 50 then
        return if IS_LUNE then Ansi.brightYellow("WARN") else "WARN"
    else
        return if IS_LUNE then Ansi.brightRed("FAIL") else "FAIL"
    end
end

local function formatPercentage(pct: number, threshold: number): string
    local text = `{pct}%`
    if not IS_LUNE then
        return text
    end
    if pct >= threshold then
        return Ansi.brightGreen(text)
    elseif pct >= 50 then
        return Ansi.brightYellow(text)
    else
        return Ansi.brightRed(text)
    end
end

--[[
    Reports coverage results to standard output.

    @param report - The coverage report from Coverage.collect
    @param threshold - The minimum coverage percentage to pass
]]
function CoverageReporter.report(report: Coverage.CoverageReport, threshold: number)
    print("")
    print("Code Coverage Report")
    print(string.rep("-", 60))

    local header = string.format("%-30s %6s %6s %6s   %s", "File", "Lines", "Hit", "Pct", "Status")
    print(header)
    print(string.rep("-", 60))

    for _, file in report.Files do
        local statusText = formatStatus(file.Percentage, threshold)
        local pctText = formatPercentage(file.Percentage, threshold)

        print(
            string.format("%-30s %6d %6d %6s   %s", file.Name, file.ExecutableLines, file.HitLines, pctText, statusText)
        )
    end

    print(string.rep("-", 60))

    local totalPctText = formatPercentage(report.TotalPercentage, threshold)
    print(string.format("%-30s %6d %6d %6s", "TOTAL", report.TotalExecutableLines, report.TotalHitLines, totalPctText))
    print("")

    if report.TotalPercentage < threshold then
        local msg = `Coverage {report.TotalPercentage}% is below threshold of {threshold}%.`
        print(if IS_LUNE then Ansi.brightRed(msg) else msg)
    else
        local msg = `Coverage {report.TotalPercentage}% meets threshold of {threshold}%.`
        print(if IS_LUNE then Ansi.brightGreen(msg) else msg)
    end
end

return CoverageReporter
