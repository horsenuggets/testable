--[[

InvalidConfigurationTest.spec

Tests that configuration options that are not valid end in the tool error exit code. Each
case runs in a subprocess, so it gets its own Testable instance and can exit with any
code without affecting this run. Covers Testable.runToExitCode with options, and the
RunTests script when the options it builds from its flags are rejected.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const process = require("@lune/process")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const Testable = require("./Source/Testable")

    Testable.configure({ InjectGlobals = false, Parallel = %s })

    local ran = false
    const tests = {
        {
            Name = "Suite",
            Func = function()
                Testable.it("passes", function()
                    ran = true
                end)
            end,
        },
    }

    const exitCode, results = Testable.runToExitCode(tests, %s)
    print("EXIT_CODE:" .. exitCode)
    print("HAS_RESULTS:" .. tostring(results ~= nil))
    print("RAN:" .. tostring(ran))
    print("INDENT:" .. Testable.Config.Indent .. "|")
    process.exit(exitCode)
]]
const THROWING_SCRIPT = [[
    const Testable = require("./Source/Testable")

    const ok, problem = pcall(Testable.runToExitCode, {
        Suite = function()
            Testable.it("passes", function() end)
        end,
    }, { Indent = ">" })
    print("FIRST_OK:" .. tostring(ok))

    const rethrown, message = pcall(Testable.runToExitCode, {})
    print("SECOND_OK:" .. tostring(rethrown))
    print("IS_TOOL_ERROR:" .. tostring(Testable.ToolError.is(message)))
    print("MESSAGE:" .. tostring(message))
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

--[[
    Runs the RunTests script with coverage turned off in its environment and returns its
    exit code and combined output. The API key is blanked so the nested script never
    plans the Roblox cloud tests.
]]
const function runTestsScriptWithoutCoverage(arguments: { string }): (number, string)
    const result = process.exec("lune", { "run", "Scripts/RunTests.exec.luau", table.unpack(arguments) }, {
        cwd = process.cwd,
        env = { LUNE_COVERAGE = "0", TESTABLE_CICD_ROBLOX_API_KEY = "" },
    })
    return result.code, `{result.stdout or ""}{result.stderr or ""}`
end

return function()
    for _, mode in EXECUTION_MODES do
        describe(`runToExitCode with {mode.Name} execution`, function()
            const function runScript(options: string): (boolean, string)
                return Subprocess.runScript(string.format(SCRIPT_TEMPLATE, tostring(mode.Parallel), options))
            end

            it("should exit with 2 and run nothing when an option is not valid", function()
                const ok, output = runScript('{ Indent = ">", MaxConcurrency = 0 }')

                expect(ok).to.equal(false)
                expect(contains(output, "EXIT_CODE:2")).to.equal(true)
                expect(contains(output, "HAS_RESULTS:false")).to.equal(true)
                expect(contains(output, "RAN:false")).to.equal(true)
                expect(
                    contains(
                        output,
                        "Testable could not complete the run. The configuration is not valid. "
                            .. "MaxConcurrency must be at least 1."
                    )
                ).to.equal(true)
                expect(contains(output, "passed")).to.equal(false)
                expect(contains(output, "stack traceback")).to.equal(false)

                -- The valid option given next to the invalid one is not applied either.
                expect(contains(output, "INDENT:   |")).to.equal(true)
            end)

            it("should exit with 2 when the options are not a table", function()
                const ok, output = runScript("5")

                expect(ok).to.equal(false)
                expect(contains(output, "EXIT_CODE:2")).to.equal(true)
                expect(contains(output, "The configuration is not valid. options must be a table.")).to.equal(true)
            end)

            it("should reject malformed suite ordering before executing tests", function()
                const ok, output = runScript('{ SuiteOrder = { "Suite", "Suite" } }')
                expect(ok).to.equal(false)
                expect(contains(output, "EXIT_CODE:2")).to.equal(true)
                expect(contains(output, "HAS_RESULTS:false")).to.equal(true)
                expect(contains(output, "RAN:false")).to.equal(true)
                expect(contains(output, "SuiteOrder entries must be unique")).to.equal(true)
            end)

            it("should apply valid options and exit with 0 when the tests pass", function()
                const ok, output = runScript('{ Indent = ">" }')

                expect(ok).to.equal(true)
                expect(contains(output, "EXIT_CODE:0")).to.equal(true)
                expect(contains(output, "HAS_RESULTS:true")).to.equal(true)
                expect(contains(output, "RAN:true")).to.equal(true)
                expect(contains(output, "INDENT:>|")).to.equal(true)
                expect(contains(output, "could not complete the run")).to.equal(false)
            end)

            it("should leave the configuration alone when no options are given", function()
                const ok, output = runScript("nil")

                expect(ok).to.equal(true)
                expect(contains(output, "EXIT_CODE:0")).to.equal(true)
                expect(contains(output, "INDENT:   |")).to.equal(true)
            end)
        end)
    end

    describe("runToExitCode", function()
        it("should still rethrow errors that are not tool errors", function()
            const _, output = Subprocess.runScript(THROWING_SCRIPT)

            expect(contains(output, "FIRST_OK:true")).to.equal(true)
            expect(contains(output, "SECOND_OK:false")).to.equal(true)
            expect(contains(output, "IS_TOOL_ERROR:false")).to.equal(true)
            expect(contains(output, "testRoots must be a non-empty table")).to.equal(true)
        end)
    end)

    describe("RunTests script", function()
        it("should exit with 2 when coverage for the lcov reporter is not available", function()
            -- The script only reaches the tests when coverage is available after all, and
            -- the spec file keeps that run small.
            const code, output = runTestsScriptWithoutCoverage({ "--reporter", "lcov", "Tests/ExampleTest.spec.luau" })

            expect(code).to.equal(2)
            expect(contains(output, "The configuration is not valid. Cannot enable coverage because")).to.equal(true)
            expect(contains(output, "stack traceback")).to.equal(false)
            expect(contains(output, "passed")).to.equal(false)
        end)

        it("should still run the tests when the options are valid", function()
            const code, output = runTestsScriptWithoutCoverage({ "Tests/ExampleTest.spec.luau" })

            expect(code).to.equal(0)
            expect(contains(output, "The configuration is not valid")).to.equal(false)
            expect(contains(output, "passed")).to.equal(true)
        end)
    end)
end
