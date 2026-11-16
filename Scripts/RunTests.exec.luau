#!/usr/bin/env -S lune run

--[[

RunTests.exec

Executes all test suites and exits with appropriate status code.

[Usage] ./Scripts/RunTests.exec.luau [--update-snapshots]

Pass "--update-snapshots" (or "-u") to accept changed snapshots and remove obsolete ones.

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
    { Name = "ParallelHooksTest", Func = require("../Tests/ParallelHooksTest.spec") },
    { Name = "PlanningErrorTest", Func = require("../Tests/PlanningErrorTest.spec") },
    { Name = "ReporterTest", Func = require("../Tests/ReporterTest.spec") },
    { Name = "RobloxCloudTest", Func = require("../Tests/RobloxCloudTest.spec") },
    { Name = "SnapshotTest", Func = require("../Tests/SnapshotTest.spec") },
    { Name = "VersionUpdateTest", Func = require("../Tests/VersionUpdateTest.spec") },
}

const RunTests = {}

function RunTests.exec()
    for _, argument in process.args do
        if argument == "--update-snapshots" or argument == "-u" then
            Testable.configure({ UpdateSnapshots = true })
        end
    end

    const _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

RunTests.exec()
