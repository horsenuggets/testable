--[[

ToolErrorTest.spec

Tests that tool errors are identifiable and kept apart from test failures. Covers the
ToolError object, the coverage gate decision, and (in subprocesses, so each case gets its
own Testable instance) the exit codes of Testable.runToExitCode and the RunTests script.

--]]

const Coverage = require("../Source/Testable/Coverage")
const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const ToolError = require("../Source/Testable/ToolError")
const process = require("@lune/process")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false }
}
const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const Testable = require("./Source/Testable")

    Testable.configure(%s)

    const tests = {
        {
            Name = "Suite",
            Func = function()
                it("passes", function() end)
                it("fails", function()
                    error("test failure")
                end)
            end,
        },
    }

    %s
]]
const EXIT_CODE_SCRIPT = [[
    const exitCode, results = Testable.runToExitCode(tests)
    print("EXIT_CODE:" .. exitCode)
    print("HAS_RESULTS:" .. tostring(results ~= nil))
    process.exit(exitCode)
]]
const THROWING_SCRIPT = [[
    const ok, problem = pcall(Testable.run, tests)
    print("OK:" .. tostring(ok))
    print("IS_TOOL_ERROR:" .. tostring(Testable.ToolError.is(problem)))
    print("KIND:" .. tostring(type(problem) == "table" and problem.Kind))
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

const function report(totalExecutableLines: number, totalPercentage: number): Coverage.CoverageReport
    return {
        Files = {},
        TotalExecutableLines = totalExecutableLines,
        TotalHitLines = 0,
        TotalPercentage = totalPercentage
    }
end

const function coverageAvailable(): boolean
    return type(debug.iscoverageenabled) == "function" and debug.iscoverageenabled()
end

--[[
    Runs the RunTests script with the given arguments and returns its exit code, its
    combined output, and both output streams on their own. The API key is blanked so the
    nested script never plans the Roblox cloud tests, which would start a remote run
    for every case here.
]]
const function runTestsScript(args: { string }): (number, string, string, string)
    const result = process.exec("lune", { "run", "Scripts/RunTests.exec.luau", table.unpack(args) }, {
        cwd = process.cwd,
        env = { TESTABLE_CICD_ROBLOX_API_KEY = "" }
    })
    const standardOutput = result.stdout or ""
    const standardError = result.stderr or ""
    return result.code, standardOutput .. standardError, standardOutput, standardError
end

return function()
    describe("ToolError", function()
        it("should carry its kind and message", function()
            const problem = ToolError.new(ToolError.Kind.EmptyFilter, "Nothing matched.")

            expect(problem.Kind).to.equal("EmptyFilter")
            expect(problem.Message).to.equal("Nothing matched.")
            expect(tostring(problem)).to.equal("Nothing matched.")
        end)

        it("should identify worker infrastructure failures without treating them as test failures", function()
            const problem = ToolError.new(ToolError.Kind.WorkerFailure, "The worker returned no completion manifest.")
            expect(ToolError.is(problem)).to.equal(true)
            expect(problem.Kind).to.equal("WorkerFailure")
            expect(tostring(problem)).to.equal("The worker returned no completion manifest.")
        end)

        it("should recognize tool errors after they are thrown", function()
            const ok, problem = pcall(function()
                error(ToolError.new(ToolError.Kind.EmptyCoverage, "Nothing measured."))
            end)

            expect(ok).to.equal(false)
            expect(ToolError.is(problem)).to.equal(true)
        end)

        it("should not recognize other values as tool errors", function()
            const lookalike = { Kind = "EmptyFilter", Message = "Nothing matched." }

            for _, value in { "Nothing matched.", 2, true, {}, lookalike } :: { any } do
                expect(ToolError.is(value)).to.equal(false)
            end
            expect(ToolError.is(nil)).to.equal(false)
        end)

        it("should reject unknown kinds and missing messages", function()
            expect(function()
                ToolError.new("Unknown" :: any, "Nothing matched.")
            end).to.throw("kind must be one of ToolError.Kind")
            expect(function()
                ToolError.new(ToolError.Kind.EmptyFilter, nil :: any)
            end).to.throw("message must be a string")
        end)
    end)

    describe("Coverage.checkGate", function()
        it("should pass whatever was measured when the threshold is 0", function()
            expect(Coverage.checkGate(nil, 0)).to.equal("Passed")
            expect(Coverage.checkGate(report(0, 0), 0)).to.equal("Passed")
            expect(Coverage.checkGate(report(10, 0), 0)).to.equal("Passed")
        end)

        it("should be unmeasured when a threshold has no report or no executable lines", function()
            expect(Coverage.checkGate(nil, 50)).to.equal("Unmeasured")
            expect(Coverage.checkGate(report(0, 0), 50)).to.equal("Unmeasured")
            expect(Coverage.checkGate(nil, 0.01)).to.equal("Unmeasured")
        end)

        it("should compare measured coverage against the threshold", function()
            expect(Coverage.checkGate(report(10, 49.99), 50)).to.equal("Failed")
            expect(Coverage.checkGate(report(10, 0), 50)).to.equal("Failed")
            expect(Coverage.checkGate(report(10, 50), 50)).to.equal("Passed")
            expect(Coverage.checkGate(report(10, 100), 50)).to.equal("Passed")
        end)
    end)

    for _, mode in EXECUTION_MODES do
        describe(`exit codes with {mode.Name} execution`, function()
            const function runScript(options: string, body: string): (boolean, string)
                const configured = `\{ Parallel = {mode.Parallel}, {options} }`
                return Subprocess.runScript(string.format(SCRIPT_TEMPLATE, configured, body))
            end

            it("should exit with 0 when the selected tests pass", function()
                const ok, output = runScript('Filter = "passes"', EXIT_CODE_SCRIPT)

                expect(ok).to.equal(true)
                expect(contains(output, "EXIT_CODE:0")).to.equal(true)
                expect(contains(output, "HAS_RESULTS:true")).to.equal(true)
                expect(contains(output, "1 passed")).to.equal(true)
                expect(contains(output, "1 skipped (1 filtered out)")).to.equal(true)
            end)

            it("should exit with 1 when a test fails", function()
                const ok, output = runScript("", EXIT_CODE_SCRIPT)

                expect(ok).to.equal(false)
                expect(contains(output, "EXIT_CODE:1")).to.equal(true)
                expect(contains(output, "HAS_RESULTS:true")).to.equal(true)
                expect(contains(output, "filtered out")).to.equal(false)
            end)

            it("should exit with 2 when the filter matches no tests", function()
                const ok, output = runScript('Filter = "missing"', EXIT_CODE_SCRIPT)

                expect(ok).to.equal(false)
                expect(contains(output, "EXIT_CODE:2")).to.equal(true)
                expect(contains(output, "HAS_RESULTS:false")).to.equal(true)
                expect(contains(output, 'The filter "missing" did not match any of the 2 planned tests.')).to.equal(
                    true
                )
                expect(contains(output, "passed")).to.equal(false)
            end)

            it("should throw an identifiable error from run when the filter matches no tests", function()
                const _, output = runScript('Filter = "missing"', THROWING_SCRIPT)

                expect(contains(output, "OK:false")).to.equal(true)
                expect(contains(output, "IS_TOOL_ERROR:true")).to.equal(true)
                expect(contains(output, "KIND:EmptyFilter")).to.equal(true)
            end)

            it("should exit with 2 when a coverage threshold has nothing to measure", function()
                if not coverageAvailable() then
                    return
                end

                const options = 'Filter = "passes", Coverage = true, CoverageThreshold = 50'
                const ok, output = runScript(options, EXIT_CODE_SCRIPT)

                expect(ok).to.equal(false)
                expect(contains(output, "EXIT_CODE:2")).to.equal(true)
                expect(contains(output, "The coverage threshold of 50% has nothing to measure.")).to.equal(true)

                const _, thrown = runScript(options, THROWING_SCRIPT)
                expect(contains(thrown, "IS_TOOL_ERROR:true")).to.equal(true)
                expect(contains(thrown, "KIND:EmptyCoverage")).to.equal(true)
            end)

            it("should not treat coverage without a threshold as a tool error", function()
                if not coverageAvailable() then
                    return
                end

                const ok, output = runScript('Filter = "passes", Coverage = true', EXIT_CODE_SCRIPT)

                expect(ok).to.equal(true)
                expect(contains(output, "EXIT_CODE:0")).to.equal(true)
            end)

            it("should rethrow errors that are not tool errors", function()
                const ok, output = runScript(
                    "",
                    [[
                        const ok, problem = pcall(Testable.runToExitCode, {})
                        print("OK:" .. tostring(ok))
                        print("IS_TOOL_ERROR:" .. tostring(Testable.ToolError.is(problem)))
                        print(problem)
                    ]]
                )

                expect(ok).to.equal(true)
                expect(contains(output, "OK:false")).to.equal(true)
                expect(contains(output, "IS_TOOL_ERROR:false")).to.equal(true)
                expect(contains(output, "testRoots must be a non-empty table")).to.equal(true)
            end)
        end)
    end

    describe("RunTests script", function()
        it("should exit with 2 and print usage for an unrecognized argument", function()
            const code, output = runTestsScript({ "--bogus" })

            expect(code).to.equal(2)
            expect(contains(output, 'The argument "--bogus" is not recognized.')).to.equal(true)
            expect(contains(output, "[Usage] ./Scripts/RunTests.exec.luau")).to.equal(true)
        end)

        it("should exit with 2 when the filter matches no tests", function()
            const code, output = runTestsScript({ "--filter", "no test has this name" })

            expect(code).to.equal(2)
            expect(contains(output, 'The filter "no test has this name" did not match any of the')).to.equal(true)
        end)

        it("should exit with 0 after running only the tests the filter selects", function()
            const code, output = runTestsScript({ "--filter=FilterArgumentsTest should accept" })

            expect(code).to.equal(0)
            expect(contains(output, "2 passed")).to.equal(true)
            expect(contains(output, "filtered out)")).to.equal(true)
        end)

        it("should take the filter alongside reporter flags", function()
            const code, output = runTestsScript({
                "--slowest",
                "1",
                "--filter",
                "FilterArgumentsTest should accept",
                "--reporter",
                "text"
            })

            expect(code).to.equal(0)
            expect(contains(output, "2 passed")).to.equal(true)
            expect(contains(output, "Slowest Tests")).to.equal(true)
        end)

        it("should exit with 2 for a reporter flag mistake", function()
            const code, output = runTestsScript({ "--reporter", "bogus" })

            expect(code).to.equal(2)
            expect(contains(output, 'The "--reporter" flag needs')).to.equal(true)
            expect(contains(output, "[Usage] ./Scripts/RunTests.exec.luau")).to.equal(true)
        end)

        it("should exit with 2 for reporters that can't work together", function()
            const code, output = runTestsScript({ "--reporter", "json", "--reporter", "junit" })

            expect(code).to.equal(2)
            expect(contains(output, "Testable could not complete the run.")).to.equal(true)
            expect(contains(output, "passed")).to.equal(false)
            -- The message is for the person running the script, so it has no source position
            expect(contains(output, "ReporterSelection.luau")).to.equal(false)
        end)

        it("should keep a tool error out of a report on standard output", function()
            const code, _, standardOutput, standardError =
                runTestsScript({ "--reporter", "json", "--filter", "no test has this name" })

            expect(code).to.equal(2)
            expect(standardOutput).to.equal("")
            expect(contains(standardError, 'The filter "no test has this name" did not match any of the')).to.equal(
                true
            )
        end)
    end)
end
