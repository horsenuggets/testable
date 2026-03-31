#!/usr/bin/env -S lune run

--[[

RunTests

Executes all test suites and exits with appropriate status code.

--]]

local Testable = require("../Source/Testable")
local process = require("@lune/process")

local TESTS = {
    { Name = "ConfigTest", Func = require("../Tests/ConfigTest.spec") },
    { Name = "DictSyntaxTest", Func = require("../Tests/DictSyntaxTest.spec") },
    { Name = "ExampleTest", Func = require("../Tests/ExampleTest.spec") },
    { Name = "ExpectationTest", Func = require("../Tests/ExpectationTest.spec") },
    { Name = "FailTest", Func = require("../Tests/FailTest.spec") },
    { Name = "LifecycleTest", Func = require("../Tests/LifecycleTest.spec") },
    { Name = "RobloxCloudTest", Func = require("../Tests/RobloxCloudTest.spec") },
    { Name = "VersionUpdateTest", Func = require("../Tests/VersionUpdateTest.spec") },
}

local function runTests()
    local _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

runTests()
