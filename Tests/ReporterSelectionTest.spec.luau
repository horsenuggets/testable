--[[

ReporterSelectionTest.spec

Tests for choosing reporters and delivering their output. The selection logic and the
delivery are checked in-process with replaced sinks, and whole runs are checked in a
subprocess to prove that standard output carries nothing but the machine-readable report.

--]]

const Config = require("../Source/Testable/Config")
const JUnitReporter = require("../Source/Testable/Reporters/JUnitReporter")
const JsonReporter = require("../Source/Testable/Reporters/JsonReporter")
const LcovReporter = require("../Source/Testable/Reporters/LcovReporter")
const ReporterSelection = require("../Source/Testable/Reporters/ReporterSelection")
const ResultFixture = require("./Helpers/ResultFixture")
const Subprocess = require("./Helpers/Subprocess")
const Xml = require("./Helpers/Xml")
const fs = require("@lune/fs")
const serde = require("@lune/serde")
const COVERAGE_REPORT = {
    Files = {
        {
            ExecutableLines = 1,
            Functions = {},
            HitLines = 1,
            LineHits = { [1] = 1 },
            Name = "A",
            Path = "Source/A.luau",
        },
    },
    TotalExecutableLines = 1,
    TotalHitLines = 1,
    TotalPercentage = 100,
}
const MACHINE_REPORTERS = { "JUnit", "Json", "Lcov" }
const GUARD_SCRIPT = [[
    const StandardOutputGuard = require("./Source/Testable/Reporters/StandardOutputGuard")

    print("BEFORE")
    const value = StandardOutputGuard.run(true, function()
        print("INSIDE")
        return "RESULT"
    end)
    print(value)
    const ok, message = pcall(StandardOutputGuard.run, true, function()
        print("FAILING")
        error("guarded failure", 0)
    end)
    print(`AFTER|{tostring(ok)}|{tostring(message)}`)
    StandardOutputGuard.run(false, function()
        print("INACTIVE")
    end)

    const outer = StandardOutputGuard.redirect()
    const inner = StandardOutputGuard.redirect()
    inner()
    inner()
    print("STILL GUARDED")
    outer()
    print("RELEASED")
]]
const NOISY_TEMPLATE = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")

    Testable.configure({ Parallel = %s, Reporters = { "%s" }, Verbose = true })

    const _, passed = Testable.run({
        {
            Name = "NoisySpec",
            Func = function()
                print("PLANNING NOISE")
                it("prints", function()
                    task.wait(0.01)
                    print("TEST NOISE", { Nested = true })
                end)
                it("runs a nested suite", function()
                    Testable.configure({ Reporters = { "Text" }, Verbose = false })
                    Testable.run({
                        {
                            Name = "NestedSpec",
                            Func = function()
                                it("nested test", function() end)
                            end,
                        },
                    })
                end)
            end,
        },
    })
    process.exit(if passed then 0 else 1)
]]
const RUN_TEMPLATE = [[
    const process = require("@lune/process")
    const Testable = require("./Source/Testable")

    Testable.configure(%s)

    const _, passed = Testable.run({
        {
            Name = "SampleSpec",
            Func = function()
                describe("group <&>", function()
                    it("passes", function()
                        require("@lune/task").wait(0.02)
                        expect(1).to.equal(1)
                    end)
                    it("fails", function()
                        error("deliberate failure")
                    end)
                    xit("is skipped", function() end)
                end)
            end,
        },
    })
    process.exit(if passed then 0 else 1)
]]

local directoryCounter = 0

--[[
    Runs a callback with a fresh folder for report files, relative to the project root,
    and removes the folder afterward even when the callback fails.
]]
const function withReportFolder(callback: (folder: string) -> ())
    directoryCounter += 1
    const folder = `_temp_reports_{os.time()}_{directoryCounter}_{math.random(100000, 999999)}`
    const ok, message = pcall(callback, folder)
    if fs.isDir(folder) then
        fs.removeDir(folder)
    end
    assert(ok, message)
