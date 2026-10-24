#!/usr/bin/env -S lune run

--[[

RunTests.exec

Executes all test suites and exits with appropriate status code.

[Usage] ./Scripts/RunTests.exec.luau

--]]

const Testable = require("../Source/Testable")
const process = require("@lune/process")

const TESTS = {
    { Name = "ConfigTest", Func = require("../Tests/ConfigTest.spec") },
    { Name = "CoverageTest", Func = require("../Tests/CoverageTest.spec") },
    { Name = "DictSyntaxTest", Func = require("../Tests/DictSyntaxTest.spec") },
    { Name = "ExampleTest", Func = require("../Tests/ExampleTest.spec") },
    { Name = "ExpectationTest", Func = require("../Tests/ExpectationTest.spec") },
    { Name = "FailTest", Func = require("../Tests/FailTest.spec") },
    { Name = "LifecycleTest", Func = require("../Tests/LifecycleTest.spec") },
    { Name = "PlanningErrorTest", Func = require("../Tests/PlanningErrorTest.spec") },
    { Name = "RobloxCloudTest", Func = require("../Tests/RobloxCloudTest.spec") },
    { Name = "VersionUpdateTest", Func = require("../Tests/VersionUpdateTest.spec") },
}

const RunTests = {}

function RunTests.exec()
    const _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

RunTests.exec()
