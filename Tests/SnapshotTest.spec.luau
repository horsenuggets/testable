--[[

SnapshotTest.spec

Tests for snapshot testing. Covers the pure pieces (serializer, file format, diff,
decisions, and summary), the manager against in-memory and yielding stores, and the
matchSnapshot matcher end to end through subprocesses and through this spec's own
snapshot file.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const process = require("@lune/process")
const task = require("@lune/task")

const MemorySnapshotStore = Testable.Snapshots.MemorySnapshotStore
const SnapshotDiff = Testable.Snapshots.SnapshotDiff
const SnapshotFormat = Testable.Snapshots.SnapshotFormat
const SnapshotLogic = Testable.Snapshots.SnapshotLogic
const SnapshotManager = Testable.Snapshots.SnapshotManager
const SnapshotSerializer = Testable.Snapshots.SnapshotSerializer
const SnapshotSummary = Testable.Snapshots.SnapshotSummary
const TestEnum = Testable.TestEnum
const serialize = SnapshotSerializer.serialize
const SPEC_PATH = "__snapshots__/Spec.snap"

-- Builds a plan node for a test named "test" (or the given name) inside a spec named
-- "Spec". These nodes have no spec function, so their snapshot file is SPEC_PATH.
const function testNode(name: string?): any
    return { parent = { phrase = "Spec" }, phrase = name or "test", type = TestEnum.NodeType.It }
end

-- Builds the part of a results tree that the manager reads when it finishes a run.
const function resultsOf(nodes: { any }): any
    return {
        visitAllNodes = function(_self: any, callback: (any) -> ())
            for _, node in nodes do
                callback(node)
            end
        end,
    }
end

-- Runs a script that prints "RESULT" lines in a separate process and returns its
-- output.
const function runScript(body: string): string
    const prelude = [[
        const Testable = require("./Source/Testable")
        const store = Testable.Snapshots.MemorySnapshotStore.new()
        const function run(func, options)
            Testable.resetConfig()
            Testable.configure({ SnapshotStore = store, UpdateSnapshots = options ~= nil and options.Update == true })
            const results, passed = Testable.run({
                { Name = "Spec", Func = func, SnapshotPath = "Spec.snap" },
            })
            return results, passed
        end
    ]]
    const _, output = Subprocess.runScript(`{prelude}\n{body}`)
    return output
end

return function()
    describe("serializer", function()
        it("should serialize scalars", function()
            expect(serialize(nil)).to.equal("nil")
            expect(serialize(true)).to.equal("true")
            expect(serialize(false)).to.equal("false")
            expect(serialize(5)).to.equal("5")
            expect(serialize(-0.5)).to.equal("-0.5")
            expect(serialize(0.1)).to.equal("0.1")
            expect(serialize(math.huge)).to.equal("inf")
            expect(serialize(-math.huge)).to.equal("-inf")
            expect(serialize(0 / 0)).to.equal("nan")
            expect(serialize(-(0 / 0))).to.equal("nan")
            expect(serialize("hello")).to.equal('"hello"')
        end)

        it("should keep line breaks and quotation marks in a top-level string", function()
            expect(serialize('Summary\n\n  passed "2"')).to.equal('"Summary\n\n  passed "2""')
            expect(serialize("a\\b\tc\rd\0")).to.equal('"a\\\\b\\tc\\rd\\000"')
        end)

        it("should keep a nested string on one line", function()
            expect(serialize({ 'a\n"b"' })).to.equal('{\n    "a\\n\\"b\\"",\n}')
        end)

        it("should sort keys and write the array part positionally", function()
            const value = { "first", "second", Zeta = 1, Alpha = 2, [10] = "sparse", [true] = "yes", ["two words"] = 3 }
            expect(serialize(value)).to.equal(table.concat({
                "{",
                '    "first",',
                '    "second",',
                '    [10] = "sparse",',
                "    Alpha = 2,",
                "    Zeta = 1,",
                '    ["two words"] = 3,',
                '    [true] = "yes",',
                "}",
            }, "\n"))
        end)

        it("should give the same text regardless of insertion order", function()
            const forward = {}
            const backward = {}
            for index = 1, 50 do
                forward[`Key{index}`] = index
                backward[`Key{51 - index}`] = 51 - index
            end
            expect(serialize(forward)).to.equal(serialize(backward))
            expect(serialize(forward)).to.equal(serialize(forward))
        end)

        it("should serialize empty and nested tables", function()
            expect(serialize({})).to.equal("{}")
            expect(serialize({ Inner = { List = { 1 }, Empty = {} } })).to.equal(table.concat({
                "{",
                "    Inner = {",
                "        Empty = {},",
                "        List = {",
                "            1,",
                "        },",
                "    },",
                "}",
            }, "\n"))
        end)

        it("should have no depth cap", function()
            const function nest(depth: number, leaf: string): any
                local value: any = leaf
                for _ = 1, depth do
                    value = { Child = value }
                end
                return value
            end
            const deep = serialize(nest(200, "leaf"))
            expect(deep:find('"leaf"', 1, true)).to.be.ok()
            expect(deep).never.to.equal(serialize(nest(200, "other")))
        end)

        it("should write functions, threads, and userdata as their type name", function()
            const value = {
                Buffer = buffer.create(1),
                Function = function() end,
                Thread = coroutine.create(function() end),
                Userdata = newproxy(false),
            }
            expect(serialize(value)).to.equal(table.concat({
                "{",
                "    Buffer = <buffer>,",
                "    Function = <function>,",
                "    Thread = <thread>,",
                "    Userdata = <userdata>,",
                "}",
            }, "\n"))
            expect(serialize(print)).to.equal("<function>")
        end)

        it("should tell different values apart", function()
            const values: { any } =
                { 5, "5", {}, "{}", { "a" }, { [2] = "a" }, "nil", false, "a\nb", "a\\nb", { "a\nb" } }
            const seen = {}
            for _, value in values do
                const text = serialize(value)
                expect(seen[text]).to.equal(nil)
                seen[text] = true
            end
            expect(serialize(nil)).never.to.equal(serialize("nil"))
        end)

        it("should reject a cyclic value", function()
            const value: any = { Inner = {} }
            value.Inner.Back = value
            expect(function()
                serialize(value)
            end).to.throw('Cannot serialize a cyclic value at "value.Inner.Back".')
        end)

        it("should accept a table that is shared without a cycle", function()
            const shared = { 1 }
            expect(serialize({ shared, shared })).to.equal("{\n    {\n        1,\n    },\n    {\n        1,\n    },\n}")
        end)

        it("should reject keys that are not scalars", function()
            const keys: { any } = { {}, function() end, newproxy(false), coroutine.create(function() end) }
            for _, key in keys do
                expect(function()
                    serialize({ List = { [key] = true } })
                end).to.throw(`Cannot serialize a table with a {type(key)} key at "value.List"`)
            end
        end)
    end)

    describe("file format", function()
        it("should build test names and keys", function()
            const name = SnapshotFormat.makeTestName({ "Spec", "group", "renders" })
            expect(name).to.equal("Spec > group > renders")
            expect(SnapshotFormat.makeKey(name, "1")).to.equal("Spec > group > renders 1")
            expect(SnapshotFormat.makeKey(name, "wide layout")).to.equal("Spec > group > renders wide layout")
        end)

        it("should render entries sorted by key with their values written literally", function()
            const text = SnapshotFormat.render({
                ["b test 1"] = '"two\nlines"',
                ["a test 1"] = "5",
            })
            expect(text).to.equal('testable snapshot v1\n\na test 1 1\n5\n\nb test 1 2\n"two\nlines"\n')
        end)

        it("should round trip awkward keys and values", function()
            const entries = {
                ["back\\slash and\nline break 1"] = "{}",
                ["looks like a header 3"] = "value 2\n\ntestable snapshot v1\n\nfake key 1",
                ["plain 1"] = '""',
                ["trailing blank lines 1"] = '"a\n\n"',
            }
            const text = SnapshotFormat.render(entries)
            const parsed = SnapshotFormat.parse(text) :: { [string]: string }
            local count = 0
            for key, value in parsed do
                count += 1
                expect(value).to.equal(entries[key])
            end
            expect(count).to.equal(4)
            expect(SnapshotFormat.render(parsed)).to.equal(text)
            expect(text:find("back\\\\slash and\\nline break 1 1", 1, true)).to.be.ok()
        end)

        it("should parse a file with Windows line endings", function()
            const parsed =
                SnapshotFormat.parse('testable snapshot v1\r\n\r\na 1 2\r\n"x\r\ny"\r\n') :: { [string]: string }
            expect(parsed["a 1"]).to.equal('"x\ny"')
        end)

        it("should parse a file with no entries", function()
            const parsed = SnapshotFormat.parse("testable snapshot v1\n")
            expect(parsed).to.be.ok()
            expect(next(parsed :: any)).to.equal(nil)
        end)

        it("should reject invalid files", function()
            const cases = {
                { Contents = "", Message = "The first line must be" },
                { Contents = "something else\n\na 1 1\n5\n", Message = "The first line must be" },
                {
                    Contents = "testable snapshot v1\n\nno count here\n5\n",
                    Message = "Line 3 is not a valid entry header.",
                },
                { Contents = "testable snapshot v1\n\na 1 0\n", Message = "Line 3 is not a valid entry header." },
                { Contents = "testable snapshot v1\n\na 1 5\n5\n", Message = "fewer lines than its header says" },
                { Contents = "testable snapshot v1\n\na 1 1\n5\n\na 1 1\n6\n", Message = "repeats an earlier key" },
            }
            for _, case in cases do
                const parsed, message = SnapshotFormat.parse(case.Contents)
                expect(parsed).to.equal(nil)
                expect((message :: string):find(case.Message, 1, true)).to.be.ok()
            end
        end)
    end)

    describe("diff", function()
        it("should return nothing for equal texts", function()
            expect(#SnapshotDiff.lines("a\nb", "a\nb")).to.equal(0)
        end)

        it("should mark removed and added lines", function()
            const lines = SnapshotDiff.lines('{\n    Status = "ok",\n}', '{\n    Status = "down",\n}')
            expect(table.concat(lines, "\n")).to.equal('  {\n-     Status = "ok",\n+     Status = "down",\n  }')
        end)

        it("should keep unchanged lines between separate changes", function()
            const lines = SnapshotDiff.lines("a\nb\nc\nd", "a\nB\nc\nD\ne")
            expect(table.concat(lines, "\n")).to.equal("  a\n- b\n+ B\n  c\n- d\n+ D\n+ e")
        end)

        it("should handle a text that only grows or shrinks", function()
            expect(table.concat(SnapshotDiff.lines("a", "a\nb"), "\n")).to.equal("  a\n+ b")
            expect(table.concat(SnapshotDiff.lines("a\nb", "b"), "\n")).to.equal("- a\n  b")
        end)

        it("should collapse unchanged lines that are far from a change", function()
            const before = {}
            for index = 1, 20 do
                table.insert(before, `line {index}`)
            end
            const after = table.clone(before)
            after[10] = "changed"
            const lines = SnapshotDiff.lines(table.concat(before, "\n"), table.concat(after, "\n"))
            expect(table.concat(lines, "\n")).to.equal(table.concat({
                "  ...",
                "  line 7",
                "  line 8",
                "  line 9",
                "- line 10",
                "+ changed",
                "  line 11",
                "  line 12",
                "  line 13",
                "  ...",
            }, "\n"))
        end)
    end)

    describe("decisions", function()
        it("should decide every combination of stored value and update mode", function()
            const storedCases: { { Stored: string?, Name: string } } = {
                { Name = "missing", Stored = nil },
                { Name = "equal", Stored = "5" },
                { Name = "different", Stored = "6" },
            }
            const expected = {
                ["missing false"] = "Write",
                ["missing true"] = "Write",
                ["equal false"] = "Match",
                ["equal true"] = "Match",
                ["different false"] = "Mismatch",
                ["different true"] = "Update",
            }
            for _, case in storedCases do
                for _, isUpdating in { false, true } do
                    const decision = SnapshotLogic.decide(case.Stored, "5", isUpdating)
                    expect(decision).to.equal(expected[`{case.Name} {isUpdating}`])
                    expect(SnapshotLogic.decide(case.Stored, "5", isUpdating)).to.equal(decision)
                end
            end
        end)

        it("should find stored keys that no test produced", function()
            const entries = { ["c 1"] = "1", ["a 1"] = "1", ["b 1"] = "1" }
            const obsolete = SnapshotLogic.findObsolete(entries, { ["b 1"] = true, ["new 1"] = true })
            expect(table.concat(obsolete, ",")).to.equal("a 1,c 1")
            expect(#SnapshotLogic.findObsolete(entries, { ["a 1"] = true, ["b 1"] = true, ["c 1"] = true })).to.equal(0)
            expect(#SnapshotLogic.findObsolete({}, {})).to.equal(0)
        end)

        it("should place the snapshot file beside the spec file", function()
            expect(SnapshotLogic.pathFromSource("/project/Tests/Foo.spec.luau")).to.equal(
                "/project/Tests/__snapshots__/Foo.spec.luau.snap"
            )
            expect(SnapshotLogic.pathFromSource("C:\\project\\Tests\\Foo.spec.lua")).to.equal(
                "C:/project/Tests/__snapshots__/Foo.spec.lua.snap"
            )
            expect(SnapshotLogic.pathFromSource("Foo.spec.luau")).to.equal("__snapshots__/Foo.spec.luau.snap")
        end)

        it("should not treat a source that is not a file as a path", function()
            expect(SnapshotLogic.pathFromSource("ReplicatedStorage.Tests.Foo.spec")).to.equal(nil)
            expect(SnapshotLogic.pathFromSource('[string "chunk"]')).to.equal(nil)
            expect(SnapshotLogic.pathFromSource("")).to.equal(nil)
        end)

        it("should build a fallback path from the spec's names", function()
            expect(SnapshotLogic.pathFromNames({ "Tests", "Foo" })).to.equal("__snapshots__/Tests/Foo.snap")
        end)
    end)

    describe("summary", function()
        it("should print nothing when snapshots only matched", function()
            const summary = { Failed = 0, Matched = 5, Obsolete = {}, Removed = 0, Updated = 0, Written = 0 }
            expect(#SnapshotSummary.format(summary, "   ")).to.equal(0)
        end)

        it("should handle singular and plural counts", function()
            const one = {
                Failed = 0,
                Matched = 0,
                Obsolete = { { Key = "Spec > old 1", Path = "Spec.snap" } },
                Removed = 1,
                Updated = 1,
                Written = 1,
            }
            expect(table.concat(SnapshotSummary.format(one, "   "), "\n")).to.equal(table.concat({
                "1 snapshot written.",
                "1 snapshot updated.",
                "1 obsolete snapshot removed.",
                "1 obsolete snapshot found. Run again with snapshot updates enabled to remove it.",
                '   "Spec > old 1" in "Spec.snap"',
            }, "\n"))

            const many = {
                Failed = 0,
                Matched = 0,
                Obsolete = { { Key = "a 1", Path = "A.snap" }, { Key = "b 1", Path = "B.snap" } },
                Removed = 2,
                Updated = 3,
                Written = 4,
            }
            expect(table.concat(SnapshotSummary.format(many, ""), "\n")).to.equal(table.concat({
                "4 snapshots written.",
                "3 snapshots updated.",
                "2 obsolete snapshots removed.",
                "2 obsolete snapshots found. Run again with snapshot updates enabled to remove them.",
                '"a 1" in "A.snap"',
                '"b 1" in "B.snap"',
            }, "\n"))
        end)
    end)

    describe("manager", function()
        it("should write a new snapshot, then match it, then fail on a different value", function()
            const store = MemorySnapshotStore.new()

            const first = SnapshotManager.new({ Store = store })
            expect(first:Match(first:CreateScope(testNode()), { Status = "ok" })).to.equal(true)
            expect(store.Files[SPEC_PATH]).to.equal(nil)
            const firstSummary = first:Finish(nil, false)
            expect(firstSummary.Written).to.equal(1)
            expect(store.Files[SPEC_PATH]).to.equal(
                'testable snapshot v1\n\nSpec > test 1 3\n{\n    Status = "ok",\n}\n'
            )

            const second = SnapshotManager.new({ Store = store })
            expect(second:Match(second:CreateScope(testNode()), { Status = "ok" })).to.equal(true)
            const secondSummary = second:Finish(nil, false)
            expect(secondSummary.Matched).to.equal(1)
            expect(secondSummary.Written).to.equal(0)

            const third = SnapshotManager.new({ Store = store })
            const passed, message = third:Match(third:CreateScope(testNode()), { Status = "down" })
            expect(passed).to.equal(false)
            expect(message).to.equal(table.concat({
                'Snapshot "Spec > test 1" did not match.',
                "- Stored",
                "+ Received",
                "",
                "  {",
                '-     Status = "ok",',
                '+     Status = "down",',
                "  }",
                "",
                "If the change is intended, run again with snapshot updates enabled.",
            }, "\n"))
            expect(third:Finish(nil, false).Failed).to.equal(1)
            expect(store.Files[SPEC_PATH]:find('"ok"', 1, true)).to.be.ok()
        end)

        it("should overwrite a different value in update mode", function()
            const store = MemorySnapshotStore.new({ [SPEC_PATH] = "testable snapshot v1\n\nSpec > test 1 1\n1\n" })
            const manager = SnapshotManager.new({ Store = store, Update = true })
            expect(manager:Match(manager:CreateScope(testNode()), 2)).to.equal(true)
            const summary = manager:Finish(nil, false)
            expect(summary.Updated).to.equal(1)
            expect(summary.Written).to.equal(0)
            expect(store.Files[SPEC_PATH]).to.equal("testable snapshot v1\n\nSpec > test 1 1\n2\n")
        end)

        it("should not write a file when nothing changed", function()
            local writes = 0
            const files = { [SPEC_PATH] = "testable snapshot v1\n\nSpec > test 1 1\n1\n" }
            const store = MemorySnapshotStore.new(files)
            const countingStore = {
                read = store.read,
                write = function(path: string, contents: string)
                    writes += 1
                    store.write(path, contents)
                end,
            }
            for _, isUpdating in { false, true } do
                const manager = SnapshotManager.new({ Store = countingStore, Update = isUpdating })
                expect(manager:Match(manager:CreateScope(testNode()), 1)).to.equal(true)
                manager:Finish(nil, false)
            end
            expect(writes).to.equal(0)
        end)

        it("should number snapshots per test and let a hint replace the number", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })
            const scope = manager:CreateScope(testNode())
            const otherScope = manager:CreateScope(testNode("other"))
            manager:Match(scope, "a")
            manager:Match(scope, "b", "wide layout")
            manager:Match(scope, "c")
            manager:Match(otherScope, "d")
            manager:Finish(nil, false)

            const entries = SnapshotFormat.parse(store.Files[SPEC_PATH]) :: { [string]: string }
            expect(entries["Spec > test 1"]).to.equal('"a"')
            expect(entries["Spec > test wide layout"]).to.equal('"b"')
            expect(entries["Spec > test 2"]).to.equal('"c"')
            expect(entries["Spec > other 1"]).to.equal('"d"')
        end)

        it("should reject a hint that is not a non-empty string", function()
            const manager = SnapshotManager.new({ Store = MemorySnapshotStore.new() })
            const scope = manager:CreateScope(testNode())
            for _, hint in { "", 5, true } :: { any } do
                const passed, message = manager:Match(scope, "a", hint)
                expect(passed).to.equal(false)
                expect(message).to.equal("The snapshot hint must be a non-empty string.")
            end
        end)

        it("should fail when one key is checked twice with different values", function()
            const store = MemorySnapshotStore.new()
            for _, isUpdating in { false, true } do
                const manager = SnapshotManager.new({ Store = store, Update = isUpdating })
                const scope = manager:CreateScope(testNode())
                expect(manager:Match(scope, "a", "same")).to.equal(true)
                expect(manager:Match(scope, "a", "same")).to.equal(true)
                const passed, message = manager:Match(scope, "b", "same")
                expect(passed).to.equal(false)
                expect((message :: string):find("was already checked in this run", 1, true)).to.be.ok()
            end
        end)

        it("should fail when the value cannot be serialized", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })
            const cyclic: any = {}
            cyclic.Self = cyclic
            const passed, message = manager:Match(manager:CreateScope(testNode()), cyclic)
            expect(passed).to.equal(false)
            expect(message).to.equal(
                'The value could not be serialized for a snapshot. Cannot serialize a cyclic value at "value.Self".'
            )
            manager:Finish(nil, false)
            expect(store.Files[SPEC_PATH]).to.equal(nil)
        end)

        it("should fail clearly without a store or a filesystem", function()
            const manager = SnapshotManager.new({ HasFilesystem = false })
            const passed, message = manager:Match(manager:CreateScope(testNode()), 1)
            expect(passed).to.equal(false)
            expect((message :: string):find("Testable.configure({ SnapshotStore = store })", 1, true)).to.be.ok()
            expect(manager:Finish(nil, false).Written).to.equal(0)
        end)

        it("should fail on an invalid snapshot file and leave it alone", function()
            for _, isUpdating in { false, true } do
                const store = MemorySnapshotStore.new({ [SPEC_PATH] = "not a snapshot file" })
                const manager = SnapshotManager.new({ Store = store, Update = isUpdating })
                const passed, message = manager:Match(manager:CreateScope(testNode()), 1)
                expect(passed).to.equal(false)
                expect((message :: string):find(`Snapshot file "{SPEC_PATH}" is not valid.`, 1, true)).to.be.ok()
                manager:Finish(nil, false)
                expect(store.Files[SPEC_PATH]).to.equal("not a snapshot file")
            end
        end)

        it("should fail when the store cannot read", function()
            const manager = SnapshotManager.new({
                Store = {
                    read = function(): string?
                        error("disk on fire", 0)
                    end,
                    write = function() end,
                },
            })
            const passed, message = manager:Match(manager:CreateScope(testNode()), 1)
            expect(passed).to.equal(false)
            expect(message).to.equal(`Snapshot file "{SPEC_PATH}" could not be read. disk on fire`)
        end)

        it("should report obsolete snapshots without removing them", function()
            const contents = "testable snapshot v1\n\nSpec > gone 1 1\n1\n\nSpec > test 1 1\n1\n"
            const store = MemorySnapshotStore.new({ [SPEC_PATH] = contents })
            const manager = SnapshotManager.new({ Store = store })
            manager:Match(manager:CreateScope(testNode()), 1)
            const summary = manager:Finish(nil, false)
            expect(#summary.Obsolete).to.equal(1)
            expect(summary.Obsolete[1].Key).to.equal("Spec > gone 1")
            expect(summary.Obsolete[1].Path).to.equal(SPEC_PATH)
            expect(summary.Removed).to.equal(0)
            expect(store.Files[SPEC_PATH]).to.equal(contents)
        end)

        it("should remove obsolete snapshots in update mode", function()
            const store = MemorySnapshotStore.new({
                [SPEC_PATH] = "testable snapshot v1\n\nSpec > gone 1 1\n1\n\nSpec > test 1 1\n1\n",
            })
            const manager = SnapshotManager.new({ Store = store, Update = true })
            manager:Match(manager:CreateScope(testNode()), 1)
            const summary = manager:Finish(nil, false)
            expect(#summary.Obsolete).to.equal(0)
            expect(summary.Removed).to.equal(1)
            expect(store.Files[SPEC_PATH]).to.equal("testable snapshot v1\n\nSpec > test 1 1\n1\n")
        end)

        it("should skip obsolete detection in every kind of incomplete run", function()
            const contents = "testable snapshot v1\n\nSpec > gone 1 1\n1\n\nSpec > test 1 1\n1\n"
            const statuses = { TestEnum.TestStatus.Success, TestEnum.TestStatus.Failure, TestEnum.TestStatus.Skipped }
            for _, isUpdating in { false, true } do
                for _, isPartialRun in { false, true } do
                    for _, status in statuses do
                        const store = MemorySnapshotStore.new({ [SPEC_PATH] = contents })
                        const manager = SnapshotManager.new({ Store = store, Update = isUpdating })
                        manager:Match(manager:CreateScope(testNode()), 1)
                        const results = resultsOf({
                            { planNode = testNode(), status = TestEnum.TestStatus.Success },
                            { planNode = testNode("gone"), status = status },
                        })
                        const summary = manager:Finish(results, isPartialRun)
                        const isDetecting = not isPartialRun and status == TestEnum.TestStatus.Success
                        expect(#summary.Obsolete).to.equal(if isDetecting and not isUpdating then 1 else 0)
                        expect(summary.Removed).to.equal(if isDetecting and isUpdating then 1 else 0)
                        expect(store.Files[SPEC_PATH] == contents).to.equal(not (isDetecting and isUpdating))
                    end
                end
            end
        end)

        it("should only check files that produced a snapshot in the run", function()
            const untouched = "testable snapshot v1\n\nOther > gone 1 1\n1\n"
            const store = MemorySnapshotStore.new({ ["__snapshots__/Other.snap"] = untouched })
            const manager = SnapshotManager.new({ Store = store, Update = true })
            manager:Match(manager:CreateScope(testNode()), 1)
            const summary = manager:Finish(nil, false)
            expect(summary.Removed).to.equal(0)
            expect(store.Files["__snapshots__/Other.snap"]).to.equal(untouched)
        end)

        it("should share one copy of a file when concurrent tests use a yielding store", function()
            local reads = 0
            const store = MemorySnapshotStore.new({ [SPEC_PATH] = "testable snapshot v1\n\nSpec > test 1 1\n1\n" })
            const manager = SnapshotManager.new({
                Store = {
                    read = function(path: string): string?
                        reads += 1
                        task.wait()
                        return store.read(path)
                    end,
                    write = store.write,
                },
            })

            local finished = 0
            const outcomes = {}
            for index = 1, 8 do
                task.spawn(function()
                    const name = if index == 1 then "test" else `test {index}`
                    outcomes[index] = manager:Match(manager:CreateScope(testNode(name)), index)
                    finished += 1
                end)
            end
            while finished < 8 do
                task.wait()
            end

            const summary = manager:Finish(nil, false)
            for index = 1, 8 do
                expect(outcomes[index]).to.equal(true)
            end
            expect(reads).to.equal(8)
            expect(summary.Matched).to.equal(1)
            expect(summary.Written).to.equal(7)
            const entries = SnapshotFormat.parse(store.Files[SPEC_PATH]) :: { [string]: string }
            for index = 2, 8 do
                expect(entries[`Spec > test {index} 1`]).to.equal(tostring(index))
            end
            expect(entries["Spec > test 1"]).to.equal("1")
        end)

        it("should resolve the file from an explicit path, then the spec file, then names", function()
            const store = MemorySnapshotStore.new()
            const manager = SnapshotManager.new({ Store = store })
            const function specFunction() end

            const explicitPlan = { modulesByMethod = { [specFunction] = { snapshotPath = "custom/Explicit.snap" } } }
            const explicitSpec = { callback = specFunction, phrase = "Explicit", plan = explicitPlan }
            const explicitGroup =
                { callback = function() end, parent = explicitSpec, phrase = "group", plan = explicitPlan }
            manager:Match(manager:CreateScope({ parent = explicitGroup, phrase = "test", plan = explicitPlan }), 1)

            const sourcePlan = { modulesByMethod = { [specFunction] = {} } }
            const sourceSpec = { callback = specFunction, phrase = "FromSource", plan = sourcePlan }
            manager:Match(manager:CreateScope({ parent = sourceSpec, phrase = "test", plan = sourcePlan }), 1)

            manager:Match(manager:CreateScope(testNode()), 1)
            manager:Finish(nil, false)

            const source = debug.info(specFunction, "s"):gsub("\\", "/")
            const directory, fileName = source:match("^(.*/)([^/]+)$")
            expect(store.Files["custom/Explicit.snap"]).to.equal(
                "testable snapshot v1\n\nExplicit > group > test 1 1\n1\n"
            )
            expect(store.Files[`{directory}__snapshots__/{fileName}.snap`]).to.equal(
                "testable snapshot v1\n\nFromSource > test 1 1\n1\n"
            )
            expect(store.Files[SPEC_PATH]).to.be.ok()
        end)

        it("should show paths relative to the working directory for the filesystem store", function()
            const manager = SnapshotManager.new()
            const root = process.cwd:gsub("\\", "/"):gsub("/$", "")
            expect(manager:GetDisplayPath("elsewhere/Spec.snap")).to.equal("elsewhere/Spec.snap")
            manager:_getStore()
            expect(manager:GetDisplayPath(`{root}/Tests/__snapshots__/Spec.snap`)).to.equal(
                "Tests/__snapshots__/Spec.snap"
            )
            expect(manager:GetDisplayPath("/elsewhere/Spec.snap")).to.equal("/elsewhere/Spec.snap")
        end)
    end)

    describe("configuration", function()
        it("should set and reset the store and update flag", function()
            const store = MemorySnapshotStore.new()
            expect(Testable.Config.SnapshotStore).to.equal(nil)
            expect(Testable.Config.UpdateSnapshots).to.equal(false)
            Testable.configure({ SnapshotStore = store, UpdateSnapshots = true })
            expect(Testable.Config.SnapshotStore).to.equal(store)
            expect(Testable.Config.UpdateSnapshots).to.equal(true)
            Testable.resetConfig()
            expect(Testable.Config.SnapshotStore).to.equal(nil)
            expect(Testable.Config.UpdateSnapshots).to.equal(false)
        end)

        it("should reject an invalid store or update flag", function()
            expect(function()
                Testable.configure({ SnapshotStore = { read = function() end } :: any })
            end).to.throw("SnapshotStore must be a table with read and write functions")
            expect(function()
                Testable.configure({ UpdateSnapshots = "yes" :: any })
            end).to.throw("UpdateSnapshots must be a boolean")
            expect(function()
                Testable.TestBootstrap:getModules({ Name = "Spec", Func = function() end, SnapshotPath = 5 })
            end).to.throw("SnapshotPath must be a string or nil")
        end)
    end)

    describe("matcher", function()
        it("should match this spec's own snapshot file", function()
            expect({
                Framework = "testable",
                Lifecycle = { "write", "match", "mismatch", "update" },
                Rendered = SnapshotFormat.render({ ["Spec > test 1"] = serialize({ Status = "ok" }) }),
            }).to.matchSnapshot()
            expect("Summary\n\n  passed 2  failed 0").to.matchSnapshot("multi-line text")
            expect(1).to.matchSnapshot().to.equal(1)
        end)

        it("should work from hooks and tests that run concurrently", function()
            const output = runScript([[
                const function spec()
                    beforeEach(function()
                        expect("hook").to.matchSnapshot("from hook")
                    end)
                    describe("group", function()
                        for index = 1, 6 do
                            it(`test {index}`, function()
                                expect(index).to.matchSnapshot()
                                require("@lune/task").wait()
                                expect(index * 10).to.matchSnapshot()
                                expect(`text {index}`).to.matchSnapshot("label")
                            end)
                        end
                    end)
                    it("top", function()
                        expect({ 1 }).to.matchSnapshot()
                    end)
                end
                const _, passed = run(spec)
                print(`RESULT first {passed}`)
                print(store.Files["Spec.snap"])
                const _, passedAgain = run(spec)
                print(`RESULT second {passedAgain}`)
            ]])
            expect(output:find("RESULT first true", 1, true)).to.be.ok()
            expect(output:find("RESULT second true", 1, true)).to.be.ok()
            expect(output:find("26 snapshots written.", 1, true)).to.be.ok()
            for index = 1, 6 do
                expect(output:find(`\nSpec > group > test {index} 1 1\n{index}\n`, 1, true)).to.be.ok()
                expect(output:find(`\nSpec > group > test {index} 2 1\n{index * 10}\n`, 1, true)).to.be.ok()
                expect(output:find(`\nSpec > group > test {index} label 1\n"text {index}"\n`, 1, true)).to.be.ok()
                expect(output:find(`\nSpec > group > test {index} from hook 1\n"hook"\n`, 1, true)).to.be.ok()
            end
            expect(output:find("\nSpec > top 1 3\n{\n    1,\n}\n", 1, true)).to.be.ok()
            expect(output:find("\nSpec > top from hook 1\n", 1, true)).to.be.ok()
        end)

        it("should fail on a mismatch and accept it in update mode", function()
            const output = runScript([[
                local status = "ok"
                const function spec()
                    it("renders", function()
                        expect({ Status = status }).to.matchSnapshot()
                    end)
                end
                run(spec)
                status = "down"
                const results, passed = run(spec)
                print(`RESULT mismatch {passed} {results.failureCount}`)
                print(`RESULT kept {store.Files["Spec.snap"]:find('"ok"', 1, true) ~= nil}`)
                const _, updated = run(spec, { Update = true })
                print(`RESULT update {updated}`)
                print(`RESULT replaced {store.Files["Spec.snap"]:find('"down"', 1, true) ~= nil}`)
                const _, afterUpdate = run(spec)
                print(`RESULT after {afterUpdate}`)
            ]])
            expect(output:find("RESULT mismatch false 1", 1, true)).to.be.ok()
            expect(output:find("RESULT kept true", 1, true)).to.be.ok()
            expect(output:find('Snapshot "Spec > renders 1" did not match.', 1, true)).to.be.ok()
            expect(output:find('-     Status = "ok",\n+     Status = "down",', 1, true)).to.be.ok()
            expect(output:find("RESULT update true", 1, true)).to.be.ok()
            expect(output:find("1 snapshot updated.", 1, true)).to.be.ok()
            expect(output:find("RESULT replaced true", 1, true)).to.be.ok()
            expect(output:find("RESULT after true", 1, true)).to.be.ok()
        end)

        it("should report obsolete snapshots, skip them in focused runs, and prune on update", function()
            const output = runScript([[
                local mode = "all"
                const function spec()
                    it("stays", function()
                        expect(1).to.matchSnapshot()
                    end)
                    if mode == "all" then
                        it("goes away", function()
                            expect(2).to.matchSnapshot()
                        end)
                    elseif mode == "focused" then
                        itFOCUS("focused", function()
                            expect(3).to.matchSnapshot()
                        end)
                    elseif mode == "skipped" then
                        itSKIP("goes away", function()
                            expect(2).to.matchSnapshot()
                        end)
                    end
                end
                const function obsoleteCount(results)
                    return #results.snapshotSummary.Obsolete
                end
                run(spec)
                mode = "focused"
                const focused = run(spec, { Update = true })
                print(`RESULT focused {obsoleteCount(focused)} {focused.snapshotSummary.Removed}`)
                mode = "skipped"
                const skipped = run(spec, { Update = true })
                print(`RESULT skipped {obsoleteCount(skipped)} {skipped.snapshotSummary.Removed}`)
                mode = "removed"
                const reported, passed = run(spec)
                print(`RESULT reported {obsoleteCount(reported)} {passed}`)
                const pruned = run(spec, { Update = true })
                print(`RESULT pruned {obsoleteCount(pruned)} {pruned.snapshotSummary.Removed}`)
                print(store.Files["Spec.snap"])
            ]])
            expect(output:find("RESULT focused 0 0", 1, true)).to.be.ok()
            expect(output:find("RESULT skipped 0 0", 1, true)).to.be.ok()
            expect(output:find("RESULT reported 2 true", 1, true)).to.be.ok()
            expect(output:find("2 obsolete snapshots found.", 1, true)).to.be.ok()
            expect(output:find('"Spec > goes away 1" in "Spec.snap"', 1, true)).to.be.ok()
            expect(output:find("RESULT pruned 0 2", 1, true)).to.be.ok()
            expect(output:find("2 obsolete snapshots removed.", 1, true)).to.be.ok()
            expect(output:find("testable snapshot v1\n\nSpec > stays 1 1\n1\n\n", 1, true)).to.be.ok()
        end)

        it("should fail for unsupported uses", function()
            const output = runScript([[
                const function spec()
                    it("negated", function()
                        expect(1).never.to.matchSnapshot()
                    end)
                    it("cyclic", function()
                        const value = {}
                        value.Self = value
                        expect(value).to.matchSnapshot()
                    end)
                    it("table key", function()
                        expect({ [{}] = 1 }).to.matchSnapshot()
                    end)
                end
                const results = run(spec)
                print(`RESULT failures {results.failureCount}`)
                print(`RESULT files {next(store.Files) == nil}`)
                Testable.resetConfig()
                const planned = Testable.run({
                    {
                        Name = "Planning",
                        Func = function()
                            expect(1).to.matchSnapshot()
                        end,
                    },
                })
                print(`RESULT planning {planned.failureCount}`)
            ]])
            expect(output:find("RESULT failures 3", 1, true)).to.be.ok()
            expect(output:find("RESULT files true", 1, true)).to.be.ok()
            expect(output:find("matchSnapshot cannot be negated with never.", 1, true)).to.be.ok()
            expect(output:find('Cannot serialize a cyclic value at "value.Self".', 1, true)).to.be.ok()
            expect(output:find('Cannot serialize a table with a table key at "value"', 1, true)).to.be.ok()
            expect(output:find("RESULT planning 1", 1, true)).to.be.ok()
            expect(output:find("matchSnapshot can only be used while a test is running.", 1, true)).to.be.ok()
        end)

        it("should store snapshots beside the spec file on the filesystem", function()
            const directory = `_temp_snapshots_{os.time()}_{math.random(100000, 999999)}`
            const snapshotPath = `{directory}/__snapshots__/Sample.spec.luau.snap`
            fs.writeDir(directory)
            fs.writeFile(
                `{directory}/Sample.spec.luau`,
                [[
                    return function()
                        it("renders", function()
                            expect({ Status = _G.STATUS }).to.matchSnapshot()
                        end)
                    end
                ]]
            )

            const function run(status: string, flag: string): (boolean, string)
                return Subprocess.runScript(table.concat({
                    'const Testable = require("./Source/Testable")',
                    `_G.STATUS = "{status}"`,
                    `Testable.configure(\{ UpdateSnapshots = {flag} })`,
                    `const spec = require("./{directory}/Sample.spec")`,
                    'const _, passed = Testable.run({ { Name = "Sample", Func = spec } })',
                    'require("@lune/process").exit(if passed then 0 else 1)',
                }, "\n"))
            end

            const ok, problem = pcall(function()
                const firstPassed, firstOutput = run("ok", "false")
                expect(firstPassed).to.equal(true)
                expect(firstOutput:find("1 snapshot written.", 1, true)).to.be.ok()
                expect(fs.readFile(snapshotPath)).to.equal(
                    'testable snapshot v1\n\nSample > renders 1 3\n{\n    Status = "ok",\n}\n'
                )

                expect((run("ok", "false"))).to.equal(true)

                const mismatchPassed, mismatchOutput = run("down", "false")
                expect(mismatchPassed).to.equal(false)
                expect(mismatchOutput:find('Snapshot "Sample > renders 1" did not match.', 1, true)).to.be.ok()
                expect(fs.readFile(snapshotPath):find('"ok"', 1, true)).to.be.ok()

                const updatePassed, updateOutput = run("down", "true")
                expect(updatePassed).to.equal(true)
                expect(updateOutput:find("1 snapshot updated.", 1, true)).to.be.ok()
                expect(fs.readFile(snapshotPath):find('"down"', 1, true)).to.be.ok()
            end)

            fs.removeDir(directory)
            if not ok then
                error(problem, 0)
            end
        end)
    end)
end
