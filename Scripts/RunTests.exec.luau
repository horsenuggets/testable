#!/usr/bin/env -S lune run

--[[

RunTests.exec

Discovers every spec file in Tests/ and runs it. Exits with 0 when the tests pass, 1 when
tests fail, and 2 for a tool error such as an unrecognized argument, an unknown git ref,
or a filter that matches no tests. The run can be narrowed to specific spec files, to the
specs affected by what changed since a git ref, or to the tests a filter matches. In
watch mode, the affected specs run again whenever a file they depend on changes.
Reporter flags choose which reports the run produces and where they go...

> --changed <ref> - Runs only the specs affected by the changes since a git ref.
> --watch - Keeps running, and runs the affected specs again whenever files change.
> --filter <text> - Only runs the tests whose full name contains the text.
> --reporter <text|json|junit|lcov> - Adds a reporter. It can be given several times, and
  "lcov" also turns on coverage for the source.
> --output <path> - Writes the reporter named just before it to a file instead of
  standard output.
> --slowest <count> - Lists that many of the slowest tests in the text report.

[Usage] ./Scripts/RunTests.exec.luau [flags] [spec files...]

--]]

const FilterArguments = require("./Helpers/FilterArguments")
const ReporterArguments = require("./Helpers/ReporterArguments")
const RunTestsArguments = require("./Helpers/RunTestsArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")

const INCLUDE = { "Tests/**/*.spec.luau" }
const SCRIPT_PATH = "Scripts/RunTests.exec.luau"
const USAGE = `[Usage] ./{SCRIPT_PATH} {RunTestsArguments.Usage} {FilterArguments.Usage} `
    .. `{ReporterArguments.Usage} [spec files...]`

const RunTests = {}

--[[
    Prints a message and exits with the status code for a problem with the run itself,
    as opposed to a failing test.

    @param message - A sentence describing the problem
    @param showUsage - Whether to print the usage line as well
]]
const function exitWithToolError(message: string, showUsage: boolean?): never
    print(message)
    if showUsage then
        print(USAGE)
    end
    return process.exit(Testable.ExitCode.ToolError)
end

--[[
    Keeps this process alive as the watcher. Every pass runs in a child process, because
    Lune caches required modules and this process would keep running the code it loaded
    first.

    @param files - Spec files to watch instead of every spec, when any were given
    @param childArguments - The flags to hand on to every pass
]]
const function watch(files: { string }, childArguments: { string })
    const ok, message = pcall(Testable.Discovery.watch, {
        Include = if #files > 0 then files else INCLUDE,
        Run = function(specFiles: { string })
            Testable.Discovery.runInChild({
                Arguments = childArguments,
                Files = specFiles,
                Script = SCRIPT_PATH,
            })
        end,
    })
    if not ok then
        exitWithToolError(tostring(message))
    end
end

function RunTests.exec()
    -- Each parser takes the flags it knows and hands the rest to the next one
    const parsed, reporterOptions, filterOptions, remaining = pcall(function()
        const reporterOptions, unparsed = ReporterArguments.parse(process.args)
        return reporterOptions, FilterArguments.parse(unparsed)
    end)
    if not parsed then
        exitWithToolError(tostring(reporterOptions), true)
    end

    const arguments, problem = RunTestsArguments.parse(remaining)
    if arguments == nil then
        exitWithToolError(problem :: string, true)
        return
    end

    if arguments.Watch then
        watch(arguments.Files, RunTestsArguments.without(process.args, remaining))
        return
    end

    Testable.configure(reporterOptions)
    Testable.configure(filterOptions)
    for _, reporter in reporterOptions.Reporters or {} do
        if reporter == Testable.TestEnum.Reporter.Lcov then
            Testable.configure({ Coverage = true, CoverageRoots = script.Parent.Parent.Source.Testable })
        end
    end

    -- A focus modifier left in a spec would silently skip every other test, so CI fails
    -- the run instead.
    const ci = process.env.CI
    Testable.configure({ ForbidFocus = ci ~= nil and ci ~= "" })

    local files: { string }? = if #arguments.Files > 0 then arguments.Files else nil
    if arguments.Changed ~= nil then
        const ok, affected = pcall(Testable.Discovery.findChanged, {
            Include = INCLUDE,
            Ref = arguments.Changed,
        })
        if not ok then
            exitWithToolError(tostring(affected))
        end
        if #affected == 0 then
            print(`No specs are affected by the changes since "{arguments.Changed}".`)
            process.exit(Testable.ExitCode.Passed)
        end
        files = affected
    end

    const ok, testRoots = pcall(Testable.Discovery.discover, { Files = files, Include = INCLUDE })
    if not ok then
        exitWithToolError(tostring(testRoots))
    end

    const exitCode = Testable.runToExitCode(testRoots)
    process.exit(exitCode)
end

RunTests.exec()
