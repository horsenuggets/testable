--[[

SnapshotStateTest.spec

Tests that snapshot state never outlives the run it belongs to. Covers aborting a
manager, the guard that aborts it when the body of a run throws, a store whose writes
fail, and (in a subprocess, so the case gets its own Testable instance) whole runs that
abort and are followed by another run on the same store. Also covers the summary counts
that the machine-readable reports share.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const task = require("@lune/task")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const MemorySnapshotStore = Testable.Snapshots.MemorySnapshotStore
const SnapshotLogic = Testable.Snapshots.SnapshotLogic
const SnapshotManager = Testable.Snapshots.SnapshotManager
const SnapshotSummary = Testable.Snapshots.SnapshotSummary
const TestEnum = Testable.TestEnum
const ToolError = Testable.ToolError

const ABORTED_MESSAGE = "The snapshot could not be checked because the test run was aborted."
const ABORTED_RUN_SCRIPT = [[
    const Testable = require("./Source/Testable")
    const expect, it = Testable.expect, Testable.it

    const store = Testable.Snapshots.MemorySnapshotStore.new()
    local value = "from the aborted run"
    const tests = {
        {
            Name = "Spec",
            Func = function()
                it("renders", function()
                    expect(value).to.matchSnapshot()
                end)
            end,
            SnapshotPath = "Spec.snap",
        },
    }

    Testable.configure({ InjectGlobals = false, Parallel = %s, SnapshotStore = store })

    -- %s
    %s

    const aborted, problem = pcall(Testable.run, tests)
    print(`RESULT aborted {not aborted}`)
    print(`RESULT toolError {Testable.ToolError.is(problem)}`)
    print(`RESULT storedAfterAbort {store.Files["Spec.snap"] ~= nil}`)

    %s
    value = "from the later run"

    const results, passed = Testable.run(tests)
    print(`RESULT passed {passed}`)
    print(`RESULT written {results.snapshotSummary.Written}`)
    print(`RESULT failed {results.snapshotSummary.Failed}`)
    print(`RESULT keepsLater {string.find(store.Files["Spec.snap"], "from the later run", 1, true) ~= nil}`)
    print(`RESULT keepsAborted {string.find(store.Files["Spec.snap"], "from the aborted run", 1, true) ~= nil}`)
]]
-- Each case makes the first run throw a tool error at a different point and then undoes
-- it, so the second run is an ordinary one.
const ABORT_CASES = {
    {
        Break = [[
            const finalize = Testable.TestSession.finalize
            Testable.TestSession.finalize = function()
                error(Testable.ToolError.new(Testable.ToolError.Kind.EmptyFilter, "Aborted on purpose."), 0)
            end
        ]],
        Name = "while the results are finalized",
        Restore = "Testable.TestSession.finalize = finalize"
    },
    {
        Break = [[
            const write = store.write
            store.write = function()
                error(Testable.ToolError.new(Testable.ToolError.Kind.EmptyFilter, "Aborted on purpose."), 0)
            end
        ]],
        Name = "while the snapshots are written",
        Restore = "store.write = write"
    }
}
const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false }
}
const OTHER_PATH = SnapshotLogic.pathFromNames({ "Other" })
const SPEC_PATH = SnapshotLogic.pathFromNames({ "Spec" })

const function contains(text: string, part: string): boolean
    return string.find(text, part, 1, true) ~= nil
end

-- Builds a plan node for a test inside a spec with the given name. These nodes have no
-- spec function, so the snapshot file path is built from the spec's name.
const function testNode(name: string, spec: string?): any
    return { parent = { phrase = spec or "Spec" }, phrase = name, type = TestEnum.NodeType.It }
end

const function match(manager: any, name: string, value: any, spec: string?): (boolean, string?)
    return manager:Match(manager:CreateScope(testNode(name, spec)), value)
end

