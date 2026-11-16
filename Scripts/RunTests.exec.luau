#!/usr/bin/env -S lune run

--[[

RunTests.exec

Executes all test suites and exits with 0 when they pass, 1 when tests fail, and 2 for a
tool error such as an unrecognized argument or a filter that matches no tests. The
filter flag narrows the run, and reporter flags choose which reports the run produces
and where they go...

> --filter <text> - Only runs the tests whose full name contains the text.
> --reporter <text|json|junit|lcov> - Adds a reporter. It can be given several times, and
  "lcov" also turns on coverage for the source.
> --output <path> - Writes the reporter named just before it to a file instead of
  standard output.
> --slowest <count> - Lists that many of the slowest tests in the text report.
> --update-snapshots, -u - Accepts changed snapshots and removes obsolete ones.

[Usage] ./Scripts/RunTests.exec.luau [--filter "<text>"] [reporter flags] [snapshot flags]

--]]

const FilterArguments = require("./Helpers/FilterArguments")
const ReporterArguments = require("./Helpers/ReporterArguments")
const SnapshotArguments = require("./Helpers/SnapshotArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")
const USAGE = `[Usage] ./Scripts/RunTests.exec.luau {FilterArguments.Usage} {ReporterArguments.Usage} `
    .. SnapshotArguments.Usage

const TESTS = {
    { Name = "CloudPlaceTest", Func = require("../Tests/CloudPlaceTest.spec") },
    { Name = "ConfigTest", Func = require("../Tests/ConfigTest.spec") },
    { Name = "CoverageTest", Func = require("../Tests/CoverageTest.spec") },
    { Name = "DescribeModifierTest", Func = require("../Tests/DescribeModifierTest.spec") },
    { Name = "DictSyntaxTest", Func = require("../Tests/DictSyntaxTest.spec") },
    { Name = "ExampleTest", Func = require("../Tests/ExampleTest.spec") },
    { Name = "ExpectationTest", Func = require("../Tests/ExpectationTest.spec") },
    { Name = "FailTest", Func = require("../Tests/FailTest.spec") },
    { Name = "FilterArgumentsTest", Func = require("../Tests/FilterArgumentsTest.spec") },
    { Name = "FilterTest", Func = require("../Tests/FilterTest.spec") },
    { Name = "FocusGuardTest", Func = require("../Tests/FocusGuardTest.spec") },
    { Name = "JUnitReporterTest", Func = require("../Tests/JUnitReporterTest.spec") },
    { Name = "JsonReporterTest", Func = require("../Tests/JsonReporterTest.spec") },
    { Name = "LcovReporterTest", Func = require("../Tests/LcovReporterTest.spec") },
    { Name = "LegacyGlobalsTest", Func = require("../Tests/LegacyGlobalsTest.spec") },
    { Name = "LifecycleTest", Func = require("../Tests/LifecycleTest.spec") },
    { Name = "MatcherTest", Func = require("../Tests/MatcherTest.spec") },
    { Name = "NestedRunTest", Func = require("../Tests/NestedRunTest.spec") },
    { Name = "ParallelHooksTest", Func = require("../Tests/ParallelHooksTest.spec") },
    { Name = "PlanningErrorTest", Func = require("../Tests/PlanningErrorTest.spec") },
    { Name = "ReporterArgumentsTest", Func = require("../Tests/ReporterArgumentsTest.spec") },
    { Name = "ReporterSelectionTest", Func = require("../Tests/ReporterSelectionTest.spec") },
    { Name = "ReporterTest", Func = require("../Tests/ReporterTest.spec") },
    { Name = "RobloxCloudTest", Func = require("../Tests/RobloxCloudTest.spec") },
    { Name = "SkipReasonTest", Func = require("../Tests/SkipReasonTest.spec") },
    { Name = "SlowestTestsTest", Func = require("../Tests/SlowestTestsTest.spec") },
    { Name = "SnapshotTest", Func = require("../Tests/SnapshotTest.spec") },
    { Name = "SpecApiTest", Func = require("../Tests/SpecApiTest.spec") },
    { Name = "TestScopeTest", Func = require("../Tests/TestScopeTest.spec") },
    { Name = "ToolErrorTest", Func = require("../Tests/ToolErrorTest.spec") },
    { Name = "ValueInspectorTest", Func = require("../Tests/ValueInspectorTest.spec") },
    { Name = "VersionUpdateTest", Func = require("../Tests/VersionUpdateTest.spec") },
}

const RunTests = {}

function RunTests.exec()
    -- Each parser takes the flags it knows and hands the rest to the next one. Snapshot
    -- flags come last, so a value that belongs to another flag (e.g., an output path) is
    -- never mistaken for one.
    const parsed, reporterOptions, filterOptions, unparsed = pcall(function()
        const reporterOptions, unparsed = ReporterArguments.parse(process.args)
        return reporterOptions, FilterArguments.parse(unparsed)
    end)
    if not parsed then
        print(tostring(reporterOptions))
        print(USAGE)
        process.exit(Testable.ExitCode.ToolError)
    end

    const snapshotOptions, remaining = SnapshotArguments.parse(unparsed)
    if #remaining > 0 then
        print(`The argument "{remaining[1]}" is not recognized.`)
        print(USAGE)
        process.exit(Testable.ExitCode.ToolError)
    end

    Testable.configure(reporterOptions)
    Testable.configure(filterOptions)
    Testable.configure(snapshotOptions)
    for _, reporter in reporterOptions.Reporters or {} do
        if reporter == Testable.TestEnum.Reporter.Lcov then
            Testable.configure({ Coverage = true, CoverageRoots = script.Parent.Parent.Source.Testable })
        end
    end

    -- A focus modifier left in a spec would silently skip every other test, so CI fails
    -- the run instead.
    const ci = process.env.CI
    Testable.configure({ ForbidFocus = ci ~= nil and ci ~= "" })

    const exitCode = Testable.runToExitCode(TESTS)
    process.exit(exitCode)
end

RunTests.exec()
