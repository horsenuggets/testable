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
> --workers <count> - Runs file jobs in that many isolated Lune VMs, or locally at 1.
> --worker-setup <path> - Loads a setup function before requiring specs in every job.
> --filter <text> - Only runs the tests whose full name contains the text.
> --reporter <text|json|junit|lcov> - Adds a reporter. It can be given several times, and
  "lcov" also turns on coverage for the source.
> --output <path> - Writes the reporter named just before it to a file instead of
  standard output.
> --slowest <count> - Lists that many of the slowest tests in the text report.
> --update-snapshots, -u - Accepts changed snapshots and removes obsolete ones.

[Usage] ./Scripts/RunTests.exec.luau [flags] [spec files...]

--]]

const FilterArguments = require("./Helpers/FilterArguments")
const ReporterArguments = require("./Helpers/ReporterArguments")
const RunTestsArguments = require("./Helpers/RunTestsArguments")
const SnapshotArguments = require("./Helpers/SnapshotArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")

const INCLUDE = { "Tests/**/*.spec.luau" }
const SCRIPT_PATH = "Scripts/RunTests.exec.luau"
const USAGE = `[Usage] ./{SCRIPT_PATH} {RunTestsArguments.Usage} {FilterArguments.Usage} `
    .. `{ReporterArguments.Usage} {SnapshotArguments.Usage} [spec files...]`

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
    @param workerOptions - Worker flags parsed before the watch branch configures a run
]]
const function watch(files: { string }, childArguments: { string }, workerOptions: RunTestsArguments.WorkerOptions)
    const ok, message = pcall(Testable.Discovery.watch, {
        Include = if #files > 0 then files else INCLUDE,
        Run = function(specFiles: { string })
            Testable.Discovery.runInChild({
                Arguments = childArguments,
                Files = specFiles,
                Script = SCRIPT_PATH,
            })
        end,
        WorkerSetup = workerOptions.WorkerSetup,
    })
    if not ok then
        exitWithToolError(tostring(message))
    end
end

function RunTests.exec()
    const workerOptions, workerRemaining, workerProblem = RunTestsArguments.extractWorkers(process.args)
    if workerOptions == nil then
        exitWithToolError(workerProblem :: string, true)
        return
    end

    -- Each parser takes the flags it knows and hands the rest to the next one. Snapshot
    -- flags come after the reporter and filter flags, so a value that belongs to another
    -- flag (e.g., an output path) is never mistaken for one.
    const parsed, reporterOptions, filterOptions, unparsed = pcall(function()
        const reporterOptions, unparsed = ReporterArguments.parse(workerRemaining)
        return reporterOptions, FilterArguments.parse(unparsed)
    end)
    if not parsed then
        exitWithToolError(tostring(reporterOptions), true)
    end

    const snapshotOptions, remaining = SnapshotArguments.parse(unparsed)
    const arguments, problem = RunTestsArguments.parse(remaining)
    if arguments == nil then
        exitWithToolError(problem :: string, true)
        return
    end

    if arguments.Watch then
        watch(arguments.Files, RunTestsArguments.without(process.args, remaining), workerOptions)
        return
    end

    -- Options that are not valid (e.g., coverage for the "lcov" reporter while
    -- LUNE_COVERAGE is off) are a problem with the run itself, not with a test.
    const configured, configurationProblem = pcall(function()
        Testable.configure(reporterOptions)
        Testable.configure(filterOptions)
        Testable.configure(snapshotOptions)
        Testable.configure(workerOptions)
        for _, reporter in reporterOptions.Reporters or {} do
            if reporter == Testable.TestEnum.Reporter.Lcov then
                Testable.configure({ Coverage = true, CoverageRoots = "Source/Testable" })
            end
        end

        -- A focus modifier left in a spec would silently skip every other test, so CI
        -- fails the run instead.
        const ci = process.env.CI
        Testable.configure({ ForbidFocus = ci ~= nil and ci ~= "" })
    end)
    if not configured then
        if not Testable.ToolError.is(configurationProblem) then
            error(configurationProblem, 0)
        end
        exitWithToolError(tostring(configurationProblem))
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
            process.exit(Testable.ExitCode.Passed)
        end
        files = affected
    end

    -- Select paths without requiring specs. The file runner must apply setup and choose
    -- worker ownership before any spec module is loaded.
    const ok, specFiles = pcall(Testable.Discovery.findSpecs, { Files = files, Include = INCLUDE })
    if not ok then
        exitWithToolError(tostring(specFiles))
    end

    const exitCode = Testable.runFilesToExitCode(specFiles)
    process.exit(exitCode)
end

RunTests.exec()
