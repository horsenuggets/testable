--[[

LcovReporter

Renders a coverage report as an lcov tracefile, the format that coverage services and
editor gutters read. Each file becomes one record with a DA line per executable line and
its hit count, followed by the LF and LH totals.

--]]

const Coverage = require("../Coverage")

const LcovReporter = {}

--[[
    Returns the lcov tracefile for the given coverage report without emitting anything.
    Records are ordered by path and lines by number, so the same report always produces
    the same text.
]]
function LcovReporter.format(report: Coverage.CoverageReport): string
    assert(type(report) == "table")
    assert(type(report.Files) == "table")
    const files = table.clone(report.Files)
    table.sort(files, function(a, b)
        return a.Path < b.Path
    end)

    const lines = {}
    for _, file in files do
        assert(type(file.Path) == "string")
        const lineHits: { [number]: number } = file.LineHits or {}
        const lineNumbers = {}
        for lineNumber in lineHits do
            table.insert(lineNumbers, lineNumber)
        end
        table.sort(lineNumbers)

        -- Record fields end at a newline, so a path can't contain one. Backslashes
        -- become slashes so reports from Windows match the paths in the repository.
        const path = file.Path:gsub("\\", "/"):gsub("[\r\n]", "")
        table.insert(lines, "TN:")
        table.insert(lines, `SF:{path}`)
        local hitLines = 0
        for _, lineNumber in lineNumbers do
            const hits = math.max(math.floor(lineHits[lineNumber]), 0)
            if hits > 0 then
                hitLines += 1
            end
            table.insert(lines, `DA:{lineNumber},{hits}`)
        end
        table.insert(lines, `LF:{#lineNumbers}`)
        table.insert(lines, `LH:{hitLines}`)
        table.insert(lines, "end_of_record")
    end
    -- A tracefile ends with a newline after its last record.
    table.insert(lines, "")
    return table.concat(lines, "\n")
end

return LcovReporter
