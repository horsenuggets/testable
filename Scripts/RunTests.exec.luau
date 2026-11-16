#!/usr/bin/env -S lune run

--[[

RunTests.exec

Discovers every spec file in Tests/ and runs it, then exits with an appropriate status
code. The run can be narrowed to specific spec files, or to the specs affected by what
changed since a git ref. In watch mode, the affected specs run again whenever a file
they depend on changes. Reporter flags choose which reports the run produces and where
they go...

> --changed <ref> - Runs only the specs affected by the changes since a git ref.
> --watch - Keeps running, and runs the affected specs again whenever files change.
> --reporter <text|json|junit|lcov> - Adds a reporter. It can be given several times, and
  "lcov" also turns on coverage for the source.
> --output <path> - Writes the reporter named just before it to a file instead of
  standard output.
> --slowest <count> - Lists that many of the slowest tests in the text report.

[Usage] ./Scripts/RunTests.exec.luau [flags] [spec files...]

--]]

const ReporterArguments = require("./Helpers/ReporterArguments")
const RunTestsArguments = require("./Helpers/RunTestsArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")

const EXIT_CODE_FAILURE = 1
const EXIT_CODE_SUCCESS = 0
const EXIT_CODE_TOOL_ERROR = 2
const INCLUDE = { "Tests/**/*.spec.luau" }
const SCRIPT_PATH = "Scripts/RunTests.exec.luau"
const USAGE = `[Usage] ./{SCRIPT_PATH} {RunTestsArguments.Usage} {ReporterArguments.Usage} [spec files...]`

const RunTests = {}

--[[
    Prints a message and exits with the status code for a problem with the run itself,
    as opposed to a failing test.

    @param message - A sentence describing the problem
]]
const function exitWithToolError(message: string): never
    print(message)
    return process.exit(EXIT_CODE_TOOL_ERROR)
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
    const parsed, options, remaining = pcall(ReporterArguments.parse, process.args)
    if not parsed then
        exitWithToolError(tostring(options))
    end

    const arguments, problem = RunTestsArguments.parse(remaining)
    if arguments == nil then
        print(problem)
        exitWithToolError(USAGE)
        return
    end

    if arguments.Watch then
        watch(arguments.Files, RunTestsArguments.without(process.args, remaining))
        return
    end

    Testable.configure(options)
    for _, reporter in options.Reporters or {} do
        if reporter == Testable.TestEnum.Reporter.Lcov then
            Testable.configure({ Coverage = true, CoverageRoots = script.Parent.Parent.Source.Testable })
        end
    end

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
            process.exit(EXIT_CODE_SUCCESS)
        end
        files = affected
    end

    const ok, testRoots = pcall(Testable.Discovery.discover, { Files = files, Include = INCLUDE })
    if not ok then
        exitWithToolError(tostring(testRoots))
    end

    const _, passed = Testable.run(testRoots)
    process.exit(if passed then EXIT_CODE_SUCCESS else EXIT_CODE_FAILURE)
end

RunTests.exec()
