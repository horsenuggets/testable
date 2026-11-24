--[[

Coordinator

Partitions paths before requiring specs, waits for a global planning decision, and grants
ordinary files concurrent execution while Serial-bearing files run alone across all VMs.
Every worker is joined, including after infrastructure failures. Reporting belongs to the
caller.

--]]

const Coverage = require("../Coverage")
const Gates = require("./Gates")
const PathUtil = require("../Discovery/PathUtil")
const Protocol = require("./Protocol")
const Results = require("./Results")
const Scheduling = require("./Scheduling")
const SpecNames = require("../Discovery/SpecNames")
const SuiteOrder = require("../SuiteOrder")
const TestFilter = require("../TestFilter")
const ToolError = require("../ToolError")
const fs = require("@lune/fs")
const process = require("@lune/process")
const task = require("@lune/task")
const Coordinator = {}
local runCounter = 0

const function check(condition: any, message: string)
    if not condition then
        error(ToolError.new(ToolError.Kind.WorkerFailure, message), 0)
    end
end

const function raiseProblem(value: any, runId: string, jobId: number)
    if type(value) == "table" and value.Problem ~= nil then
        for key in pairs(value) do
            check(key == "Problem", "Unknown worker problem envelope field.")
        end
        error(Protocol.decodeProblem(value.Problem, runId, jobId), 0)
    end
end

const function array(value: any, label: string): number
    assert(type(value) == "table" and getmetatable(value) == nil, `{label} must be a plain array.`)
    local count = 0
    for key in pairs(value) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0, `{label} must be a dense array.`)
        count += 1
    end
    for index = 1, count do
        assert(value[index] ~= nil, `{label} must be a dense array.`)
    end
    return count
end

const function paths(files: any, root: string): { string }
    const count = array(files, "Files")
    const normalized = {}
    for index = 1, count do
        const file = files[index]
        assert(type(file) == "string" and file ~= "", "Files must contain nonempty paths.")
        const absolute = PathUtil.join(root, file)
        table.insert(normalized, PathUtil.relative(root, absolute) or absolute)
    end
    return normalized
end

