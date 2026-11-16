#!/usr/bin/env -S lune run

--[[

RunTests.exec

Executes all test suites and exits with appropriate status code. Reporter flags choose
which reports the run produces and where they go...

> --reporter <text|json|junit|lcov> - Adds a reporter. It can be given several times, and
  "lcov" also turns on coverage for the source.
> --output <path> - Writes the reporter named just before it to a file instead of
  standard output.
> --slowest <count> - Lists that many of the slowest tests in the text report.

[Usage] ./Scripts/RunTests.exec.luau [reporter flags]

--]]

const ReporterArguments = require("./Helpers/ReporterArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")

const TESTS = {
    { Name = "ConfigTest", Func = require("../Tests/ConfigTest.spec") },
    { Name = "CoverageTest", Func = require("../Tests/CoverageTest.spec") },
    { Name = "DictSyntaxTest", Func = require("../Tests/DictSyntaxTest.spec") },
    { Name = "ExampleTest", Func = require("../Tests/ExampleTest.spec") },
    { Name = "ExpectationTest", Func = require("../Tests/ExpectationTest.spec") },
    { Name = "FailTest", Func = require("../Tests/FailTest.spec") },
    { Name = "JUnitReporterTest", Func = require("../Tests/JUnitReporterTest.spec") },
    { Name = "JsonReporterTest", Func = require("../Tests/JsonReporterTest.spec") },
    { Name = "LcovReporterTest", Func = require("../Tests/LcovReporterTest.spec") },
    { Name = "LifecycleTest", Func = require("../Tests/LifecycleTest.spec") },
    { Name = "ParallelHooksTest", Func = require("../Tests/ParallelHooksTest.spec") },
    { Name = "PlanningErrorTest", Func = require("../Tests/PlanningErrorTest.spec") },
    { Name = "ReporterArgumentsTest", Func = require("../Tests/ReporterArgumentsTest.spec") },
    { Name = "ReporterSelectionTest", Func = require("../Tests/ReporterSelectionTest.spec") },
    { Name = "ReporterTest", Func = require("../Tests/ReporterTest.spec") },
    { Name = "RobloxCloudTest", Func = require("../Tests/RobloxCloudTest.spec") },
    { Name = "SlowestTestsTest", Func = require("../Tests/SlowestTestsTest.spec") },
    { Name = "VersionUpdateTest", Func = require("../Tests/VersionUpdateTest.spec") },
}

const RunTests = {}

function RunTests.exec()
    const parsed, options, remaining = pcall(ReporterArguments.parse, process.args)
    if not parsed then
        print(tostring(options))
        process.exit(1)
    end
    if #remaining > 0 then
        print(`The argument "{remaining[1]}" is not recognized.`)
        print(`[Usage] ./Scripts/RunTests.exec.luau {ReporterArguments.Usage}`)
        process.exit(1)
    end

    Testable.configure(options)
    for _, reporter in options.Reporters or {} do
        if reporter == Testable.TestEnum.Reporter.Lcov then
            Testable.configure({ Coverage = true, CoverageRoots = script.Parent.Parent.Source.Testable })
        end
    end

    const _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

RunTests.exec()
