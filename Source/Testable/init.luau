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
const TableRenderer = require("@self/TableRenderer")
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
const Discovery = if IS_LUNE then require("@self/Discovery") else nil
local Testable: any

export type Alignment = TableRenderer.Alignment
export type Expect<Custom = {}> = SpecApi.Expect<Custom>
export type Expectation<Custom = {}> = SpecApi.Expectation<Custom>
export type Matcher = SpecApi.Matcher
export type MatcherResult = SpecApi.MatcherResult
export type TableRow = TableRenderer.TableRow

const function captureFileConfiguration(): any
    const function copy(value: any): any
        if type(value) ~= "table" then
            return value
        end
        const owned = {}
        for key, item in pairs(value) do
            owned[key] = copy(item)
        end
        return owned
    end
    const options = {}
    for key, value in pairs(Config) do
        if key == "Log" or type(value) ~= "function" then
            options[key] = if key == "SnapshotStore" or key == "CoverageRoots" then value else copy(value)
        end
    end
    return options
end

--[[
    Executes tests from the specified test roots, generates a test plan, runs the tests,
    reports the results with the configured reporters, and returns the results and a
    boolean indicating whether all tests passed. If coverage is enabled, collects and
    reports coverage data after tests complete.

    Test failures are reported through the "passed" return value. Tool errors, where the
    run can't give a meaningful verdict, are thrown as ToolError objects instead. That
    covers a Config.Filter that selects no tests, a coverage threshold with nothing
    measured, and reporter settings that can't work together. Testable.configure throws
    one as well when an option is not valid. Catch them with pcall and ToolError.is, or
    use runToExitCode.

    @param testRoots - Array of test module roots to execute
    @return results - The test results object
    @return passed - Boolean indicating if all tests passed
]]
const function runConfigured(testRoots: any, fileRoot: string?, fileMode: boolean): (any, boolean)
    if not testRoots then
        error("testRoots must be provided")
    end
    if type(testRoots) == "table" and #testRoots == 0 and next(testRoots) == nil then
        error("testRoots must be a non-empty table")
    end

    if fileMode and not IS_LUNE then
        error(ToolError.new(ToolError.Kind.InvalidConfiguration, "File-oriented test execution requires Lune."), 0)
    end
    const logging = { Log = Config.Log, Verbose = Config.Verbose }
    const fileConfiguration = if fileMode then captureFileConfiguration() else nil
    if fileConfiguration ~= nil and fileConfiguration.Workers > 1 and logging.Log ~= nil then
        error(
            ToolError.new(
                ToolError.Kind.InvalidConfiguration,
                "Log callbacks cannot cross worker VMs. Use Workers = 1 for a parent-owned callback."
            ),
            0
        )
    end

    -- Snapshot coverage config before tests run, since tests may call
    -- Config.reset() which would wipe the coverage settings
    const coverageEnabled = Config.Coverage
    const coverageLayout = { Rows = Config.CoverageRows, Sort = Config.CoverageSort }
    const coverageRoots = Config.CoverageRoots
    const coverageThreshold = Config.CoverageThreshold

    -- Discovery and spec registration can change config, so both inputs are snapshotted.
    const filter = Config.Filter
    const suiteOrder = table.clone(Config.SuiteOrder)

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
    const workerSetup = Config.WorkerSetup
    if
        selection.NeedsCoverage
        and not (coverageEnabled and (coverageRoots ~= nil or (fileMode and workerSetup ~= nil)))
    then
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
    const outcome = StandardOutputGuard.run(selection.StandardOutput ~= nil, function()
        if fileConfiguration ~= nil then
            const Coordinator = require("@self/Workers/Coordinator")
            const options = {
                Config = fileConfiguration,
                Groups = fileConfiguration.WorkerGroups,
                Setup = fileConfiguration.WorkerSetup,
                Workers = fileConfiguration.Workers,
            }
            if options.Workers > 1 then
                if fileConfiguration.SnapshotStore ~= nil then
                    error(
                        ToolError.new(
                            ToolError.Kind.InvalidConfiguration,
                            "SnapshotStore functions cannot cross worker VMs. Use Workers = 1 to retain a parent-owned store, "
                                .. "or construct an independent worker-local store in WorkerSetup."
                        ),
                        0
                    )
                end
                const roots = fileConfiguration.CoverageRoots
                local transferableRoots = roots == nil or type(roots) == "string"
                if type(roots) == "table" and getmetatable(roots) == nil then
                    transferableRoots = true
                    const ownedRoots = {}
                    for name, value in pairs(roots) do
                        if type(name) ~= "string" or type(value) ~= "string" then
                            transferableRoots = false
                            break
                        end
                        ownedRoots[name] = value
                    end
                    if transferableRoots then
                        fileConfiguration.CoverageRoots = ownedRoots
                    end
                end
                if not transferableRoots then
                    error(
                        ToolError.new(
                            ToolError.Kind.InvalidConfiguration,
                            "CoverageRoots userdata cannot cross worker VMs. Pass filesystem paths, "
                                .. "or construct the roots inside WorkerSetup."
                        ),
                        0
                    )
                end
                if next(TestRunner.environment) ~= nil and workerSetup == nil then
                    error(
                        ToolError.new(
                            ToolError.Kind.InvalidConfiguration,
                            "TestRunner.environment is VM-local. Recreate its bindings in WorkerSetup before running actors."
                        ),
                        0
                    )
                end
                -- Coordinator-only settings do not recursively fan out nested file runs.
                fileConfiguration.Workers = 1
                fileConfiguration.WorkerGroups = {}
                fileConfiguration.WorkerSetup = nil
                const result = Coordinator.run(testRoots, fileRoot, options, selection.StandardOutput ~= nil)
                result.CoverageFromWorkers = true
                return result
            end
            const prepared = Coordinator.prepare(testRoots, fileRoot, options)
            if prepared.Setup ~= nil then
                const setup = Discovery.Loader.load(prepared.Setup)
                assert(type(setup) == "function", "WorkerSetup must return a function.")
                setup(Testable, { Files = table.clone(prepared.Files), JobId = 1, Root = prepared.Root })
            end
            const localCoverageRoots = Config.CoverageRoots
            const roots = Discovery.load(prepared.Files, prepared.Root)
            const modules = TestBootstrap:getModulesFromMultipleRoots(roots)
            const plan = TestPlanner.createPlan(modules, filter, nil, suiteOrder)
            plan.forbidFocus = fileConfiguration.ForbidFocus
            return {
                CoverageRoots = localCoverageRoots,
                LocalFiles = true,
                Results = TestRunner.runPlan(plan, { Logging = logging }),
            }
        end
        const modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
        const plan = TestPlanner.createPlan(modules, filter, nil, suiteOrder)
        return { Results = TestRunner.runPlan(plan, { Logging = logging }) }
    end)
    const results = outcome.Results

    if selection.Text then
        TextReporter.report(results, slowestTests)
    end

    local passed = results.failureCount == 0
    local coverageReport = nil

    if coverageEnabled then
        if outcome.CoverageFromWorkers then
            if outcome.RawCoverage ~= nil then
                coverageReport = Coverage.collectRaw(outcome.RawCoverage)
            end
        else
            const roots = if outcome.LocalFiles then outcome.CoverageRoots else coverageRoots
            if roots ~= nil then
                coverageReport = Coverage.collect(roots)
            end
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

    if selection.NeedsCoverage and coverageReport == nil then
        error(
            ToolError.new(
                ToolError.Kind.InvalidReporters,
                'The "Lcov" reporter needs coverage roots in every execution VM. Configure them before loading specs.'
            ),
            0
        )
    end
    ReporterSelection.emit(selection, results, coverageReport)

    return results, passed
