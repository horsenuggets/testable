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
const TestPlan = require("@self/TestPlan")
const TestPlanner = require("@self/TestPlanner")
const TestResults = require("@self/TestResults")
const TestRunner = require("@self/TestRunner")
const TestSession = require("@self/TestSession")
const TextReporter = require("@self/Reporters/TextReporter")

--[[
    Executes tests from the specified test roots, generates a test plan, runs the tests,
    reports the results using the TextReporter, and returns the results and a boolean
    indicating whether all tests passed. If coverage is enabled, collects and reports
    coverage data after tests complete.

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
    const coverageRoots = Config.CoverageRoots
    const coverageThreshold = Config.CoverageThreshold

    const modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
    const plan = TestPlanner.createPlan(modules)
    const results = TestRunner.runPlan(plan)

    TextReporter.report(results)

    local passed = results.failureCount == 0

    if coverageEnabled and coverageRoots ~= nil then
        const coverageReport = Coverage.collect(coverageRoots)

        if coverageReport ~= nil then
            CoverageReporter.report(coverageReport, coverageThreshold)

            if coverageReport.TotalPercentage < coverageThreshold then
                passed = false
            end
        end
    end

    return results, passed
end

const Testable = {
    configure = Config.set,
    resetConfig = Config.reset,
    run = run,

    Config = Config,
    Coverage = Coverage,
    Expectation = Expectation,
    Reporters = {
        CoverageReporter = CoverageReporter,
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

return Testable
