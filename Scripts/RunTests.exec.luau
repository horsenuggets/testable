#!/usr/bin/env -S lune run

--[[

RunTests.exec

Discovers every spec file in Tests/ and runs it, then exits with an appropriate status
code. The run can be narrowed to specific spec files, or to the specs affected by what
changed since a git ref. In watch mode, the affected specs run again whenever a file
they depend on changes.

[Usage] ./Scripts/RunTests.exec.luau [--changed <ref>] [--watch] [spec files...]

--]]

const RunTestsArguments = require("./Helpers/RunTestsArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")

const EXIT_CODE_FAILURE = 1
const EXIT_CODE_SUCCESS = 0
const EXIT_CODE_TOOL_ERROR = 2
const INCLUDE = { "Tests/**/*.spec.luau" }
const SCRIPT_PATH = "Scripts/RunTests.exec.luau"

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
]]
const function watch(files: { string })
    const ok, message = pcall(Testable.Discovery.watch, {
        Include = if #files > 0 then files else INCLUDE,
        Run = function(specFiles: { string })
            Testable.Discovery.runInChild({ Files = specFiles, Script = SCRIPT_PATH })
        end,
    })
    if not ok then
        exitWithToolError(tostring(message))
    end
end

function RunTests.exec()
    const arguments, problem = RunTestsArguments.parse(process.args)
    if arguments == nil then
        print(problem)
        exitWithToolError(RunTestsArguments.Usage)
        return
    end

    if arguments.Watch then
        watch(arguments.Files)
        return
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
