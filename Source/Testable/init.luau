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
    indicating whether all tests passed.

    @param testRoots - Array of test module roots to execute
    @return results - The test results object
    @return passed - Boolean indicating if all tests passed
]]
local function run(testRoots: { any }): (any, boolean)
    if not testRoots or #testRoots == 0 then
        error("testRoots must be a non-empty array")
    end

    local modules = TestBootstrap:getModulesFromMultipleRoots(testRoots)
    local plan = TestPlanner.createPlan(modules)
    local results = TestRunner.runPlan(plan)

    TextReporter.report(results)

    return results, results.failureCount == 0
end

local Testable = {
    run = run,

    Expectation = Expectation,
    TestBootstrap = TestBootstrap,
    TestEnum = TestEnum,
    TestPlan = TestPlan,
    TestPlanner = TestPlanner,
    TestResults = TestResults,
    TestRunner = TestRunner,
    TestSession = TestSession,

    Reporters = {
        TextReporter = TextReporter,
    },
}

return Testable
