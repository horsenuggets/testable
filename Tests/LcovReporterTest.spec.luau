--[[

LcovReporterTest.spec

Tests for the lcov reporter, and for the per-line hit data that Coverage.collect records
for it.

--]]

const Coverage = require("../Source/Testable/Coverage")
const LcovReporter = require("../Source/Testable/Reporters/LcovReporter")
const SampleModule = require("./CoverageFixtures/SampleModule")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it
const fixturesDir = script.Parent.CoverageFixtures

const function file(path: string, lineHits: { [number]: number }?): any
    return { ExecutableLines = 0, Functions = {}, HitLines = 0, LineHits = lineHits, Name = path, Path = path }
end

const function report(files: { any }): any
    return { Files = files, TotalExecutableLines = 0, TotalHitLines = 0, TotalPercentage = 0 }
end

--[[
    Splits a tracefile into its records, each a list of lines without the end marker.
]]
const function records(tracefile: string): { { string } }
    const result = {}
    local current = {}
    for _, line in string.split(tracefile, "\n") do
        if line == "end_of_record" then
            table.insert(result, current)
            current = {}
        elseif line ~= "" then
            table.insert(current, line)
        end
    end
    assert(#current == 0, "The tracefile has lines after its last record.")
    return result
end

return function()
    describe("LcovReporter.format", function()
        it("should write one record per file with its lines in order", function()
            const tracefile = LcovReporter.format(report({
                file("Source/Module.luau", { [12] = 3, [3] = 0, [7] = 1 })
            }))
            expect(tracefile).to.equal(table.concat({
                "TN:",
                "SF:Source/Module.luau",
                "DA:3,0",
                "DA:7,1",
                "DA:12,3",
                "LF:3",
                "LH:2",
                "end_of_record",
                ""
            }, "\n"))
        end)

        it("should order records by path", function()
            const parsed = records(LcovReporter.format(report({
                file("Source/Zebra.luau", { [1] = 1 }),
                file("Source/Apple.luau", { [1] = 0 })
            })))
            expect(#parsed).to.equal(2)
            expect(parsed[1][2]).to.equal("SF:Source/Apple.luau")
            expect(parsed[2][2]).to.equal("SF:Source/Zebra.luau")
        end)

        it("should count only lines with hits as hit", function()
            const parsed = records(LcovReporter.format(report({
                file("Source/Unloaded.luau", { [1] = 0, [2] = 0 })
            })))
            expect(parsed[1][5]).to.equal("LF:2")
            expect(parsed[1][6]).to.equal("LH:0")
        end)

        it("should write an empty record for a file without line data", function()
            for _, lineHits in { {}, nil } :: { any } do
                const parsed = records(LcovReporter.format(report({ file("Source/Empty.luau", lineHits) })))
                expect(table.concat(parsed[1], "\n")).to.equal("TN:\nSF:Source/Empty.luau\nLF:0\nLH:0")
            end
        end)

        it("should write an empty tracefile for a report without files", function()
            expect(LcovReporter.format(report({}))).to.equal("")
        end)

        it("should use forward slashes and keep paths on one line", function()
            const parsed = records(LcovReporter.format(report({ file("Source\\Nested\\Odd\nName.luau", {}) })))
            expect(parsed[1][2]).to.equal("SF:Source/Nested/OddName.luau")
        end)

        it("should not reorder the report's files", function()
            const input = report({ file("Source/Zebra.luau", {}), file("Source/Apple.luau", {}) })
            LcovReporter.format(input)
            expect(input.Files[1].Path).to.equal("Source/Zebra.luau")
        end)

        it("should produce the same text for the same report", function()
            const input = report({ file("Source/Module.luau", { [5] = 2, [1] = 0, [9] = 4, [2] = 1 }) })
            expect(LcovReporter.format(input)).to.equal(LcovReporter.format(input))
        end)
    end)

    describe("Coverage.collect line hits", function()
        it("should record a hit count for every executable line", function()
            SampleModule.add(1, 2)
            const collected = Coverage.collect(fixturesDir.SampleModule)
            if collected == nil then
                return
            end

            const sample = collected.Files[1]
            local lines = 0
            local hit = 0
            for lineNumber, hits in sample.LineHits do
                expect(lineNumber >= 1 and lineNumber % 1 == 0).to.equal(true)
                expect(hits >= 0).to.equal(true)
                lines += 1
                if hits > 0 then
                    hit += 1
                end
            end
            expect(lines).to.equal(sample.ExecutableLines)
            expect(hit).to.equal(sample.HitLines)
            expect(hit > 0).to.equal(true)
            expect(hit < lines).to.equal(true)
        end)

        it("should record zero hits for every line of a module that never ran", function()
            const collected = Coverage.collect(fixturesDir.UnrequiredModule)
            if collected == nil then
                return
            end

            const unrequired = collected.Files[1]
            local lines = 0
            for _, hits in unrequired.LineHits do
                expect(hits).to.equal(0)
                lines += 1
            end
            expect(lines).to.equal(unrequired.ExecutableLines)
            expect(lines > 0).to.equal(true)
        end)

        it("should render collected coverage as a tracefile that agrees with the report", function()
            SampleModule.add(1, 2)
            const collected = Coverage.collect(fixturesDir.SampleModule)
            if collected == nil then
                return
            end

            const parsed = records(LcovReporter.format(collected))
            expect(#parsed).to.equal(1)
            const record = parsed[1]
            expect(record[2]).to.equal("SF:Tests/CoverageFixtures/SampleModule.luau")
            expect(record[#record - 1]).to.equal(`LF:{collected.Files[1].ExecutableLines}`)
            expect(record[#record]).to.equal(`LH:{collected.Files[1].HitLines}`)
            expect(#record).to.equal(collected.Files[1].ExecutableLines + 4)
        end)
    end)
end
