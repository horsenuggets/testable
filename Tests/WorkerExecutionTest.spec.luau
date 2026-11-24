--[[

WorkerExecutionTest.spec

Runs the public file API in fresh processes against real actor VMs. Fixtures verify
cross-shard planning decisions, exact membership, actual concurrency and cleanup after
workers exit without completing their assignments.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const expect, it = Testable.expect, Testable.it
const TEMPLATE = [[
    const fs = require("@lune/fs")
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")
    const PathUtil = Testable.Discovery.PathUtil
    const fixtureRoot = PathUtil.join(process.cwd, `_temp_worker_{os.time()}_{math.random(1, 1000000000)}`)
    assert(not fs.isDir(fixtureRoot), "The fixture directory already exists.")
    fs.writeDir(fixtureRoot)
    const ok, problem = xpcall(function()
        const sources = %s
        for name, source in pairs(sources) do
            const path = PathUtil.join(fixtureRoot, name)
            const directory = PathUtil.dirname(path)
            if not fs.isDir(directory) then
                fs.writeDir(directory)
            end
            fs.writeFile(path, source)
        end
        Testable.configure({ Reporters = {}, Workers = 2 })
        %s
    end, debug.traceback)
    fs.removeDir(fixtureRoot)
    assert(ok, problem)
]]
const SETUP = [[
    return function(_testable, context)
        _G.WorkerRoot = context.Root
    end
]]
const WAIT = [[
    const fs = require("@lune/fs")
    const task = require("@lune/task")
    const function waitFor(name)
        const deadline = os.clock() + 5
        while not fs.isFile(_G.WorkerRoot .. "/" .. name) do
            assert(os.clock() < deadline, "The peer worker did not reach its rendezvous.")
            task.wait()
        end
    end
]]

const function run(sources: { [string]: string }, body: string): (string, string)
    const names = {}
    for name in pairs(sources) do
        table.insert(names, name)
    end
    table.sort(names)
    const fields = {}
    for _, name in ipairs(names) do
        table.insert(fields, string.format("[%q] = %q", name, sources[name]))
    end
    const scriptSource = string.format(TEMPLATE, "{ " .. table.concat(fields, ", ") .. " }", body)
    const ok, output, errors = Subprocess.runScriptStreams(scriptSource)
    assert(ok, output .. errors)
    return output, errors
end

return function()
    it("should preserve globally disambiguated names and SuiteOrder under reversed completion", function()
        run(
            {
                ["A/Same.spec.luau"] = [[
                const task = require("@lune/task")
                return function()
                    it("first", function() task.wait(0.03) end)
                end
            ]],
                ["B/Same.spec.luau"] = 'return function() it("second", function() end) end',
            },
            [[
            Testable.configure({ SuiteOrder = { "B/Same", "A/Same" } })
            const results, passed = Testable.runFiles({ "A/Same.spec.luau", "B/Same.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 2)
            assert(results.children[1].planNode.phrase == "B/Same")
            assert(results.children[2].planNode.phrase == "A/Same")
            assert(results.children[2].children[1].planNode:getFullName() == "A/Same first")
            assert(results.children[2].children[1].planNode.plan == results.planNode)
        ]]
        )
    end)

    it("should retain a total grant order for case-equivalent names in sequential workers", function()
        run(
            {
                ["A/Foo.spec.luau"] = 'return function() it("passes", function() end) end',
                ["B/FOO.spec.luau"] = 'return function() it("passes", function() end) end',
                ["C/FoO.spec.luau"] = 'return function() it("passes", function() end) end',
                ["D/fOO.spec.luau"] = 'return function() it("passes", function() end) end',
            },
            [[
            const files = { "A/Foo.spec.luau", "B/FOO.spec.luau", "C/FoO.spec.luau", "D/fOO.spec.luau" }
            for _, workers in { 1, 2, 4 } do
                Testable.configure({ Parallel = false, Workers = workers, WorkerGroups = { files } })
                const results, passed = Testable.runFiles(files, fixtureRoot)
                assert(passed and results.successCount == 4)
                const names = {}
                for _, node in results.children do table.insert(names, node.planNode.phrase) end
                assert(table.concat(names, ",") == "FOO,FoO,Foo,fOO")
            end
        ]]
        )
    end)

    it("should coordinate focus globally and emit exactly one focus guard", function()
        run(
            {
                ["Focused.spec.luau"] = 'return function() itFOCUS("chosen", function() end) end',
                ["Ordinary.spec.luau"] = 'return function() it("excluded", function() error("must not execute") end) end',
            },
            [[
            Testable.configure({ ForbidFocus = true })
            const results, passed = Testable.runFiles({ "Focused.spec.luau", "Ordinary.spec.luau" }, fixtureRoot)
            assert(not passed)
            assert(results.successCount == 1 and results.failureCount == 1 and results.skippedCount == 1)
            assert(results.focusExcludedCount == 1 and results.focusGuardFailed)
            assert(#results.children == 3 and results.focusGuardNode == results.children[3])
            assert(#results.errors == 1)
        ]]
        )
    end)

    it("should decide empty filters only after every shard has planned", function()
        run(
            {
                ["A.spec.luau"] = 'return function() it("selected", function() end) end',
                ["B.spec.luau"] = 'return function() itFOCUS("other", function() error("filtered") end) end',
            },
            [[
            const files = { "A.spec.luau", "B.spec.luau" }
            Testable.configure({ Filter = "selected", ForbidFocus = true })
            const results, passed = Testable.runFiles(files, fixtureRoot)
            assert(passed and results.successCount == 1 and results.filteredCount == 1)
            assert(results.focusExcludedCount == 0)
            Testable.configure({ Filter = "absent" })
            const ok, problem = pcall(Testable.runFiles, files, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "EmptyFilter")
            Testable.configure({ Filter = "" })
            const again = Testable.runFiles(files, fixtureRoot)
            assert(again.failureCount == 2 and again.focusExcludedCount == 1)
        ]]
        )
    end)

    it("should execute ordinary shards concurrently in separate VMs", function()
        run(
            {
                ["A.spec.luau"] = WAIT .. [[
                return function()
                    it("meets the other VM", function()
                        assert(_G.Owned == nil)
                        _G.Owned = "A"
                        fs.writeFile(_G.WorkerRoot .. "/a-started", "")
                        waitFor("b-started")
                        assert(_G.Owned == "A")
                    end)
                end
            ]],
                ["B.spec.luau"] = WAIT .. [[
                return function()
                    it("meets the other VM", function()
                        assert(_G.Owned == nil)
                        _G.Owned = "B"
                        fs.writeFile(_G.WorkerRoot .. "/b-started", "")
                        waitFor("a-started")
                        assert(_G.Owned == "B")
                    end)
                end
            ]],
                ["Setup.luau"] = SETUP,
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 2, table.concat(results.errors, "\n"))
        ]]
        )
    end)

    it("should exclude every other shard for Serial files including their outer hooks", function()
        run(
            {
                ["A.spec.luau"] = WAIT .. [[
                return function()
                    beforeAll(function()
                        fs.writeFile(_G.WorkerRoot .. "/a-before", "")
                        waitFor("release-a-before")
                        assert(not fs.isFile(_G.WorkerRoot .. "/b-started"))
                    end)
                    it("runs ordinarily", function() end)
                    afterAll(function()
                        fs.writeFile(_G.WorkerRoot .. "/a-after", "")
                        waitFor("release-a-after")
                        assert(not fs.isFile(_G.WorkerRoot .. "/b-started"))
                        fs.writeFile(_G.WorkerRoot .. "/a-done", "")
                    end)
                end
            ]],
                ["B.spec.luau"] = WAIT .. [[
                return function()
                    beforeAll(function()
                        assert(fs.isFile(_G.WorkerRoot .. "/a-done"))
                        fs.writeFile(_G.WorkerRoot .. "/b-started", "")
                    end)
                    it("runs exclusively", function() end, { Serial = true })
                    afterAll(function()
                        waitFor("release-b-after")
                        assert(not fs.isFile(_G.WorkerRoot .. "/c-started"))
                        fs.writeFile(_G.WorkerRoot .. "/b-done", "")
                    end)
                end
            ]],
                ["C.spec.luau"] = WAIT .. [[
                return function()
                    beforeAll(function()
                        assert(fs.isFile(_G.WorkerRoot .. "/b-done"))
                        fs.writeFile(_G.WorkerRoot .. "/c-started", "")
                    end)
                    it("runs afterward", function() end)
                end
            ]],
                ["Setup.luau"] = SETUP,
            },
            [[
            Testable.configure({ Workers = 3, WorkerSetup = "Setup.luau" })
            local released = false
            const function await(name)
                const deadline = os.clock() + 5
                while not fs.isFile(fixtureRoot .. "/" .. name) do
                    assert(os.clock() < deadline, "The hook did not reach its rendezvous.")
                    task.wait()
                end
            end
            task.spawn(function()
                await("a-before")
                assert(not fs.isFile(fixtureRoot .. "/b-started"))
                fs.writeFile(fixtureRoot .. "/release-a-before", "")
                await("a-after")
                assert(not fs.isFile(fixtureRoot .. "/b-started"))
                fs.writeFile(fixtureRoot .. "/release-a-after", "")
                await("b-started")
                assert(not fs.isFile(fixtureRoot .. "/c-started"))
                fs.writeFile(fixtureRoot .. "/release-b-after", "")
                released = true
            end)
            const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau", "C.spec.luau" }, fixtureRoot)
            assert(released and passed and results.successCount == 3, table.concat(results.errors, "\n"))
        ]]
        )
    end)

    it("should overlap ordinary files even when their worker also owns a Serial file", function()
        run(
            {
                ["A.spec.luau"] = WAIT .. [[
                return function()
                    it("overlaps B", function()
                        fs.writeFile(_G.WorkerRoot .. "/a-started", "")
                        waitFor("b-started")
                        fs.writeFile(_G.WorkerRoot .. "/a-done", "")
                    end)
                end
            ]],
                ["B.spec.luau"] = WAIT .. [[
                return function()
                    it("overlaps A", function()
                        fs.writeFile(_G.WorkerRoot .. "/b-started", "")
                        waitFor("a-started")
                        fs.writeFile(_G.WorkerRoot .. "/b-done", "")
                    end)
                end
            ]],
                ["C.spec.luau"] = WAIT
                    .. [[
                return function()
                    beforeAll(function()
                        assert(fs.isFile(_G.WorkerRoot .. "/a-done") and fs.isFile(_G.WorkerRoot .. "/b-done"))
                    end)
                    it("runs exclusively", function()
                        fs.writeFile(_G.WorkerRoot .. "/c-done", "")
                    end, { Serial = true })
                end
            ]],
                ["D.spec.luau"] = WAIT .. [[
                return function()
                    it("runs after the exclusive", function()
                        assert(fs.isFile(_G.WorkerRoot .. "/c-done"))
                    end)
                end
            ]],
                ["Setup.luau"] = SETUP,
            },
            [[
            Testable.configure({ Parallel = false, WorkerSetup = "Setup.luau" })
            const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau", "C.spec.luau", "D.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 4, table.concat(results.errors, "\n"))
        ]]
        )
    end)

    it("should invoke setup before requiring specs in local and actor execution", function()
        for _, workers in { 1, 2 } do
            run(
                {
                    ["A.spec.luau"] = [[
                    assert(_G.SetupReady == true, "Setup must run before spec requires.")
                    return function() it("uses setup", function() end) end
                ]],
                    ["B.spec.luau"] = [[
                    assert(_G.SetupReady == true, "Setup must run before spec requires.")
                    return function() it("also uses setup", function() end) end
                ]],
                    ["Setup.luau"] = [[
                    return function(framework, context)
                        assert(type(framework.runFiles) == "function")
                        assert(type(context.Root) == "string" and type(context.JobId) == "number")
                        assert(#context.Files > 0)
                        _G.SetupReady = true
                    end
                ]],
                },
                string.format(
                    [[
                Testable.configure({ Workers = %d, WorkerSetup = "Setup.luau" })
                const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau" }, fixtureRoot)
                assert(passed and results.successCount == 2)
            ]],
                    workers
                )
            )
        end
    end)

    it("should retain grouped spec state in one VM even when more workers are requested", function()
        run(
            {
                ["A.spec.luau"] = [[
                _G.GroupedState = { Value = 0 }
                return function()
                    it("sets the shared fixture", function() _G.GroupedState.Value = 42 end)
                end
            ]],
                ["B.spec.luau"] = [[
                const state = assert(_G.GroupedState)
                return function()
                    it("sees the shared fixture", function() assert(state.Value == 42) end)
                end
            ]],
            },
            [[
            Testable.configure({ Parallel = false, Workers = 4, WorkerGroups = { { "A.spec.luau", "B.spec.luau" } } })
            const results, passed = Testable.runFiles({ "B.spec.luau", "A.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 2, table.concat(results.errors, "\n"))
        ]]
        )
    end)

    it("should reject successful worker exits without a completion manifest and join waiting peers", function()
        run(
            {
                ["A.spec.luau"] = WAIT .. [[
                const process = require("@lune/process")
                return function()
                    it("exits early", function()
                        waitFor("peer-started")
                        process.exit(0)
                    end)
                end
            ]],
                ["B.spec.luau"] = WAIT .. [[
                return function()
                    it("waits until terminated", function()
                        fs.writeFile(_G.WorkerRoot .. "/peer-started", "")
                        while true do task.wait() end
                    end)
                end
            ]],
                ["C.spec.luau"] = 'return function() it("still usable", function() end) end',
                ["Setup.luau"] = SETUP,
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const ok, problem = pcall(Testable.runFiles, { "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "WorkerFailure")
            assert(tostring(problem):find("completion manifest", 1, true))
            const results, passed = Testable.runFiles({ "C.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 1)
        ]]
        )
    end)

    it("should observe a later worker failure while an earlier worker is still running", function()
        run(
            {
                ["A.spec.luau"] = WAIT .. [[
                return function()
                    it("waits until terminated", function()
                        fs.writeFile(_G.WorkerRoot .. "/peer-started", "")
                        while true do task.wait() end
                    end)
                end
            ]],
                ["B.spec.luau"] = WAIT .. [[
                const process = require("@lune/process")
                return function()
                    it("exits later in job order", function()
                        waitFor("peer-started")
                        process.exit(0)
                    end)
                end
            ]],
                ["Setup.luau"] = SETUP,
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const code, results = Testable.runFilesToExitCode({ "A.spec.luau", "B.spec.luau" }, nil, fixtureRoot)
            assert(code == 2 and results == nil)
        ]]
        )
    end)

    it("should observe planning exits without waiting for an earlier unfinished plan", function()
        run(
            {
                ["A.spec.luau"] = WAIT .. [[
                fs.writeFile(_G.WorkerRoot .. "/planning-started", "")
                while true do task.wait() end
            ]],
                ["B.spec.luau"] = WAIT .. [[
                const process = require("@lune/process")
                waitFor("planning-started")
                process.exit(0)
            ]],
                ["Setup.luau"] = SETUP,
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const ok, problem = pcall(Testable.runFiles, { "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "WorkerFailure")
        ]]
        )
    end)

    it("should claim shared snapshot paths before writes and preserve grouped snapshot ownership", function()
        run(
            {
                ["A.spec.luau"] = 'return require("./Shared")',
                ["B.spec.luau"] = 'return require("./Shared")',
                ["Shared.luau"] = [[
                return function()
                    it("snapshots", function() expect({ Value = 1 }).to.matchSnapshot() end)
                end
            ]],
            },
            [[
            const files = { "A.spec.luau", "B.spec.luau" }
            const snapshotPath = Testable.Snapshots.SnapshotLogic.pathFromSource(fixtureRoot .. "/Shared.luau")
            Testable.configure({ UpdateSnapshots = true })
            const ok, problem = pcall(Testable.runFiles, files, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "InvalidConfiguration")
            assert(not fs.isFile(snapshotPath))
            Testable.configure({ WorkerGroups = { files } })
            const written, passed = Testable.runFiles(files, fixtureRoot)
            assert(passed and written.snapshotSummary.Written == 2)
            const format = Testable.Snapshots.SnapshotFormat
            const entries = assert(format.parse(fs.readFile(snapshotPath)))
            const obsoleteKey = format.makeKey("old case", "1")
            entries[obsoleteKey] = "old value"
            fs.writeFile(snapshotPath, format.render(entries))
            const matched, againPassed = Testable.runFiles(files, fixtureRoot)
            assert(againPassed and matched.snapshotSummary.Matched == 2 and matched.snapshotSummary.Removed == 1)
            const remaining = assert(format.parse(fs.readFile(snapshotPath)))
            assert(remaining[obsoleteKey] == nil)
            local count = 0
            for _ in pairs(remaining) do count += 1 end
            assert(count == 2)
        ]]
        )
    end)

    it("should reject undeclared nested default snapshot paths before storage access", function()
        run(
            {
                ["A.spec.luau"] = [[
                const other = require("./Other")
                return function()
                    it("contains a nested run", function()
                        const results, passed = _G.Framework.run({ { Name = "Other", Func = other } })
                        assert(not passed and table.concat(results.errors):find("was not assigned", 1, true))
                    end)
                end
            ]],
                ["B.spec.luau"] = 'return function() it("passes", function() end) end',
                ["Other.luau"] = 'return function() it("snapshots", function() expect(1).to.matchSnapshot() end) end',
                ["Setup.luau"] = [[
                return function(framework)
                    _G.Framework = framework
                end
            ]],
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 2, table.concat(results.errors, "\n"))
            const path = Testable.Snapshots.SnapshotLogic.pathFromSource(fixtureRoot .. "/Other.luau")
            assert(not fs.isFile(path))
        ]]
        )
    end)

    it("should retain parent-owned snapshot stores locally and reject transferring their closures", function()
        run(
            {
                ["A.spec.luau"] = 'return function() it("snapshots", function() expect(1).to.matchSnapshot() end) end',
            },
            [[
            const store = Testable.Snapshots.MemorySnapshotStore.new()
            Testable.configure({ SnapshotStore = store })
            const ok, problem = pcall(Testable.runFiles, { "A.spec.luau" }, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "InvalidConfiguration")
            assert(next(store.Files) == nil)
            Testable.configure({ Workers = 1 })
            const results, passed = Testable.runFiles({ "A.spec.luau" }, fixtureRoot)
            assert(passed and results.snapshotSummary.Written == 1)
            assert(next(store.Files) ~= nil)
        ]]
        )
    end)

    it("should merge real worker coverage layouts and retain zero-hit unrequired sources", function()
        run(
            {
                ["A.spec.luau"] = [[
                const choose = require("./Source/Choose")
                return function() it("takes true", function() assert(choose(true) == 1) end) end
            ]],
                ["B.spec.luau"] = [[
                const choose = require("./Source/Choose")
                return function() it("takes false", function() assert(choose(false) == 2) end) end
            ]],
                ["Source/Choose.luau"] = [[
                return function(value)
                    if value then
                        return 1
                    else
                        return 2
                    end
                end
            ]],
                ["Source/Unrequired.luau"] = [[
                error("This eligible source must never be required by coverage collection.")
                return 3
            ]],
            },
            [[
            if not debug.iscoverageenabled() then return end
            const Coordinator = require("./Source/Testable/Workers/Coordinator")
            const files = { "A.spec.luau", "B.spec.luau" }
            const options = {
                Config = {
                    Coverage = true,
                    CoverageRoots = fixtureRoot .. "/Source",
                    ForbidFocus = false,
                    Parallel = false,
                    Reporters = {},
                    SuiteOrder = {},
                },
                Groups = {},
                Workers = 1,
            }
            const single = Coordinator.run(files, fixtureRoot, options, false)
            options.Workers = 2
            const parallel = Coordinator.run(files, fixtureRoot, options, false)
            const first = Testable.Coverage.collectRaw(single.RawCoverage)
            const second = Testable.Coverage.collectRaw(parallel.RawCoverage)
            assert(first.TotalExecutableLines == second.TotalExecutableLines)
            assert(first.TotalHitLines == second.TotalHitLines)
            assert(#second.Files == 2 and second.TotalPercentage < 100)
            local unloaded = false
            for _, file in parallel.RawCoverage.Files do
                if file.Name == "Unrequired" then
                    unloaded = true
                    assert(not file.Loaded)
                end
            end
            assert(unloaded)
            Testable.configure({ Coverage = true, CoverageRoots = fixtureRoot .. "/Source", CoverageThreshold = 100 })
            const results, passed = Testable.runFiles(files, fixtureRoot)
            assert(not passed and results.failureCount == 0 and results.successCount == 2)
        ]]
        )
    end)

    it("should collect overlapping coverage roots once in local and worker execution", function()
        run(
            {
                ["A.spec.luau"] = [[
                const value = require("./Source/Value")
                return function() it("calls value", function() assert(value() == 1) end) end
            ]],
                ["B.spec.luau"] = [[
                const value = require("./Source/Value")
                return function() it("also calls value", function() assert(value() == 1) end) end
            ]],
                ["Source/Value.luau"] = "return function() return 1 end",
            },
            [[
            if not debug.iscoverageenabled() then return end
            for _, workers in { 1, 2 } do
                const output = fixtureRoot .. "/coverage-" .. workers .. ".lcov"
                Testable.configure({
                    Coverage = true,
                    CoverageRoots = { All = fixtureRoot .. "/Source", One = fixtureRoot .. "/Source/Value.luau" },
                    CoverageThreshold = 100,
                    ReporterOutputs = { Lcov = output },
                    Reporters = { "Lcov" },
                    Workers = workers,
                })
                const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau" }, fixtureRoot)
                assert(passed and results.successCount == 2)
                const _, records = fs.readFile(output):gsub("end_of_record", "")
                assert(records == 1, "Overlapping roots must produce exactly one source record.")
            end
        ]]
        )
    end)

    it("should construct userdata coverage roots inside setup instead of transporting parent references", function()
        run(
            {
                ["A.spec.luau"] = [[
                const value = require("./Source/Value")
                return function() it("calls value", function() assert(value() == 1) end) end
            ]],
                ["B.spec.luau"] = [[
                const value = require("./Source/Value")
                return function() it("also calls value", function() assert(value() == 1) end) end
            ]],
                ["Source/Value.luau"] = "return function() return 1 end",
                ["Setup.luau"] = [[
                const roots = script.Parent.Source
                return function(framework)
                    framework.configure({ CoverageRoots = roots })
                end
            ]],
            },
            [[
            if not debug.iscoverageenabled() then return end
            Testable.configure({ CoverageRoots = script.Parent })
            const ok, problem = pcall(Testable.runFiles, { "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "InvalidConfiguration")
            Testable.resetConfig()
            Testable.configure({ Coverage = true, CoverageThreshold = 100, Reporters = {}, Workers = 2, WorkerSetup = "Setup.luau" })
            const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(passed and results.successCount == 2)
        ]]
        )
    end)

    it("should preserve explicitly independent worker-local snapshot stores created by setup", function()
        run(
            {
                ["A.spec.luau"] = 'return require("./Shared")',
                ["B.spec.luau"] = 'return require("./Shared")',
                ["Shared.luau"] = 'return function() it("snapshots", function() expect(1).to.matchSnapshot() end) end',
                ["Setup.luau"] = [[
                const fs = require("@lune/fs")
                return function(framework, context)
                    const store = framework.Snapshots.MemorySnapshotStore.new()
                    const write = store.write
                    store.write = function(path, contents)
                        write(path, contents)
                        fs.writeFile(context.Root .. "/store-" .. context.JobId, contents)
                    end
                    framework.configure({ SnapshotStore = store })
                end
            ]],
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const results, passed = Testable.runFiles({ "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(passed and results.snapshotSummary.Written == 2)
            assert(fs.isFile(fixtureRoot .. "/store-1") and fs.isFile(fixtureRoot .. "/store-2"))
            local counts = 0
            for index = 1, 2 do
                const entries = assert(Testable.Snapshots.SnapshotFormat.parse(fs.readFile(fixtureRoot .. "/store-" .. index)))
                for _ in pairs(entries) do counts += 1 end
            end
            assert(counts == 2)
        ]]
        )
    end)

    it("should preserve tool-error identity and kind across worker setup failures", function()
        run(
            {
                ["A.spec.luau"] = 'return function() it("must not execute", function() error("unreachable") end) end',
                ["Setup.luau"] = [[
                return function(framework)
                    framework.configure({ Workers = 0 })
                end
            ]],
            },
            [[
            for _, workers in { 1, 2 } do
                Testable.configure({ Workers = workers, WorkerSetup = "Setup.luau" })
                const ok, problem = pcall(Testable.runFiles, { "A.spec.luau" }, fixtureRoot)
                assert(not ok and Testable.ToolError.is(problem))
                assert(problem.Kind == "InvalidConfiguration", tostring(problem.Kind))
                assert(problem.Message:find("Workers", 1, true))
            end
        ]]
        )
    end)

    it("should preserve tool errors raised after the planning barrier", function()
        run(
            {
                ["A.spec.luau"] = 'return function() it("passes", function() end) end',
                ["Setup.luau"] = [[
                return function(framework)
                    framework.TestRunner.runPlan = function()
                        error(framework.ToolError.new(framework.ToolError.Kind.EmptyCoverage, "No source was measured."), 0)
                    end
                end
            ]],
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const ok, problem = pcall(Testable.runFiles, { "A.spec.luau" }, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "EmptyCoverage")
            assert(problem.Message == "No source was measured.")
        ]]
        )
    end)

    it("should reject malformed worker manifests rather than emit a passing verdict", function()
        run(
            {
                ["A.spec.luau"] = 'return function() it("passes", function() end) end',
                ["B.spec.luau"] = 'return function() it("also passes", function() end) end',
                ["Setup.luau"] = [[
                const protocol = require("../Source/Testable/Workers/Protocol")
                return function()
                    protocol.makeManifest = function()
                        return { Version = 1, RunId = "wrong run", JobId = 1, Assigned = {}, Completed = {} }
                    end
                end
            ]],
            },
            [[
            Testable.configure({ WorkerSetup = "Setup.luau" })
            const ok, problem = pcall(Testable.runFiles, { "A.spec.luau", "B.spec.luau" }, fixtureRoot)
            assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "WorkerFailure")
            assert(tostring(problem):find("manifest", 1, true) or tostring(problem):find("Manifest", 1, true))
        ]]
        )
    end)

    it("should reject malformed file arrays before requiring any spec", function()
        run(
            {
                ["A.spec.luau"] = [[
                const fs = require("@lune/fs")
                fs.writeFile(script.Parent .. "/required", "")
                return function() it("passes", function() end) end
            ]],
            },
            [[
            for _, workers in { 1, 2 } do
                Testable.configure({ Workers = workers })
                for _, files in {
                    {},
                    { [2] = "A.spec.luau", [3] = "A.spec.luau", [4] = "A.spec.luau", [6] = "A.spec.luau" },
                    { "A.spec.luau", "./A.spec.luau" },
                    { "A.spec.luau", false },
                } do
                    assert(not pcall(Testable.runFiles, files, fixtureRoot))
                    assert(not fs.isFile(fixtureRoot .. "/required"))
                end
            end
        ]]
        )
    end)

    it("should keep machine-readable stdout separate from worker planning and test output", function()
        const output, errors = run(
            {
                ["A.spec.luau"] = [[
                print("worker require output")
                return function()
                    print("worker planning output")
                    it("prints", function() print("worker test output") end)
                end
            ]],
                ["B.spec.luau"] = 'return function() it("passes", function() end) end',
            },
            [[
            Testable.configure({ Reporters = { "Json" } })
            const code, results = Testable.runFilesToExitCode({ "A.spec.luau", "B.spec.luau" }, nil, fixtureRoot)
            assert(code == 0 and results.successCount == 2)
        ]]
        )
        const serde = require("@lune/serde")
        expect(serde.decode("json", output).Totals.Passed).to.equal(2)
        for _, message in { "worker require output", "worker planning output", "worker test output" } do
            expect(errors:find(message, 1, true) ~= nil).to.equal(true)
        end
    end)
end
