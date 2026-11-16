--[[

Testable

A Luau testing framework with TestEZ-style API. Provides describe/it blocks, expectation
matchers, lifecycle hooks, and parallel test execution support.

--]]

const IS_LUNE = pcall(function()
    require("@lune/fs")
end)

const Config = require("@self/Config")
const Coverage = require("@self/Coverage")
const CoverageReporter = require("@self/Reporters/CoverageReporter")
const Expectation = require("@self/Expectation")
const JUnitReporter = require("@self/Reporters/JUnitReporter")
const JsonReporter = require("@self/Reporters/JsonReporter")
const LcovReporter = require("@self/Reporters/LcovReporter")
const MemorySnapshotStore = require("@self/Snapshots/MemorySnapshotStore")
const ReporterSelection = require("@self/Reporters/ReporterSelection")
const SnapshotDiff = require("@self/Snapshots/SnapshotDiff")
const SnapshotFormat = require("@self/Snapshots/SnapshotFormat")
const SnapshotLogic = require("@self/Snapshots/SnapshotLogic")
const SnapshotManager = require("@self/Snapshots/SnapshotManager")
const SnapshotSerializer = require("@self/Snapshots/SnapshotSerializer")
const SnapshotSummary = require("@self/Snapshots/SnapshotSummary")
const SpecApi = require("@self/SpecApi")
const StandardOutputGuard = require("@self/Reporters/StandardOutputGuard")
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

export type Expect<Custom = {}> = SpecApi.Expect<Custom>
export type Expectation<Custom = {}> = SpecApi.Expectation<Custom>
export type Matcher = SpecApi.Matcher
export type MatcherResult = SpecApi.MatcherResult

--[[
    Executes tests from the specified test roots, generates a test plan, runs the tests,
    reports the results with the configured reporters, and returns the results and a
    boolean indicating whether all tests passed. If coverage is enabled, collects and
    reports coverage data after tests complete.

    Test failures are reported through the "passed" return value. Tool errors, where the
    run can't give a meaningful verdict, are thrown as ToolError objects instead. That
    covers a Config.Filter that selects no tests, a coverage threshold with nothing
    measured, and reporter settings that can't work together. Catch them with pcall and ToolError.is, or use runToExitCode.

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

    -- The filter is snapshotted for the same reason
    const filter = Config.Filter

    -- The reporter settings are resolved up front for the same reason, and so that a bad
    -- combination fails before any test runs.
    -- A combination that can't work is a tool error, since no test has anything to do
    -- with it.
    const resolved, selection = pcall(ReporterSelection.resolve, Config.Reporters, Config.ReporterOutputs)
    if not resolved then
        -- The source position in front of the message means nothing to the caller
        const message = tostring(selection):gsub("^[^\n]-:%d+: ", "")
        error(ToolError.new(ToolError.Kind.InvalidReporters, message), 0)
    end
    const slowestTests = Config.SlowestTests
    if selection.NeedsCoverage and not (coverageEnabled and coverageRoots ~= nil) then
        error(
            ToolError.new(
                ToolError.Kind.InvalidReporters,
                'The "Lcov" reporter needs Coverage enabled and CoverageRoots set.'
            ),
            0
        )
    end

    -- A machine-readable report on standard output has to be the only thing there, so
    -- whatever is printed while tests are planned and run goes to standard error.
    const results = StandardOutputGuard.run(selection.StandardOutput ~= nil, function()
        const modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
        const plan = TestPlanner.createPlan(modules, filter)
        return TestRunner.runPlan(plan)
    end)

    if selection.Text then
        TextReporter.report(results, slowestTests)
    end

    local passed = results.failureCount == 0
    local coverageReport = nil

    if coverageEnabled then
        if coverageRoots ~= nil then
            coverageReport = Coverage.collect(coverageRoots)
        end

        if coverageReport ~= nil and selection.Text then
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

    ReporterSelection.emit(selection, results, coverageReport)

    return results, passed
end

-- Discovery needs Lune's filesystem and process libraries, so it is only required on Lune
-- and is nil everywhere else. Requiring it unconditionally would stop this package from
-- loading on Roblox.
const Discovery = if IS_LUNE then require("@self/Discovery") else nil

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
        -- In Lune the message goes to standard error, which keeps it out of the way of a
        -- machine-readable report that owns standard output
        StandardOutputGuard.run(true, function()
            print("")
            print(`Testable could not complete the run. {results.Message}`)
        end)
        return EXIT_CODES.ToolError, nil
    end

    return if passed then EXIT_CODES.Passed else EXIT_CODES.Failed, results
end

const modules = {
    configure = Config.set,
    resetConfig = Config.reset,
    run = run,
    runToExitCode = runToExitCode,

    Config = Config,
    Coverage = Coverage,
    Discovery = Discovery :: typeof(require("@self/Discovery")),
    ExitCode = EXIT_CODES,
    Expectation = Expectation,
    Reporters = {
        CoverageReporter = CoverageReporter,
        JUnitReporter = JUnitReporter,
        JsonReporter = JsonReporter,
        LcovReporter = LcovReporter,
        TextReporter = TextReporter,
    },
    Snapshots = {
        MemorySnapshotStore = MemorySnapshotStore,
        SnapshotDiff = SnapshotDiff,
        SnapshotFormat = SnapshotFormat,
        SnapshotLogic = SnapshotLogic,
        SnapshotManager = SnapshotManager,
        SnapshotSerializer = SnapshotSerializer,
        SnapshotSummary = SnapshotSummary,
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

-- The spec API (describe, it, expect, and so on) is exported alongside the modules above
-- so that specs can require it instead of relying on injected globals. SpecApi generates
-- it from the spec environment, so it is merged in rather than listed here.
const Testable = table.clone(modules) :: { [string]: any }

for key, value in SpecApi.create() :: { [string]: any } do
    assert(Testable[key] == nil, `The spec API entry "{key}" collides with a Testable export`)
    Testable[key] = value
end

return (Testable :: any) :: typeof(modules) & SpecApi.Api
