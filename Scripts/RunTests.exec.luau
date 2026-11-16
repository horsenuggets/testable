#!/usr/bin/env -S lune run

--[[

RunTests.exec

Executes all test suites and exits with 0 when they pass, 1 when tests fail, and 2 for a
tool error such as an unrecognized argument or a filter that matches no tests. The
optional filter only runs the tests whose full name contains the given text.

[Usage] ./Scripts/RunTests.exec.luau [--filter "<text>"]

--]]

const RunTestsArguments = require("./Helpers/RunTestsArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")

const TESTS = {
    { Name = "ConfigTest", Func = require("../Tests/ConfigTest.spec") },
    { Name = "CoverageTest", Func = require("../Tests/CoverageTest.spec") },
    { Name = "DescribeModifierTest", Func = require("../Tests/DescribeModifierTest.spec") },
    { Name = "DictSyntaxTest", Func = require("../Tests/DictSyntaxTest.spec") },
    { Name = "ExampleTest", Func = require("../Tests/ExampleTest.spec") },
    { Name = "ExpectationTest", Func = require("../Tests/ExpectationTest.spec") },
    { Name = "FailTest", Func = require("../Tests/FailTest.spec") },
    { Name = "FilterTest", Func = require("../Tests/FilterTest.spec") },
    { Name = "LifecycleTest", Func = require("../Tests/LifecycleTest.spec") },
    { Name = "NestedRunTest", Func = require("../Tests/NestedRunTest.spec") },
    { Name = "ParallelHooksTest", Func = require("../Tests/ParallelHooksTest.spec") },
    { Name = "PlanningErrorTest", Func = require("../Tests/PlanningErrorTest.spec") },
    { Name = "ReporterTest", Func = require("../Tests/ReporterTest.spec") },
    { Name = "RobloxCloudTest", Func = require("../Tests/RobloxCloudTest.spec") },
    { Name = "RunTestsArgumentsTest", Func = require("../Tests/RunTestsArgumentsTest.spec") },
    { Name = "ToolErrorTest", Func = require("../Tests/ToolErrorTest.spec") },
    { Name = "VersionUpdateTest", Func = require("../Tests/VersionUpdateTest.spec") },
}

const RunTests = {}

function RunTests.exec()
    const arguments, problem = RunTestsArguments.parse(process.args)
    if arguments == nil then
        print(problem)
        print(RunTestsArguments.Usage)
        process.exit(Testable.ExitCode.ToolError)
        return
    end

    if arguments.Filter ~= nil then
        Testable.configure({ Filter = arguments.Filter })
    end

    process.exit(Testable.runToExitCode(TESTS))
end

RunTests.exec()
