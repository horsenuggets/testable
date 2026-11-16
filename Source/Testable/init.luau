--[[

Testable

A Luau testing framework with TestEZ-style API. Provides describe/it blocks, expectation
matchers, lifecycle hooks, and parallel test execution support.

--]]

const Config = require("@self/Config")
const Coverage = require("@self/Coverage")
const CoverageReporter = require("@self/Reporters/CoverageReporter")
const Expectation = require("@self/Expectation")
const TestBootstrap = require("@self/TestBootstrap")
const TestEnum = require("@self/TestEnum")
const TestFilter = require("@self/TestFilter")
const TestPlan = require("@self/TestPlan")
const TestPlanner = require("@self/TestPlanner")
const TestResults = require("@self/TestResults")
const TestRunner = require("@self/TestRunner")
const TestSession = require("@self/TestSession")
const TextReporter = require("@self/Reporters/TextReporter")
const ToolError = require("@self/ToolError")
const EXIT_CODES = {
    Failed = 1,
    Passed = 0,
    ToolError = 2,
}

--[[
    Executes tests from the specified test roots, generates a test plan, runs the tests,
    reports the results using the TextReporter, and returns the results and a boolean
    indicating whether all tests passed. If coverage is enabled, collects and reports
    coverage data after tests complete.

    Test failures are reported through the "passed" return value. Tool errors, where the
    run can't give a meaningful verdict, are thrown as ToolError objects instead. That
    covers a Config.Filter that selects no tests and a coverage threshold with nothing
    measured. Catch them with pcall and ToolError.is, or use runToExitCode.

    @param testRoots - Array of test module roots to execute
    @return results - The test results object
    @return passed - Boolean indicating if all tests passed
]]
const function run(testRoots: any): (any, boolean)
    if not testRoots then
        error("testRoots must be provided")
    end
    if type(testRoots) == "table" and #testRoots == 0 and next(testRoots) == nil then
        error("testRoots must be a non-empty table")
    end

    -- Snapshot coverage config before tests run, since tests may call
    -- Config.reset() which would wipe the coverage settings
    const coverageEnabled = Config.Coverage
    const coverageLayout = { Rows = Config.CoverageRows, Sort = Config.CoverageSort }
    const coverageRoots = Config.CoverageRoots
    const coverageThreshold = Config.CoverageThreshold

    const modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
    const plan = TestPlanner.createPlan(modules, Config.Filter)
    const results = TestRunner.runPlan(plan)

    TextReporter.report(results)

    local passed = results.failureCount == 0

    if coverageEnabled then
        const coverageReport = if coverageRoots ~= nil then Coverage.collect(coverageRoots) else nil

        if coverageReport ~= nil then
            CoverageReporter.report(coverageReport, coverageThreshold, coverageLayout)
        end

        const gate = Coverage.checkGate(coverageReport, coverageThreshold)
        if gate == "Unmeasured" then
            error(
                ToolError.new(
                    ToolError.Kind.EmptyCoverage,
                    `The coverage threshold of {coverageThreshold}% has nothing to measure. `
                        .. "Set CoverageRoots to modules that contain executable lines."
                ),
                0
            )
        elseif gate == "Failed" then
            passed = false
        end
    end

    return results, passed
end

--[[
    Runs tests like run() and turns the outcome into a process exit code, so scripts can
    tell test failures apart from tool errors. A caught tool error is printed. Any other
    error is rethrown with its traceback.

    @param testRoots - Array of test module roots to execute
    @return exitCode - One of ExitCode, 0 for a passing run, 1 for test failures (or
        coverage below its threshold), and 2 for a tool error
    @return results - The test results object, or nil after a tool error
]]
const function runToExitCode(testRoots: any): (number, any?)
    const ok, results, passed = xpcall(run, function(problem)
        return if ToolError.is(problem) then problem else debug.traceback(tostring(problem), 2)
    end, testRoots)

    if not ok then
        if not ToolError.is(results) then
            error(results, 0)
        end
        print("")
        print(`Testable could not complete the run. {results.Message}`)
        return EXIT_CODES.ToolError, nil
    end

    return if passed then EXIT_CODES.Passed else EXIT_CODES.Failed, results
end

const Testable = {
    configure = Config.set,
    resetConfig = Config.reset,
    run = run,
    runToExitCode = runToExitCode,

    Config = Config,
    Coverage = Coverage,
    ExitCode = EXIT_CODES,
    Expectation = Expectation,
    Reporters = {
        CoverageReporter = CoverageReporter,
        TextReporter = TextReporter,
    },
    TestBootstrap = TestBootstrap,
    TestEnum = TestEnum,
    TestFilter = TestFilter,
    TestPlan = TestPlan,
    TestPlanner = TestPlanner,
    TestResults = TestResults,
    TestRunner = TestRunner,
    TestSession = TestSession,
    ToolError = ToolError,
}

return Testable
