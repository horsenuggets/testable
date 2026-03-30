--[[

Testable

A Luau testing framework with TestEZ-style API. Provides describe/it blocks, expectation
matchers, lifecycle hooks, and parallel test execution support.

--]]

local Config = require("@self/Config")
local Coverage = require("@self/Coverage")
local CoverageReporter = require("@self/Reporters/CoverageReporter")
local Expectation = require("@self/Expectation")
local TestBootstrap = require("@self/TestBootstrap")
local TestEnum = require("@self/TestEnum")
local TestPlan = require("@self/TestPlan")
local TestPlanner = require("@self/TestPlanner")
local TestResults = require("@self/TestResults")
local TestRunner = require("@self/TestRunner")
local TestSession = require("@self/TestSession")
local TextReporter = require("@self/Reporters/TextReporter")

--[[
    Executes tests from the specified test roots, generates a test plan, runs the tests,
    reports the results using the TextReporter, and returns the results and a boolean
    indicating whether all tests passed. If coverage is enabled, collects and reports
    coverage data after tests complete.

    @param testRoots - Array of test module roots to execute
    @return results - The test results object
    @return passed - Boolean indicating if all tests passed
]]
local function run(testRoots: { any }): (any, boolean)
    if not testRoots then
        error("testRoots must be a non-empty table")
    end
    if #testRoots == 0 and next(testRoots) == nil then
        error("testRoots must be a non-empty table")
    end

    -- Snapshot coverage config before tests run, since tests may call
    -- Config.reset() which would wipe the coverage settings
    local coverageEnabled = Config.Coverage
    local coverageRoots = Config.CoverageRoots
    local coverageThreshold = Config.CoverageThreshold

    local modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
    local plan = TestPlanner.createPlan(modules)
    local results = TestRunner.runPlan(plan)

    TextReporter.report(results)

    local passed = results.failureCount == 0

    if coverageEnabled and coverageRoots ~= nil then
        local coverageReport = Coverage.collect(coverageRoots)

        if coverageReport ~= nil then
            CoverageReporter.report(coverageReport, coverageThreshold)

            if coverageReport.TotalPercentage < coverageThreshold then
                passed = false
            end
        end
    end

    return results, passed
end

local Testable = {
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
