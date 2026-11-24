#!/usr/bin/env -S lune run

--[[

Entry.exec

Plans and executes one isolated file shard. Planning pauses at the coordinator's barrier
before any test or lifecycle hook runs. Only plain results and exact raw coverage leave
the worker VM.

--]]

const Config = require("../Config")
const Coverage = require("../Coverage")
const Discovery = require("../Discovery")
const PathUtil = require("../Discovery/PathUtil")
const Protocol = require("./Protocol")
const SnapshotManager = require("../Snapshots/SnapshotManager")
const StandardOutputGuard = require("../Reporters/StandardOutputGuard")
const TestBootstrap = require("../TestBootstrap")
const TestFilter = require("../TestFilter")
const TestPlanner = require("../TestPlanner")
const TestRunner = require("../TestRunner")
const ToolError = require("../ToolError")
const actor = require("@lune/actor")
const process = require("@lune/process")
const Entry = {}

const function containsSerial(node: any): boolean
    if node.serial == true then
        return true
    end
    for _, child in ipairs(node.children) do
        if containsSerial(child) then
            return true
        end
    end
    return false
end

function Entry.exec(): any
    const parent = assert(actor.parent, "The Testable worker must run inside an actor.")
    const job = actor.args[1]
    assert(type(job) == "table", "The Testable worker requires a job.")
    const ok, outcome = xpcall(function()
        return StandardOutputGuard.run(job.RedirectOutput, function()
            const snapshotPaths = {}
            const allowedPaths = {}
            TestRunner.SnapshotPathGuard = function(path: string)
                const normalized = PathUtil.join(process.cwd, path)
                assert(
                    allowedPaths[normalized],
                    `The snapshot path "{normalized}" was not assigned to this worker during planning. `
                        .. "Group its spec with the owning files or use an independent worker-local snapshot store."
                )
            end
            Config.set(job.Config)
            if job.Setup ~= nil then
                const setup = Discovery.Loader.load(job.Setup)
                assert(type(setup) == "function", "WorkerSetup must return a function.")
                setup(require("../../Testable"), {
                    Files = table.clone(job.Files),
                    JobId = job.JobId,
                    Root = job.Root,
                })
            end

            -- Setup can create Instance-valued roots inside this VM. Spec registration and
            -- tests must not be able to erase the roots captured for this run.
            const coverageRoots = Config.CoverageRoots
            const roots = Discovery.load(job.Files, job.Root)
            for index, root in ipairs(roots) do
                root.Name = job.Names[job.Files[index]]
            end
            const modules = TestBootstrap:getModulesFromMultipleRoots(roots)
            const plan = TestPlanner.createPlan(modules, nil, nil, job.Config.SuiteOrder)
            const selection = TestFilter.apply(plan, job.Config.Filter)
            plan.forbidFocus = job.Config.ForbidFocus
            const exclusiveRoots = {}
            for _, specNode in ipairs(plan.children) do
                exclusiveRoots[specNode.phrase] = containsSerial(specNode)
            end
            if Config.SnapshotStore == nil then
                const resolver = SnapshotManager.new({ HasFilesystem = false })
                for _, specNode in ipairs(plan.children) do
                    const path = PathUtil.join(process.cwd, resolver:_resolvePath(specNode))
                    if not allowedPaths[path] then
                        allowedPaths[path] = true
                        table.insert(snapshotPaths, path)
                    end
                end
                table.sort(snapshotPaths)
            end

            parent:send("Planned", {
                Assigned = table.clone(job.Files),
                ExclusiveRoots = exclusiveRoots,
                HasFocus = TestFilter.hasFocus(plan),
                JobId = job.JobId,
                RunId = job.RunId,
                Selection = selection,
                SnapshotPaths = snapshotPaths,
                Version = 1,
            })
            const command = parent:receive("Execute")
            assert(
                type(command) == "table" and type(command.HasFocus) == "boolean",
                "Invalid worker execution command."
            )
            assert(
                command.RunId == job.RunId and command.JobId == job.JobId,
                "The execution command belongs to another job."
            )
            local requestId = 0
            const function sendGate(kind: string, node: any, id: number)
                parent:send("Gate", { Id = id, JobId = job.JobId, Kind = kind, Name = node.phrase, RunId = job.RunId })
            end
            const results = TestRunner.runPlan(plan, {
                ForbidFocus = false,
                HasFocus = command.HasFocus,
                RootGate = {
                    Acquire = function(node)
                        requestId += 1
                        const id = requestId
                        sendGate("Acquire", node, id)
                        const grant = parent:receive(`Root/{id}`)
                        assert(
                            type(grant) == "table"
                                and grant.RunId == job.RunId
                                and grant.JobId == job.JobId
                                and grant.Id == id
                                and grant.Name == node.phrase,
                            "Invalid file execution grant."
                        )
                        return id
                    end,
                    Release = function(node, id)
                        sendGate("Release", node, id)
                    end,
                },
            })
            const completed = {
                Coverage = if job.Config.Coverage and coverageRoots ~= nil
                    then Coverage.captureRaw(coverageRoots)
                    else nil,
                Manifest = Protocol.makeManifest(job.RunId, job.JobId, job.Files, table.clone(job.Files)),
                Results = Protocol.encodeResults(results),
            }
            -- join closes the parent's sending endpoint. The coordinator waits for this
            -- signal before joining, so file grants remain deliverable until execution ends.
            parent:send("Executed", { JobId = job.JobId, RunId = job.RunId, Version = 1 })
            return completed
        end)
    end, function(problem)
        return if ToolError.is(problem) then problem else debug.traceback(tostring(problem), 2)
    end)
    if not ok then
        if ToolError.is(outcome) then
            return { Problem = Protocol.encodeProblem(outcome, job.RunId, job.JobId) }
        end
        error(outcome, 0)
    end
    return outcome
end

return Entry.exec()