end

const function run(configuration: string): (boolean, string)
    return Subprocess.runScript(string.format(RUN_TEMPLATE, configuration))
end

const function hasError(callback: () -> (), text: string): boolean
    const ok, message = pcall(callback)
    return not ok and string.find(tostring(message), text, 1, true) ~= nil
end

--[[
    Builds sinks that record what was delivered instead of printing or writing it.
]]
const function recordingSinks(): (ReporterSelection.Sinks, { string }, { [string]: string })
    const printed = {}
    const written = {}
    return {
        Print = function(contents: string)
            table.insert(printed, contents)
        end,
        WriteFile = function(path: string, contents: string)
            written[path] = contents
        end,
    },
        printed,
        written
end

return function()
    describe("ReporterSelection.resolve", function()
        it("should select only the text report by default", function()
            const selection = ReporterSelection.resolve({ "Text" }, {})
            expect(selection.Text).to.equal(true)
            expect(selection.NeedsCoverage).to.equal(false)
            expect(#selection.Outputs).to.equal(0)
        end)

        it("should select nothing for an empty list", function()
            const selection = ReporterSelection.resolve({}, {})
            expect(selection.Text).to.equal(false)
            expect(#selection.Outputs).to.equal(0)
        end)

        it("should keep machine-readable reporters in the order they were listed", function()
            const outputs = { JUnit = "junit.xml", Json = "results.json", Lcov = "lcov.info" }
            const selection = ReporterSelection.resolve({ "Lcov", "Text", "Json", "JUnit" }, outputs)
            expect(selection.Text).to.equal(true)
            expect(#selection.Outputs).to.equal(3)
            expect(selection.Outputs[1].Reporter).to.equal("Lcov")
            expect(selection.Outputs[1].Path).to.equal("lcov.info")
            expect(selection.Outputs[2].Reporter).to.equal("Json")
            expect(selection.Outputs[2].Path).to.equal("results.json")
            expect(selection.Outputs[3].Reporter).to.equal("JUnit")
            expect(selection.Outputs[3].Path).to.equal("junit.xml")
        end)

        it("should need coverage exactly when the lcov reporter is selected", function()
            expect(ReporterSelection.resolve({ "Lcov" }, {}).NeedsCoverage).to.equal(true)
            expect(ReporterSelection.resolve({ "Json" }, { Lcov = "lcov.info" }).NeedsCoverage).to.equal(false)
        end)

        it("should ignore paths of reporters that aren't selected", function()
            const selection = ReporterSelection.resolve({ "Text" }, { Json = "results.json" })
            expect(selection.Text).to.equal(true)
            expect(#selection.Outputs).to.equal(0)
        end)

        it("should let exactly one report use standard output in every combination", function()
            -- Walks every subset of the reporters with every choice of which
            -- machine-readable ones have a path. A combination is valid exactly when at
            -- most one selected reporter is left writing to standard output.
            for textSelected = 0, 1 do
                for selectedMask = 0, 7 do
                    for pathMask = 0, 7 do
                        const reporters = if textSelected == 1 then { "Text" } else {}
                        const outputs = {}
                        local onStandardOutput = textSelected
                        for index, name in MACHINE_REPORTERS do
                            const bit = bit32.lshift(1, index - 1)
                            const selected = bit32.band(selectedMask, bit) ~= 0
                            const hasPath = bit32.band(pathMask, bit) ~= 0
                            if selected then
                                table.insert(reporters, name)
                            end
                            if hasPath then
                                outputs[name] = `{name}.out`
                            end
                            if selected and not hasPath then
                                onStandardOutput += 1
                            end
                        end

                        const ok, selection = pcall(ReporterSelection.resolve, reporters, outputs)
                        expect(ok).to.equal(onStandardOutput <= 1)
                        if ok then
                            local withoutPath = if selection.Text then 1 else 0
                            for _, output in selection.Outputs do
                                if output.Path == nil then
                                    withoutPath += 1
                                end
                            end
                            expect(withoutPath).to.equal(onStandardOutput)
                            expect(selection.Text).to.equal(textSelected == 1)
                        end
                    end
                end
            end
        end)

        it("should explain how to fix a standard output conflict", function()
            expect(hasError(function()
                ReporterSelection.resolve({ "Text", "Json" }, {})
            end, 'The "Text" and "Json" reporters would both write to standard output')).to.equal(true)
            expect(hasError(function()
                ReporterSelection.resolve({ "Json", "JUnit" }, {})
            end, 'The "Json" and "JUnit" reporters would both write to standard output')).to.equal(true)
        end)

        it("should reject unknown, repeated, and misconfigured reporters", function()
            expect(hasError(function()
                ReporterSelection.resolve({ "Tap" }, {})
            end, '"Tap" is not a reporter')).to.equal(true)
            expect(hasError(function()
                ReporterSelection.resolve({ "Json", "Json" }, {})
            end, "listed more than once")).to.equal(true)
            expect(hasError(function()
                ReporterSelection.resolve({ "Text" }, { Text = "report.txt" })
            end, "can't have an output path")).to.equal(true)
            expect(hasError(function()
                ReporterSelection.resolve({ "Text" }, { Tap = "report.tap" })
            end, "which is not a reporter")).to.equal(true)
            expect(hasError(function()
                ReporterSelection.resolve({ "Json" }, { Json = "" })
            end, "must be a non-empty string")).to.equal(true)
            expect(hasError(function()
                ReporterSelection.resolve({ "Json", "JUnit" }, { JUnit = "same.out", Json = "same.out" })
            end, 'would both write to "same.out"')).to.equal(true)
        end)

        it("should name the reporter that owns standard output", function()
            expect(ReporterSelection.resolve({ "Text" }, {}).StandardOutput).to.equal(nil)
            expect(ReporterSelection.resolve({ "Json" }, {}).StandardOutput).to.equal("Json")
            expect(ReporterSelection.resolve({ "Json" }, { Json = "results.json" }).StandardOutput).to.equal(nil)
            expect(ReporterSelection.resolve({ "Json", "JUnit" }, { Json = "results.json" }).StandardOutput).to.equal(
                "JUnit"
            )
        end)

        it("should treat different spellings of one file as the same output", function()
            const spellings = {
                "./reports/same.out",
                "reports//same.out",
                "reports/./same.out",
                "reports/nested/../same.out",
                "reports\\same.out",
            }
            for _, spelling in spellings do
                expect(hasError(function()
                    ReporterSelection.resolve({ "Json", "JUnit" }, { JUnit = spelling, Json = "reports/same.out" })
                end, `would both write to "{spelling}"`)).to.equal(true)
            end
        end)

        it("should keep the configured spelling of distinct output paths", function()
            const outputs = { JUnit = "./reports/junit.out", Json = "reports/nested/../json.out" }
            const selection = ReporterSelection.resolve({ "Json", "JUnit" }, outputs)
            expect(selection.Outputs[1].Path).to.equal("reports/nested/../json.out")
            expect(selection.Outputs[2].Path).to.equal("./reports/junit.out")
        end)

        it("should return equal selections for equal input", function()
            const first = ReporterSelection.resolve({ "Text", "Json" }, { Json = "results.json" })
            const second = ReporterSelection.resolve({ "Text", "Json" }, { Json = "results.json" })
            expect(serde.encode("json", first)).to.equal(serde.encode("json", second))
        end)
    end)

    describe("ReporterSelection.emit", function()
        it("should write each report to its file and print nothing", function()
            const sinks, printed, written = recordingSinks()
            const outputs = { JUnit = "out/junit.xml", Json = "out/results.json", Lcov = "out/lcov.info" }
            const selection = ReporterSelection.resolve({ "Text", "Json", "JUnit", "Lcov" }, outputs)
            ReporterSelection.emit(selection, ResultFixture.mixed(), COVERAGE_REPORT, sinks)
            expect(#printed).to.equal(0)
            expect(written["out/results.json"]).to.equal(JsonReporter.format(ResultFixture.mixed()))
            expect(written["out/junit.xml"]).to.equal(JUnitReporter.format(ResultFixture.mixed()))
            expect(written["out/lcov.info"]).to.equal(LcovReporter.format(COVERAGE_REPORT))
        end)

        it("should print the one report without a path", function()
            const sinks, printed, written = recordingSinks()
            const selection = ReporterSelection.resolve({ "Json", "JUnit" }, { JUnit = "junit.xml" })
            ReporterSelection.emit(selection, ResultFixture.mixed(), nil, sinks)
            expect(#printed).to.equal(1)
            expect(printed[1]).to.equal(JsonReporter.format(ResultFixture.mixed()))
            expect(written["junit.xml"] ~= nil).to.equal(true)
        end)

        it("should deliver nothing when only the text reporter is selected", function()
            const sinks, printed, written = recordingSinks()
            ReporterSelection.emit(ReporterSelection.resolve({ "Text" }, {}), ResultFixture.mixed(), nil, sinks)
            expect(#printed).to.equal(0)
            expect(next(written)).to.equal(nil)
        end)

        it("should fail when the lcov reporter has no coverage data", function()
            const sinks = recordingSinks()
            expect(hasError(function()
                ReporterSelection.emit(ReporterSelection.resolve({ "Lcov" }, {}), ResultFixture.mixed(), nil, sinks)
            end, "needs coverage data")).to.equal(true)
        end)

        it("should refuse to render the text reporter", function()
            expect(hasError(function()
                ReporterSelection.render("Text", ResultFixture.mixed(), nil)
            end, "is not a machine-readable reporter")).to.equal(true)
        end)
    end)

    describe("Config", function()
        afterEach(function()
            Config.reset()
        end)

        it("should default to the text reporter with no output paths", function()
            expect(#Config.Reporters).to.equal(1)
            expect(Config.Reporters[1]).to.equal("Text")
            expect(next(Config.ReporterOutputs)).to.equal(nil)
            expect(Config.SlowestTests).to.equal(0)
        end)

        it("should set and reset the reporter options", function()
            Config.set({ ReporterOutputs = { Json = "results.json" }, Reporters = { "Json", "Text" }, SlowestTests = 5 })
            expect(Config.Reporters[1]).to.equal("Json")
            expect(Config.Reporters[2]).to.equal("Text")
            expect(Config.ReporterOutputs.Json).to.equal("results.json")
            expect(Config.SlowestTests).to.equal(5)

            Config.reset()
            expect(#Config.Reporters).to.equal(1)
            expect(Config.Reporters[1]).to.equal("Text")
            expect(next(Config.ReporterOutputs)).to.equal(nil)
            expect(Config.SlowestTests).to.equal(0)
        end)

        it("should copy the tables it is given", function()
            const reporters: { Config.Reporter } = { "Json" }
            const outputs = { Json = "results.json" }
            Config.set({ ReporterOutputs = outputs, Reporters = reporters })
            table.insert(reporters, "Text")
            outputs.Json = "changed.json"
            expect(#Config.Reporters).to.equal(1)
            expect(Config.ReporterOutputs.Json).to.equal("results.json")
        end)

        it("should not share the default reporter list between resets", function()
            table.insert(Config.Reporters, "Json")
            Config.reset()
            expect(#Config.Reporters).to.equal(1)
        end)

        it("should reject invalid reporter options", function()
            const invalid: { any } = {
                { Reporters = "Json" },
                { Reporters = { "Tap" } },
                { Reporters = { 1 } },
                { ReporterOutputs = "results.json" },
                { ReporterOutputs = { Text = "report.txt" } },
                { ReporterOutputs = { Tap = "report.tap" } },
                { ReporterOutputs = { Json = "" } },
                { ReporterOutputs = { Json = 5 } },
                { SlowestTests = -1 },
                { SlowestTests = 1.5 },
                { SlowestTests = "3" },
            }
            for _, options in invalid do
                expect(function()
                    Config.set(options)
                end).to.throw()
            end
            expect(#Config.Reporters).to.equal(1)
            expect(next(Config.ReporterOutputs)).to.equal(nil)
            expect(Config.SlowestTests).to.equal(0)
        end)
    end)

    describe("StandardOutputGuard", function()
        it("should redirect printed output only while it is active", function()
            const ok, standardOutput, standardError = Subprocess.runScriptStreams(GUARD_SCRIPT)
            expect(ok).to.equal(true)
            expect(standardOutput).to.equal("BEFORE\nRESULT\nAFTER|false|guarded failure\nINACTIVE\nRELEASED\n")
            expect(standardError).to.equal("INSIDE\nFAILING\nSTILL GUARDED\n")
        end)
    end)

    describe("Testable.run", function()
        it("should print only JSON to standard output when it is the only reporter", function()
            const ok, output = run('{ Reporters = { "Json" } }')
            expect(ok).to.equal(false)

            const document = serde.decode("json", output)
            expect(document.Totals.Total).to.equal(3)
            expect(document.Totals.Passed).to.equal(1)
            expect(document.Totals.Failed).to.equal(1)
            expect(document.Totals.Skipped).to.equal(1)

            const group = document.Suites[1].Children[1]
            expect(group.FullName).to.equal("SampleSpec > group <&>")
            expect(group.Children[1].Status).to.equal("Success")
            expect(group.Children[1].Duration >= 0.02).to.equal(true)
            expect(group.Children[2].Status).to.equal("Failure")
            expect(string.find(group.Children[2].ErrorMessage, "deliberate failure", 1, true) ~= nil).to.equal(true)
            expect(group.Children[3].Status).to.equal("Skipped")
            expect(group.Duration >= group.Children[1].Duration).to.equal(true)
            expect(document.Totals.Duration >= group.Duration).to.equal(true)
        end)

        it("should print only JUnit XML to standard output when it is the only reporter", function()
            const ok, output = run('{ Reporters = { "JUnit" } }')
            expect(ok).to.equal(false)

            -- The parser rejects text outside of the root element, so this also proves
            -- that nothing else was printed.
            const root = Xml.parse(output)
            expect(root.Attributes.tests).to.equal("3")
            expect(root.Attributes.failures).to.equal("1")
            expect(root.Attributes.skipped).to.equal("1")
            expect(root.Children[1].Children[1].Attributes.classname).to.equal("SampleSpec > group <&>")
        end)

        for _, parallel in { true, false } do
            const mode = if parallel then "parallel" else "sequential"

            it(`should keep printed output off standard output with {mode} execution`, function()
                const script = string.format(NOISY_TEMPLATE, tostring(parallel), "Json")
                const ok, standardOutput, standardError = Subprocess.runScriptStreams(script)
                expect(ok).to.equal(true)

                -- Planning output, test output, verbose logging, and the nested run's
                -- text report would each make this fail to decode.
                const document = serde.decode("json", standardOutput)
                expect(document.Totals.Total).to.equal(2)
                expect(document.Totals.Passed).to.equal(2)
                expect(document.Suites[1].Name).to.equal("NoisySpec")
                expect(standardOutput:sub(1, 1)).to.equal("{")

                for _, noise in { "PLANNING NOISE", "TEST NOISE", "Nested", "[Testable]", "NestedSpec", "1 passed" } do
                    expect(standardError:find(noise, 1, true) ~= nil).to.equal(true)
                    expect(standardOutput:find(noise, 1, true)).to.equal(nil)
                end
            end)
        end

        it("should keep printed output out of JUnit XML on standard output", function()
            const script = string.format(NOISY_TEMPLATE, "true", "JUnit")
            const ok, standardOutput, standardError = Subprocess.runScriptStreams(script)
            expect(ok).to.equal(true)
            expect(Xml.parse(standardOutput).Attributes.tests).to.equal("2")
            expect(standardError:find("TEST NOISE", 1, true) ~= nil).to.equal(true)
        end)

        it("should leave printed output alone when no report uses standard output", function()
            withReportFolder(function(folder)
                const script = string.format(NOISY_TEMPLATE, "true", "Json"):gsub(
                    'Reporters = { "Json" }, Verbose = true',
                    `ReporterOutputs = \{ Json = "{folder}/results.json" }, Reporters = \{ "Json" }`
                )
                const ok, standardOutput, standardError = Subprocess.runScriptStreams(script)
                expect(ok).to.equal(true)
                expect(standardOutput:find("PLANNING NOISE", 1, true) ~= nil).to.equal(true)
                expect(standardOutput:find("TEST NOISE", 1, true) ~= nil).to.equal(true)
                expect(standardError).to.equal("")
                expect(serde.decode("json", fs.readFile(`{folder}/results.json`)).Totals.Total).to.equal(2)
            end)
        end)

        it("should keep the text report and write the other reports to files", function()
            withReportFolder(function(folder)
                const configuration = string.format(
                    '{ ReporterOutputs = { JUnit = "%s/nested/junit.xml", Json = "%s/results.json" }, '
                        .. 'Reporters = { "Text", "Json", "JUnit" } }',
                    folder,
                    folder
                )
                const ok, output = run(configuration)
                expect(ok).to.equal(false)
                expect(string.find(output, "Unit Tests", 1, true) ~= nil).to.equal(true)
                expect(string.find(output, "1 passed", 1, true) ~= nil).to.equal(true)
                expect(string.find(output, '"Version"', 1, true)).to.equal(nil)
                expect(string.find(output, "<testsuites", 1, true)).to.equal(nil)

                const document = serde.decode("json", fs.readFile(`{folder}/results.json`))
                expect(document.Totals.Total).to.equal(3)
                const root = Xml.parse(fs.readFile(`{folder}/nested/junit.xml`))
                expect(root.Attributes.tests).to.equal("3")
            end)
        end)

        it("should print nothing when every reporter writes to a file", function()
            withReportFolder(function(folder)
                const ok, output = run(
                    string.format('{ ReporterOutputs = { Json = "%s/results.json" }, Reporters = { "Json" } }', folder)
                )
                expect(ok).to.equal(false)
                expect(output).to.equal("")
                expect(fs.isFile(`{folder}/results.json`)).to.equal(true)
            end)
        end)

        it("should write an lcov tracefile when coverage is enabled", function()
            if type(debug.iscoverageenabled) ~= "function" or not debug.iscoverageenabled() then
                return
            end
            withReportFolder(function(folder)
                const configuration = string.format(
                    "{ Coverage = true, CoverageRoots = script.Parent.Tests.CoverageFixtures, "
                        .. 'ReporterOutputs = { Lcov = "%s/lcov.info" }, Reporters = { "Lcov" } }',
                    folder
                )
                const _, output = run(configuration)
                expect(output).to.equal("")
                const tracefile = fs.readFile(`{folder}/lcov.info`)
                expect(string.find(tracefile, "SF:Tests/CoverageFixtures/SampleModule.luau", 1, true) ~= nil).to.equal(
                    true
                )
                expect(string.find(tracefile, "\nDA:%d+,0\n") ~= nil).to.equal(true)
                expect(tracefile:sub(-14)).to.equal("end_of_record\n")
            end)
        end)

        it("should fail before running tests when lcov is selected without coverage", function()
            const ok, output = run('{ Reporters = { "Lcov" } }')
            expect(ok).to.equal(false)
            expect(string.find(output, "needs Coverage enabled and CoverageRoots set", 1, true) ~= nil).to.equal(true)
        end)

        it("should fail before running tests when two reports would share standard output", function()
            const ok, output = run('{ Reporters = { "Text", "Json" } }')
            expect(ok).to.equal(false)
            expect(string.find(output, "would both write to standard output", 1, true) ~= nil).to.equal(true)
            expect(string.find(output, "Unit Tests", 1, true)).to.equal(nil)
        end)
    end)
end