const function validatePlanned(value: any, runId: string, job: any, names: { [string]: string }): any
    check(type(value) == "table", "The worker returned no planning summary.")
    for key in pairs(value) do
        check(
            key == "Assigned"
                or key == "ExclusiveRoots"
                or key == "HasFocus"
                or key == "JobId"
                or key == "RunId"
                or key == "Selection"
                or key == "SnapshotPaths"
                or key == "Version",
            `The worker planning summary contains an unknown field "{key}".`
        )
    end
    Protocol.validateManifest({
        Assigned = value.Assigned,
        Completed = value.Assigned,
        JobId = value.JobId,
        RunId = value.RunId,
        Version = value.Version,
    }, runId, job.Id, job.Files)
    check(type(value.HasFocus) == "boolean", "Invalid worker focus flag.")
    check(type(value.ExclusiveRoots) == "table", "Missing worker file scheduling flags.")
    const expectedRoots = {}
    for _, file in ipairs(job.Files) do
        expectedRoots[names[file]] = true
    end
    local rootCount = 0
    for name, exclusive in pairs(value.ExclusiveRoots) do
        check(expectedRoots[name] and type(exclusive) == "boolean", "Invalid worker file scheduling identity.")
        rootCount += 1
    end
    check(rootCount == #job.Files, "Missing worker file scheduling identity.")
    check(type(value.Selection) == "table", "Missing worker filter selection.")
    for key in pairs(value.Selection) do
        check(key == "Matched" or key == "PlanningErrors" or key == "Total", "Unknown worker selection field.")
    end
    for _, key in { "Matched", "PlanningErrors", "Total" } do
        const count = value.Selection[key]
        check(
            type(count) == "number" and count >= 0 and count < math.huge and count % 1 == 0,
            "Invalid worker selection count."
        )
    end
    check(value.Selection.Matched <= value.Selection.Total, "Worker matches exceed its planned test count.")
    const pathCount = array(value.SnapshotPaths, "Worker snapshot paths")
    const seen = {}
    for index = 1, pathCount do
        const path = value.SnapshotPaths[index]
        check(
            type(path) == "string" and PathUtil.isAbsolute(path) and PathUtil.normalize(path) == path,
            "Worker snapshot paths must be normalized absolute paths."
        )
        check(not seen[path], "Duplicate worker snapshot ownership path.")
        seen[path] = true
    end
    return value
end

function Coordinator.prepare(files: { string }, root: string?, options: any): any
    assert(root == nil or type(root) == "string", "root must be a string or nil")
    assert(type(options) == "table", "options must be a table")
    const absoluteRoot = PathUtil.join(process.cwd, root or ".")
    const normalized = paths(files, absoluteRoot)
    assert(#normalized > 0, "files must be a nonempty array")
    const names = SpecNames.assign(normalized)
    const descriptors = {}
    for _, file in ipairs(normalized) do
        assert(fs.isFile(PathUtil.join(absoluteRoot, file)), `The spec file "{file}" does not exist.`)
        table.insert(descriptors, { File = file, path = { names[file] }, pathStringForSorting = names[file]:lower() })
    end
    const orderedFiles = {}
    const orderedNames = {}
    for _, descriptor in SuiteOrder.modules(descriptors, options.Config.SuiteOrder) do
        table.insert(orderedFiles, descriptor.File)
        table.insert(orderedNames, names[descriptor.File])
    end
    const groups = {}
    const groupCount = array(options.Groups, "WorkerGroups")
    for index = 1, groupCount do
        table.insert(groups, paths(options.Groups[index], absoluteRoot))
    end
    const jobs = Scheduling.partition(orderedFiles, names, options.Workers, groups)
    const setup = if options.Setup ~= nil then PathUtil.join(absoluteRoot, options.Setup) else nil
    return {
        Files = orderedFiles,
        Jobs = jobs,
        Names = names,
        OrderedNames = orderedNames,
        Root = absoluteRoot,
        Setup = setup,
    }
end

function Coordinator.run(files: { string }, root: string?, options: any, redirectOutput: boolean): any
    assert(type(redirectOutput) == "boolean", "redirectOutput must be a boolean")
    const prepared = Coordinator.prepare(files, root, options)
    const absoluteRoot = prepared.Root
    const jobs = prepared.Jobs
    const names = prepared.Names
    const orderedNames = prepared.OrderedNames
    const setup = prepared.Setup
    const actor = require("@lune/actor")
    runCounter += 1
    const runId = tostring(runCounter)
    const startTime = os.clock()
    const records = {}
    const shards = {}
    const snapshots = {}
    local stopping = false

    const ok, outcome = pcall(function()
        for _, job in ipairs(jobs) do
            const handle = actor.spawn("./Entry.exec.luau", {
                args = {
                    {
                        Config = options.Config,
                        Files = job.Files,
                        JobId = job.Id,
                        Names = names,
                        RedirectOutput = redirectOutput,
                        Root = absoluteRoot,
                        RunId = runId,
                        Setup = setup,
                    },
                },
            })
            records[job.Id] = { Handle = handle, Joined = false }
        end
        const selection = { Matched = 0, PlanningErrors = 0, Total = 0 }
        const exclusive = {}
        const rootOwners = {}
        const snapshotOwners = {}
        local hasFocus = false
        for _, job in ipairs(jobs) do
            const record = records[job.Id]
            record.PlanStarted = true
            task.spawn(function()
                record.PlanResult = table.pack(pcall(record.Handle.receive, record.Handle, "Planned"))
                record.PlanDone = true
            end)
        end
        local unplanned = #jobs
        while unplanned > 0 do
            for _, job in ipairs(jobs) do
                const record = records[job.Id]
                if record.PlanDone and not record.Planned then
                    record.Planned = true
                    unplanned -= 1
                    const received, summary = table.unpack(record.PlanResult)
                    if not received then
                        const joined, problem = record.Handle:join()
                        record.Joined = true
                        if joined then
                            raiseProblem(problem, runId, job.Id)
                        end
                        check(
                            false,
                            if joined then "The worker exited before completing planning." else tostring(problem)
                        )
                    end
                    const planned = validatePlanned(summary, runId, job, names)
                    for _, path in ipairs(planned.SnapshotPaths) do
                        const owner = snapshotOwners[path]
                        if owner ~= nil and owner ~= job.Id then
                            error(
                                ToolError.new(
                                    ToolError.Kind.InvalidConfiguration,
                                    `The snapshot path "{path}" belongs to multiple workers. `
                                        .. "Put the specs that share it in one WorkerGroups entry."
                                ),
                                0
                            )
                        end
                        snapshotOwners[path] = job.Id
                    end
                    hasFocus = hasFocus or planned.HasFocus
                    for name, isExclusive in pairs(planned.ExclusiveRoots) do
                        exclusive[name] = isExclusive
                        rootOwners[name] = job.Id
                    end
                    for key in pairs(selection) do
                        selection[key] += planned.Selection[key]
                    end
                end
            end
            if unplanned > 0 then
                task.wait()
            end
        end
        if TestFilter.isEmpty(selection, options.Config.Filter) then
            const noun = if selection.Total == 1 then "test" else "tests"
            error(
                ToolError.new(
                    ToolError.Kind.EmptyFilter,
                    `The filter "{options.Config.Filter}" did not match any of the {selection.Total} planned {noun}.`
                ),
                0
            )
        end
        const gates = Gates.new(orderedNames, exclusive, rootOwners)
        const function checkGateProblems()
            for _, record in ipairs(records) do
                check(record.GateProblem == nil, tostring(record.GateProblem))
            end
        end
        for _, job in ipairs(jobs) do
            const record = records[job.Id]
            record.GateStarted = true
            task.spawn(function()
                const pumped, problem = pcall(function()
                    while not stopping do
                        const received, event = pcall(record.Handle.receive, record.Handle, "Gate")
                        if not received or stopping then
                            break
                        end
                        check(type(event) == "table", "Invalid file gate event.")
                        for key in pairs(event) do
                            check(
                                key == "Id" or key == "JobId" or key == "Kind" or key == "Name" or key == "RunId",
                                "Unknown file gate event field."
                            )
                        end
                        check(
                            event.RunId == runId and event.JobId == job.Id,
                            "The file gate event belongs to another job."
                        )
                        check(event.Kind == "Acquire" or event.Kind == "Release", "Unknown file gate event kind.")
                        const grants = if event.Kind == "Acquire"
                            then Gates.request(gates, job.Id, event.Id, event.Name)
                            else Gates.release(gates, job.Id, event.Id, event.Name)
                        for _, grant in ipairs(grants) do
                            records[grant.JobId].Handle:send(`Root/{grant.RequestId}`, {
                                Id = grant.RequestId,
                                JobId = grant.JobId,
                                Name = grant.Name,
                                RunId = runId,
                            })
                        end
                    end
                end)
                if not pumped then
                    record.GateProblem = problem
                end
                record.GateDone = true
            end)
        end
        for _, job in ipairs(jobs) do
            records[job.Id].Handle:send("Execute", { HasFocus = hasFocus, JobId = job.Id, RunId = runId })
        end
        for _, job in ipairs(jobs) do
            const record = records[job.Id]
            record.JoinStarted = true
            task.spawn(function()
                record.Executed = table.pack(pcall(record.Handle.receive, record.Handle, "Executed"))
                record.JoinResult = table.pack(pcall(record.Handle.join, record.Handle))
                record.Joined = true
            end)
        end
        -- Observe every completion, not just the first job in order. A failed peer must
        -- terminate a stuck earlier job rather than waiting behind it forever.
        local remaining = #jobs
        while remaining > 0 do
            checkGateProblems()
            for _, job in ipairs(jobs) do
                const record = records[job.Id]
                if record.Joined and not record.Processed then
                    record.Processed = true
                    remaining -= 1
                    const joinResult = record.JoinResult
                    check(joinResult[1], tostring(joinResult[2]))
                    check(joinResult[2], `Worker {job.Id} failed. {tostring(joinResult[3])}`)
                    const value = joinResult[3]
                    raiseProblem(value, runId, job.Id)
                    check(type(value) == "table", `Worker {job.Id} returned no completion manifest.`)
                    check(record.Executed[1], "The worker omitted its execution completion signal.")
                    const executed = record.Executed[2]
                    check(
                        type(executed) == "table"
                            and executed.Version == 1
                            and executed.RunId == runId
                            and executed.JobId == job.Id,
                        "The worker returned an invalid execution completion signal."
                    )
                    for key in pairs(executed) do
                        check(key == "JobId" or key == "RunId" or key == "Version", "Unknown execution signal field.")
                    end
                    for key in pairs(value) do
                        check(
                            key == "Coverage" or key == "Manifest" or key == "Results",
                            "Unknown worker completion field."
                        )
                    end
                    Protocol.validateManifest(value.Manifest, runId, job.Id, job.Files)
                    table.insert(shards, Protocol.decodeResults(value.Results))
                    if value.Coverage ~= nil then
                        table.insert(snapshots, value.Coverage)
                    end
                end
            end
            if remaining > 0 then
                task.wait()
            end
        end
        for _, record in ipairs(records) do
            while not record.GateDone do
                checkGateProblems()
                task.wait()
            end
        end
        checkGateProblems()
        check(Gates.finished(gates), "Workers did not finish every assigned file execution gate.")
        check(#snapshots == 0 or #snapshots == #jobs, "Some workers omitted their coverage snapshots.")
        if options.Config.Coverage and options.Config.CoverageRoots ~= nil then
            check(#snapshots == #jobs, "Workers omitted the configured coverage roots.")
        end
        return {
            RawCoverage = if #snapshots > 0 then Coverage.mergeRaw(snapshots) else nil,
            Results = Results.merge(
                shards,
                orderedNames,
                options.Config.Filter,
                options.Config.ForbidFocus,
                os.clock() - startTime
            ),
        }
    end)

    stopping = true
    -- Stop every remaining worker before joining any of them, so workers waiting at the
    -- planning barrier cannot hold cleanup open after another worker failed.
    for _, record in ipairs(records) do
        if not record.Joined then
            record.Handle:terminate()
        end
    end
    for _, record in ipairs(records) do
        if record.PlanStarted then
            while not record.PlanDone do
                task.wait()
            end
        end
        if record.JoinStarted then
            while not record.Joined do
                task.wait()
            end
        elseif not record.Joined then
            record.Handle:join()
        end
        if record.GateStarted then
            while not record.GateDone do
                task.wait()
            end
        end
    end
    if not ok then
        if ToolError.is(outcome) then
            error(outcome, 0)
        end
        error(ToolError.new(ToolError.Kind.WorkerFailure, tostring(outcome)), 0)
    end
    return outcome
end

return Coordinator
