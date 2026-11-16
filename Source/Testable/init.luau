--[[

Testable

A Luau testing framework with TestEZ-style API. Provides describe/it blocks, expectation
matchers, lifecycle hooks, and parallel test execution support.

--]]

const Config = require("@self/Config")
const Coverage = require("@self/Coverage")
const CoverageReporter = require("@self/Reporters/CoverageReporter")
const Expectation = require("@self/Expectation")
const JUnitReporter = require("@self/Reporters/JUnitReporter")
const JsonReporter = require("@self/Reporters/JsonReporter")
const LcovReporter = require("@self/Reporters/LcovReporter")
const ReporterSelection = require("@self/Reporters/ReporterSelection")
const SpecApi = require("@self/SpecApi")
const StandardOutputGuard = require("@self/Reporters/StandardOutputGuard")
const TestBootstrap = require("@self/TestBootstrap")
const TestEnum = require("@self/TestEnum")
const TestPlan = require("@self/TestPlan")
const TestPlanner = require("@self/TestPlanner")
const TestResults = require("@self/TestResults")
const TestRunner = require("@self/TestRunner")
const TestSession = require("@self/TestSession")
const TextReporter = require("@self/Reporters/TextReporter")

export type Expect<Custom = {}> = SpecApi.Expect<Custom>
export type Expectation<Custom = {}> = SpecApi.Expectation<Custom>
export type Matcher = SpecApi.Matcher
export type MatcherResult = SpecApi.MatcherResult

--[[
    Executes tests from the specified test roots, generates a test plan, runs the tests,
    reports the results with the configured reporters, and returns the results and a
    boolean indicating whether all tests passed. If coverage is enabled, collects and
    reports coverage data after tests complete.

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

    -- The reporter settings are resolved up front for the same reason, and so that a bad
    -- combination fails before any test runs.
    const selection = ReporterSelection.resolve(Config.Reporters, Config.ReporterOutputs)
    const slowestTests = Config.SlowestTests
    if selection.NeedsCoverage and not (coverageEnabled and coverageRoots ~= nil) then
        error('The "Lcov" reporter needs Coverage enabled and CoverageRoots set.')
    end

    -- A machine-readable report on standard output has to be the only thing there, so
    -- whatever is printed while tests are planned and run goes to standard error.
    const results = StandardOutputGuard.run(selection.StandardOutput ~= nil, function()
        const modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
        const plan = TestPlanner.createPlan(modules)
        return TestRunner.runPlan(plan)
    end)

    if selection.Text then
        TextReporter.report(results, slowestTests)
    end

    local passed = results.failureCount == 0
    local coverageReport = nil

    if coverageEnabled and coverageRoots ~= nil then
        coverageReport = Coverage.collect(coverageRoots)

        if coverageReport ~= nil then
            if selection.Text then
                CoverageReporter.report(coverageReport, coverageThreshold, coverageLayout)
            end

            if coverageReport.TotalPercentage < coverageThreshold then
                passed = false
            end
        end
    end

    ReporterSelection.emit(selection, results, coverageReport)

    return results, passed
end

const modules = {
    configure = Config.set,
    resetConfig = Config.reset,
    run = run,

    Config = Config,
    Coverage = Coverage,
    Expectation = Expectation,
    Reporters = {
        CoverageReporter = CoverageReporter,
        JUnitReporter = JUnitReporter,
        JsonReporter = JsonReporter,
        LcovReporter = LcovReporter,
        TextReporter = TextReporter,
    },
    TestBootstrap = TestBootstrap,
    TestEnum = TestEnum,
    TestPlan = TestPlan,
    TestPlanner = TestPlanner,
    TestResults = TestResults,
    TestRunner = TestRunner,
    TestSession = TestSession,
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