return function()
    describe("snapshot path ownership", function()
        it("should reject an unassigned path before reading or changing the store", function()
            local accessed = false
            const manager = SnapshotManager.new({
                PathGuard = function(path)
                    error(`The path "{path}" is not assigned.`)
                end,
                Store = {
                    read = function()
                        accessed = true
                        return nil
                    end,
                    write = function()
                        accessed = true
                    end
                }
            })
            const ok, problem = pcall(function()
                match(manager, "test", "value")
            end)
            expect(ok).to.equal(false)
            expect(contains(tostring(problem), "not assigned")).to.equal(true)
            expect(accessed).to.equal(false)
            manager:Abort()
            expect(accessed).to.equal(false)
        end)

        it("should check ownership when joining a file already held by another manager", function()
            const store = MemorySnapshotStore.new()
            const owner = SnapshotManager.new({ Store = store })
            expect(match(owner, "outer", "first")).to.equal(true)
            const visitor = SnapshotManager.new({
                PathGuard = function()
                    error("Another worker owns this file.")
                end,
                Store = store
            })
            expect(pcall(match, visitor, "nested", "second")).to.equal(false)
            visitor:Abort()
            const summary = owner:Finish(nil, false)
            expect(summary.Written).to.equal(1)
            expect(contains(store.Files[SPEC_PATH], "first")).to.equal(true)
            expect(contains(store.Files[SPEC_PATH], "second")).to.equal(false)
        end)

        it("should reject malformed ownership guards", function()
            expect(pcall(SnapshotManager.new, { PathGuard = false } :: any)).to.equal(false)
        end)
    end)

    describe("SnapshotManager.Abort", function()
        it("should drop what the run buffered so a later run starts from the store", function()
            const store = MemorySnapshotStore.new()
            const aborted = SnapshotManager.new({ Store = store })
            expect(match(aborted, "test", "from the aborted run")).to.equal(true)
            aborted:Abort()
            expect(next(store.Files)).to.equal(nil)

            -- A leaked file would make this a second check of the same key with a
            -- different value, which fails.
            const later = SnapshotManager.new({ Store = store })
            const passed, message = match(later, "test", "from the later run")
            expect(message).to.equal(nil)
            expect(passed).to.equal(true)

            const summary = later:Finish(nil, false)
            expect(summary.Written).to.equal(1)
            expect(summary.Failed).to.equal(0)
            expect(contains(store.Files[SPEC_PATH], "from the later run")).to.equal(true)
            expect(contains(store.Files[SPEC_PATH], "from the aborted run")).to.equal(false)
        end)

        it("should share a file with a run that is still unfinished when nothing was aborted", function()
            const store = MemorySnapshotStore.new()
            const unfinished = SnapshotManager.new({ Store = store })
            expect(match(unfinished, "test", "first value")).to.equal(true)

            const overlapping = SnapshotManager.new({ Store = store })
            const passed, message = match(overlapping, "test", "second value")
            expect(passed).to.equal(false)
            expect(contains(message :: string, "was already checked in this run with a different value")).to.equal(true)

            overlapping:Finish(nil, false)
            unfinished:Finish(nil, false)
        end)

        it("should leave a shared file to the other run and stop it from judging obsolete snapshots", function()
            const store = MemorySnapshotStore.new({
                [SPEC_PATH] = "testable snapshot v1\n\nSpec > gone 1 1\n1\n"
            })
            const outer = SnapshotManager.new({ Store = store })
            const nested = SnapshotManager.new({ Store = store })
            expect(match(outer, "outer", "a")).to.equal(true)
            expect(match(nested, "nested", "b")).to.equal(true)

            nested:Abort()
            expect(match(outer, "outer late", "c")).to.equal(true)

            const summary = outer:Finish(nil, false)
            expect(summary.Written).to.equal(2)
            expect(#summary.Obsolete).to.equal(0)
            expect(contains(store.Files[SPEC_PATH], "Spec > outer 1")).to.equal(true)
            expect(contains(store.Files[SPEC_PATH], "Spec > outer late 1")).to.equal(true)
            expect(contains(store.Files[SPEC_PATH], "Spec > gone 1")).to.equal(true)

            -- Both runs are done, so the file is closed and the next run judges every key.
            const later = SnapshotManager.new({ Store = store })
            expect(match(later, "outer", "a")).to.equal(true)
            expect(#later:Finish(nil, false).Obsolete).to.equal(3)
        end)

        it("should fail snapshot assertions that arrive after the abort without loading a file", function()
            local reads = 0
            const files = {}
            const store = {
                read = function(path: string): string?
                    reads += 1
                    return files[path]
                end,
                write = function(path: string, contents: string)
                    files[path] = contents
                end
            }
            const manager = SnapshotManager.new({ Store = store })
            manager:Abort()

            const passed, message = match(manager, "test", 1)
            expect(passed).to.equal(false)
            expect(message).to.equal(ABORTED_MESSAGE)
            expect(reads).to.equal(0)

            const summary = manager:Finish(nil, false)
            expect(summary.Written).to.equal(0)
            expect(next(files)).to.equal(nil)
        end)

        it("should not load a file whose read was still in flight when the run was aborted", function()
            const files = {}
            local reading = false
            const store = {
                read = function(path: string): string?
                    reading = true
                    task.wait(0.02)
                    return files[path]
                end,
                write = function(path: string, contents: string)
                    files[path] = contents
                end
            }
            const manager = SnapshotManager.new({ Store = store })

            local passed: boolean? = nil
            local message: string? = nil
            task.spawn(function()
                passed, message = match(manager, "test", "in flight")
            end)
            expect(reading).to.equal(true)
            manager:Abort()
            while passed == nil do
                task.wait()
            end

            expect(passed).to.equal(false)
            expect(message).to.equal(ABORTED_MESSAGE)

            const later = SnapshotManager.new({ Store = store })
            expect(match(later, "test", "from the later run")).to.equal(true)
            expect(later:Finish(nil, false).Written).to.equal(1)
            expect(contains(files[SPEC_PATH], "in flight")).to.equal(false)
        end)

        it("should do nothing after the run finished, when repeated, or without a store", function()
            const store = MemorySnapshotStore.new()
            const finished = SnapshotManager.new({ Store = store })
            expect(match(finished, "test", "kept")).to.equal(true)
            finished:Finish(nil, false)
            const contents = store.Files[SPEC_PATH]

            finished:Abort()
            finished:Abort()
            expect(store.Files[SPEC_PATH]).to.equal(contents)

            const later = SnapshotManager.new({ Store = store })
            expect(match(later, "test", "kept")).to.equal(true)
            expect(later:Finish(nil, false).Matched).to.equal(1)

            SnapshotManager.new({ HasFilesystem = false }):Abort()
        end)
    end)

    describe("SnapshotManager.Finish with a store that fails to write", function()
        it("should release every file, write the others, and throw the first failure", function()
            const files = {}
            local failing = true
            const store = {
                read = function(path: string): string?
                    return files[path]
                end,
                write = function(path: string, contents: string)
                    if failing and path == OTHER_PATH then
                        error("The disk is full.", 0)
                    end
                    files[path] = contents
                end
            }
            const manager = SnapshotManager.new({ Store = store })
            expect(match(manager, "test", "other, first run", "Other")).to.equal(true)
            expect(match(manager, "test", "spec, first run", "Spec")).to.equal(true)

            expect(function()
                manager:Finish(nil, false)
            end).to.throw("The disk is full.")
            expect(files[OTHER_PATH]).to.equal(nil)
            expect(contains(files[SPEC_PATH], "spec, first run")).to.equal(true)

            -- Finishing again has nothing left to release or write.
            failing = false
            manager:Finish(nil, false)
            expect(files[OTHER_PATH]).to.equal(nil)

            -- Both files were closed, so a later run reads them from the store again. A
            -- leaked copy of the first file would fail this as a repeated key.
            const later = SnapshotManager.new({ Store = store })
            expect(match(later, "test", "other, later run", "Other")).to.equal(true)
            const passed, message = match(later, "test", "spec, later run", "Spec")
            expect(passed).to.equal(false)
            expect(contains(message :: string, "did not match")).to.equal(true)

            const summary = later:Finish(nil, false)
            expect(summary.Written).to.equal(1)
            expect(summary.Failed).to.equal(1)
            expect(contains(files[OTHER_PATH], "other, later run")).to.equal(true)
        end)

        it("should keep a thrown tool error identifiable", function()
            const problem = ToolError.new(ToolError.Kind.EmptyFilter, "Thrown by the store.")
            const store = {
                read = function(): string?
                    return nil
                end,
                write = function()
                    error(problem, 0)
                end
            }
            const manager = SnapshotManager.new({ Store = store })
            expect(match(manager, "test", 1)).to.equal(true)

            const ok, thrown = pcall(function()
                manager:Finish(nil, false)
            end)
            expect(ok).to.equal(false)
            expect(thrown).to.equal(problem)
        end)

        it("should keep a file shared until it is written, so a yielding store loses nothing", function()
            const files = {}
            local writingOther = false
            const store = {
                read = function(path: string): string?
                    return files[path]
                end,
                write = function(path: string, contents: string)
                    if path == OTHER_PATH then
                        writingOther = true
                        task.wait(0.02)
                    end
                    files[path] = contents
                end
            }
            const first = SnapshotManager.new({ Store = store })
            expect(match(first, "test", "other, first run", "Other")).to.equal(true)
            expect(match(first, "first", "spec, first run", "Spec")).to.equal(true)

            -- The first run writes "Other" before "Spec", and its store yields while
            -- doing so. A second run adds a snapshot to "Spec" and finishes meanwhile.
            local finished = false
            task.spawn(function()
                first:Finish(nil, false)
                finished = true
            end)
            expect(writingOther).to.equal(true)

            const second = SnapshotManager.new({ Store = store })
            expect(match(second, "second", "spec, second run", "Spec")).to.equal(true)
            second:Finish(nil, false)

            while not finished do
                task.wait()
            end

            expect(contains(files[SPEC_PATH], "spec, first run")).to.equal(true)
            expect(contains(files[SPEC_PATH], "spec, second run")).to.equal(true)
        end)

        it("should not throw when every write succeeds", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })
            expect(match(manager, "test", 1, "Other")).to.equal(true)
            expect(match(manager, "test", 2, "Spec")).to.equal(true)

            expect(manager:Finish(nil, false).Written).to.equal(2)
            expect(store.Files[OTHER_PATH] ~= nil).to.equal(true)
            expect(store.Files[SPEC_PATH] ~= nil).to.equal(true)
        end)
    end)

    describe("SnapshotManager.RunGuarded", function()
        it("should return whatever the body returns and leave the run open", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })

            const first, second, third = manager:RunGuarded(function()
                task.wait()
                expect(match(manager, "test", "kept")).to.equal(true)
                return "results", nil, 3
            end)
            expect(first).to.equal("results")
            expect(second).to.equal(nil)
            expect(third).to.equal(3)

            -- The body did not throw, so the run goes on and finishes as usual.
            expect(match(manager, "second test", "also kept")).to.equal(true)
            expect(manager:Finish(nil, false).Written).to.equal(2)
            expect(contains(store.Files[SPEC_PATH], "also kept")).to.equal(true)
        end)

        it("should abort the run and throw the message again when the body throws", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })

            const ok, problem = pcall(function()
                manager:RunGuarded(function()
                    expect(match(manager, "test", "from the aborted run")).to.equal(true)
                    task.wait()
                    error("The runner broke.")
                end)
            end)
            expect(ok).to.equal(false)
            expect(type(problem)).to.equal("string")
            expect(contains(problem :: any, "The runner broke.")).to.equal(true)
            expect(next(store.Files)).to.equal(nil)

            const stragglerPassed, stragglerMessage = match(manager, "test", "from a straggler")
            expect(stragglerPassed).to.equal(false)
            expect(stragglerMessage).to.equal(ABORTED_MESSAGE)

            const later = SnapshotManager.new({ Store = store })
            expect(match(later, "test", "from the later run")).to.equal(true)
            expect(later:Finish(nil, false).Written).to.equal(1)
        end)

        it("should throw a tool error again as the same object", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })
            const thrown = ToolError.new(ToolError.Kind.EmptyCoverage, "Nothing measured.")

            const ok, problem = pcall(function()
                manager:RunGuarded(function()
                    expect(match(manager, "test", "from the aborted run")).to.equal(true)
                    error(thrown, 0)
                end)
            end)
            expect(ok).to.equal(false)
            expect(problem).to.equal(thrown)
            expect(ToolError.is(problem)).to.equal(true)

            const later = SnapshotManager.new({ Store = store })
            expect(match(later, "test", "from the later run")).to.equal(true)
            expect(later:Finish(nil, false).Written).to.equal(1)
        end)

        it("should reject a body that is not a function", function()
            expect(function()
                SnapshotManager.new({ HasFilesystem = false }):RunGuarded(nil :: any)
            end).to.throw("callback must be a function")
        end)
    end)

    for _, mode in EXECUTION_MODES do
        describe(`aborted runs with {mode.Name} execution`, function()
            for _, case in ABORT_CASES do
                it(`should not leak snapshots into a later run when a run aborts {case.Name}`, function()
                    const ok, output = Subprocess.runScript(
                        string.format(ABORTED_RUN_SCRIPT, tostring(mode.Parallel), case.Name, case.Break, case.Restore)
                    )

                    expect(ok).to.equal(true)
                    expect(contains(output, "RESULT aborted true")).to.equal(true)
                    expect(contains(output, "RESULT toolError true")).to.equal(true)
                    expect(contains(output, "RESULT storedAfterAbort false")).to.equal(true)
                    expect(contains(output, "RESULT passed true")).to.equal(true)
                    expect(contains(output, "RESULT written 1")).to.equal(true)
                    expect(contains(output, "RESULT failed 0")).to.equal(true)
                    expect(contains(output, "RESULT keepsLater true")).to.equal(true)
                    expect(contains(output, "RESULT keepsAborted false")).to.equal(true)
                end)
            end
        end)
    end

    describe("SnapshotSummary.counts", function()
        const function summaryOf(obsolete: number): any
            const entries = {}
            for index = 1, obsolete do
                table.insert(entries, { Key = `Spec > old {index}`, Path = "Spec.snap" })
            end
            return { Failed = 1, Matched = 2, Obsolete = entries, Removed = 3, Updated = 4, Written = 5 }
        end

        it("should name every count in a fixed order", function()
            const names = {}
            const values = {}
            for _, entry in SnapshotSummary.counts(summaryOf(6)) do
                table.insert(names, entry.Name)
                table.insert(values, entry.Value)
            end
            expect(table.concat(names, ",")).to.equal("Written,Updated,Removed,Obsolete,Matched,Failed")
            expect(table.concat(values, ",")).to.equal("5,4,3,6,2,1")
        end)

        it("should return equal counts when called twice", function()
            const first = SnapshotSummary.counts(summaryOf(2))
            const second = SnapshotSummary.counts(summaryOf(2))
            expect(#first).to.equal(#second)
            for index, entry in first do
                expect(entry.Name).to.equal(second[index].Name)
                expect(entry.Value).to.equal(second[index].Value)
            end
        end)

        it("should tell whether a run touched any snapshot for each count on its own", function()
            const untouched = { Failed = 0, Matched = 0, Obsolete = {}, Removed = 0, Updated = 0, Written = 0 }
            expect(SnapshotSummary.hasActivity(untouched)).to.equal(false)

            for _, name in { "Failed", "Matched", "Removed", "Updated", "Written" } do
                const summary = table.clone(untouched)
                summary[name] = 1
                expect(SnapshotSummary.hasActivity(summary)).to.equal(true)
            end

            const withObsolete = table.clone(untouched)
            withObsolete.Obsolete = { { Key = "Spec > old 1", Path = "Spec.snap" } }
            expect(SnapshotSummary.hasActivity(withObsolete)).to.equal(true)
        end)

        it("should reject a summary with a missing count", function()
            expect(function()
                SnapshotSummary.counts({ Obsolete = {} })
            end).to.throw("summary.Written must be a number")
            expect(function()
                SnapshotSummary.counts({ Written = 0 })
            end).to.throw("summary.Obsolete must be an array")
        end)
    end)
end