end

const function run(testRoots: any): (any, boolean)
    return runConfigured(testRoots, nil, false)
end

-- Paths remain unloaded until the run has captured its configuration and reporters.
const function runFiles(files: { string }, root: string?): (any, boolean)
    return runConfigured(files, root, true)
end

--[[
    Runs tests like run() and turns the outcome into a process exit code, so scripts can
    tell test failures apart from tool errors. A caught tool error is printed. Any other
    error is rethrown with its traceback.

    Options passed here are applied with Testable.configure before the run, inside the
    same protection, so options that are not valid also end in the tool error exit code
    instead of an uncaught error.

    @param testRoots - Array of test module roots to execute
    @param options - Configuration options to set before the run, if any
    @return exitCode - One of ExitCode, 0 for a passing run, 1 for test failures (or
        coverage below its threshold), and 2 for a tool error
    @return results - The test results object, or nil after a tool error
]]
const function runWithExitCode(
    runner: (any, string?) -> (any, boolean),
    testRoots: any,
    options: Config.ConfigOptions?,
    root: string?
): (number, any?)
    const ok, results, passed = xpcall(function()
        if options ~= nil then
            Config.set(options)
        end
        return runner(testRoots, root)
    end, function(problem)
        return if ToolError.is(problem) then problem else debug.traceback(tostring(problem), 2)
    end)

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

const function runToExitCode(testRoots: any, options: Config.ConfigOptions?): (number, any?)
    return runWithExitCode(run, testRoots, options, nil)
end

const function runFilesToExitCode(files: { string }, options: Config.ConfigOptions?, root: string?): (number, any?)
    return runWithExitCode(runFiles, files, options, root)
end

const modules = {
    configure = Config.set,
    resetConfig = Config.reset,
    run = run,
    runFiles = runFiles,
    runFilesToExitCode = runFilesToExitCode,
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
    TableRenderer = TableRenderer,
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
Testable = table.clone(modules) :: { [string]: any }

for key, value in SpecApi.create() :: { [string]: any } do
    assert(Testable[key] == nil, `The spec API entry "{key}" collides with a Testable export`)
    Testable[key] = value
end

return (Testable :: any) :: typeof(modules) & SpecApi.Api
