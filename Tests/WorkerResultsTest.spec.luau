--[[

WorkerResultsTest.spec

Verifies coordinator aggregation against real plans, runner output, and protocol-owned
fixtures. Exact spec membership, global focus failures, report parity, snapshot ordering,
and independent ownership must survive out-of-order worker completion.

--]]

const JUnitReporter = require("../Source/Testable/Reporters/JUnitReporter")
const JsonReporter = require("../Source/Testable/Reporters/JsonReporter")
const Protocol = require("../Source/Testable/Workers/Protocol")
const Results = require("../Source/Testable/Workers/Results")
const TestEnum = require("../Source/Testable/TestEnum")
const TestFilter = require("../Source/Testable/TestFilter")
const TestPlan = require("../Source/Testable/TestPlan")
const TestResults = require("../Source/Testable/TestResults")
const TestSession = require("../Source/Testable/TestSession")
const Testable = require("../Source/Testable")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it
const TEXT_OPTIONS = { AlphabeticalSort = false, Color = false, Indent = "   ", PrintSkipped = true }

const function rejects(callback: () -> (), fragment: string?)
    const ok, message = pcall(callback)
    expect(ok).to.equal(false)
    if fragment ~= nil then
        expect(string.find(tostring(message), fragment, 1, true) ~= nil).to.equal(true)
    end
end

-- Build completed fixtures with the real session API, then cross the worker boundary.
const function shard(names: { string }): any
    const plan = TestPlan.new()
    const session = TestSession.new(plan)
    for _, name in ipairs(names) do
        const suite = plan:addChild(name, TestEnum.NodeType.Describe)
        suite.collected = true
        suite.specModule = { path = { name }, pathStringForSorting = name, snapshotPath = `Tests/{name}.spec.luau` }
        const test = suite:addChild("passes", TestEnum.NodeType.It)
        session:pushNode(suite)
        session:pushNode(test)
        session:setSuccess()
        session:popNode()
        session:setStatusFromChildren()
        session:popNode()
    end
    return Protocol.decodeResults(Protocol.encodeResults(session:finalize()))
end

-- Use identical, deterministic durations so separate runs can be compared byte-for-byte.
const function run(
    names: { string },
    methods: { [string]: () -> () },
    hasFocus: boolean?,
    forbidFocus: boolean?,
    filter: string?
): any
    const modules = {}
    for _, name in ipairs(names) do
        table.insert(modules, {
            method = methods[name],
            path = { name },
            pathStringForSorting = name,
            snapshotPath = `Tests/{name}.spec.luau`,
        })
    end
    const plan = Testable.TestPlanner.createPlan(modules, nil, nil, names)
    plan.forbidFocus = true
    TestFilter.apply(plan, filter)
    const results = Testable.TestRunner.runPlan(plan, { HasFocus = hasFocus, ForbidFocus = forbidFocus == true })
    results:visitAllNodes(function(node)
        if node.duration ~= nil then
            node.duration = 0
        end
    end)
    results.duration = 12.5
    return Protocol.decodeResults(Protocol.encodeResults(results))
end

const function reportsMatch(actual: any, expected: any)
    expect(JsonReporter.format(actual)).to.equal(JsonReporter.format(expected))
    expect(JUnitReporter.format(actual)).to.equal(JUnitReporter.format(expected))
    expect(table.concat(TextReporter.format(actual, TEXT_OPTIONS), "\n")).to.equal(
        table.concat(TextReporter.format(expected, TEXT_OPTIONS), "\n")
    )
end

return function()
    it("should combine reversed completions and interleaved shard roots in exact global order", function()
        const first = shard({ "Beta", "Alpha" })
        first.children[1], first.children[2] = first.children[2], first.children[1]
        const second = shard({ "Gamma" })
        const names = { "Gamma", "Alpha", "Beta" }
        const merged = Results.merge({ first, second }, names, "", true, 4.5)
        const forward = Results.merge({ second, first }, names, nil, true, 4.5)
        expect(getmetatable(merged)).to.equal(TestResults)
        expect(getmetatable(merged.planNode)).to.equal(TestPlan)
        expect(merged.duration).to.equal(4.5)
        expect(merged.planNode.filter).to.equal(nil)
        expect(merged.planNode.forbidFocus).to.equal(true)
        expect(merged.successCount).to.equal(3)
        expect(merged.failureCount).to.equal(0)
        expect(#merged.children).to.equal(3)
        for index, name in ipairs(names) do
            const root = merged.planNode.children[index]
            expect(root.phrase).to.equal(name)
            expect(root.parent).to.equal(nil)
            expect(root.plan).to.equal(merged.planNode)
            expect(merged.children[index].planNode).to.equal(root)
            expect(root.children[1].parent).to.equal(root)
            expect(root.children[1].plan).to.equal(merged.planNode)
            expect(root.children[1]:getFullName()).to.equal(`{name} passes`)
            expect(root.specModule.snapshotPath).to.equal(`Tests/{name}.spec.luau`)
        end
        expect(#merged.planNode:findNodes(function()
            return true
        end)).to.equal(6)
        expect(merged.planNode:visualize()).to.equal(forward.planNode:visualize())
        expect(merged:visualize()).to.equal(forward:visualize())
        reportsMatch(merged, forward)
    end)

    it("should retain completed empty specs and support a genuinely empty global run", function()
        const emptySpec = run({ "Empty" }, { Empty = function() end })
        const merged = Results.merge({ emptySpec }, { "Empty" }, nil, false, 0)
        expect(#merged.children).to.equal(1)
        expect(#merged.planNode.children).to.equal(1)
        expect(merged.children[1].planNode.phrase).to.equal("Empty")
        expect(merged.successCount).to.equal(0)
        expect(merged.failureCount).to.equal(0)
        const empty = Results.merge({}, {}, nil, false, 0)
        expect(#empty.children).to.equal(0)
        expect(#empty.planNode.children).to.equal(0)
        expect(empty.successCount).to.equal(0)
        expect(empty.failureCount).to.equal(0)
        expect(empty.skippedCount).to.equal(0)
        expect(empty.focusGuardFailed).to.equal(false)
        expect(empty.snapshotSummary.Matched).to.equal(0)
        expect(#empty.snapshotSummary.Obsolete).to.equal(0)
    end)

    it("should add one global focus guard with count and reporter parity to a single run", function()
        const methods = {
            Alpha = function()
                Testable.itFOCUS("selected", function()
                    Testable.fail("selected failure")
                end, { Serial = true, Timeout = 2 })
                Testable.it("excluded alpha", function() end)
                Testable.itSKIP("pending", function() end, "not ready")
            end,
            Beta = function()
                Testable.describe("nested", function()
                    Testable.it("excluded beta", function() end)
                    Testable.it("excluded gamma", function() end)
                end)
            end,
        }
        const first = run({ "Alpha" }, methods, true)
        const second = run({ "Beta" }, methods, true)
        expect(first.focusGuardFailed).to.equal(false)
        expect(second.focusGuardFailed).to.equal(false)
        const merged = Results.merge({ second, first }, { "Alpha", "Beta" }, nil, true, 12.5)
        const reference = run({ "Alpha", "Beta" }, methods, nil, true)
        expect(merged.failureCount).to.equal(2)
        expect(merged.successCount).to.equal(0)
        expect(merged.skippedCount).to.equal(4)
        expect(merged.focusExcludedCount).to.equal(3)
        expect(merged.focusGuardFailed).to.equal(true)
        expect(#merged.children).to.equal(3)
        expect(#merged.planNode.children).to.equal(2)
        expect(merged.focusGuardNode).to.equal(merged.children[3])
        expect(merged.focusGuardNode.planNode.plan).to.equal(merged.planNode)
        expect(merged.focusGuardNode.errors[1]).to.equal(TestSession.formatFocusGuardError(3))
        expect(merged.errors[1]).to.equal(first.errors[1])
        expect(string.find(merged.errors[1], "selected failure", 1, true) ~= nil).to.equal(true)
        expect(merged.errors[2]).to.equal(merged.focusGuardNode.errors[1])
        const selected = merged.planNode.children[1].children[1]
        expect(selected.modifier).to.equal(TestEnum.NodeModifier.Focus)
        expect(selected.serial).to.equal(true)
        expect(selected.timeout).to.equal(2)
        expect(merged.children[1].children[3].skipReason).to.equal("not ready")
        expect(merged.children[2].children[1].children[1].excludedByFocus).to.equal(true)
        reportsMatch(merged, reference)
        reportsMatch(Protocol.decodeResults(Protocol.encodeResults(merged)), reference)
        const session = TestSession.new(merged.planNode)
        session.results = merged
        session.forbidFocus = true
        session:finalize()
        expect(#merged.children).to.equal(3)
        expect(merged.failureCount).to.equal(2)
        expect(first.focusGuardNode).to.equal(nil)
        expect(second.focusGuardNode).to.equal(nil)
    end)

    it("should preserve filtered and explicit skips without inventing a focus failure", function()
        const methods = {
            Spec = function()
                Testable.describeSKIP("group", function()
                    Testable.it("keep skipped", function() end)
                end, "group reason")
                Testable.itFOCUS("filtered focus", function() end)
                Testable.it("keep passes", function() end)
            end,
        }
        const input = run({ "Spec" }, methods, nil, false, "keep")
        const merged = Results.merge({ input }, { "Spec" }, "keep", true, 12.5)
        expect(merged.planNode.filter).to.equal("keep")
        expect(merged.filteredCount).to.equal(1)
        expect(merged.skippedCount).to.equal(2)
        expect(merged.successCount).to.equal(1)
        expect(merged.focusExcludedCount).to.equal(0)
        expect(merged.focusGuardFailed).to.equal(false)
        expect(merged.focusGuardNode).to.equal(nil)
        expect(merged.children[1].children[1].planNode.filteredOut).to.equal(true)
        expect(merged.children[1].children[1].skipReason).to.equal(TestEnum.SkipReason.Filter)
        expect(merged.planNode.children[1].children[1].skipReason).to.equal("group reason")
        reportsMatch(merged, input)
    end)

    it("should keep focus exclusions but not add a guard when focus is allowed", function()
        const methods = {
            Spec = function()
                Testable.itFOCUS("selected", function() end)
                Testable.it("excluded", function() end)
            end,
        }
        const input = run({ "Spec" }, methods, true)
        const merged = Results.merge({ input }, { "Spec" }, nil, false, 12.5)
        expect(merged.focusExcludedCount).to.equal(1)
        expect(merged.focusGuardFailed).to.equal(false)
        expect(merged.failureCount).to.equal(0)
        expect(merged.planNode.forbidFocus).to.equal(false)
        reportsMatch(merged, input)
    end)

    it("should preserve nested synthetic hook failures and all original plan links", function()
        const methods = {
            Hooks = function()
                Testable.describe("outer", function()
                    Testable.describe("inner", function()
                        Testable.beforeAll(function()
                            Testable.fail("setup failed")
                        end)
                        Testable.afterAll(function()
                            Testable.fail("cleanup failed")
                        end)
                        Testable.it("never runs", function() end)
                    end)
                end)
            end,
        }
        const input = run({ "Hooks" }, methods)
        const merged = Results.merge({ input }, { "Hooks" }, nil, false, 12.5)
        expect(merged.failureCount).to.equal(2)
        expect(#merged.errors).to.equal(2)
        const innerPlan = merged.planNode.children[1].children[1].children[1]
        const innerResult = merged.children[1].children[1].children[1]
        expect(innerPlan:getFullName()).to.equal("Hooks outer inner")
        expect(#innerPlan.children).to.equal(3)
        expect(#innerResult.children).to.equal(2)
        expect(innerResult.children[1].planNode.phrase).to.equal("beforeAll")
        expect(innerResult.children[2].planNode.phrase).to.equal("afterAll")
        for _, node in ipairs(innerResult.children) do
            expect(node.planNode.parent).to.equal(nil)
            expect(node.planNode.plan).to.equal(merged.planNode)
            expect(node.planNode:getFullName()).to.equal(node.planNode.phrase)
            expect(table.find(innerPlan.children, node.planNode)).to.equal(nil)
        end
        merged.planNode:visitAllNodes(function(node)
            expect(node.plan).to.equal(merged.planNode)
            if node.parent ~= nil then
                expect(table.find(node.parent.children, node) ~= nil).to.equal(true)
            end
        end)
        reportsMatch(merged, input)
        expect(merged.planNode:visualize()).to.equal(input.planNode:visualize())
    end)

    it("should recompute planning failures and gather every error in global spec order", function()
        const first = shard({ "Alpha" })
        first.planNode.children[1].loadError = "collection failed"
        first.children[1].status = TestEnum.TestStatus.Failure
        first.children[1].errors = { "collection failed", "additional diagnostic" }
        first.children[1].children[1].status = TestEnum.TestStatus.Failure
        first.children[1].children[1].errors = { "assertion failed" }
        first.children[1].children[1].messages = { "message" }
        const session = TestSession.new(first.planNode)
        session.results = first
        session:finalize()
        const merged = Results.merge({ shard({ "Beta" }), first }, { "Alpha", "Beta" }, nil, false, 0)
        expect(merged.successCount).to.equal(1)
        expect(merged.failureCount).to.equal(2)
        expect(#merged.errors).to.equal(3)
        expect(merged.errors[1]).to.equal("collection failed")
        expect(merged.errors[2]).to.equal("additional diagnostic")
        expect(merged.errors[3]).to.equal("assertion failed")
        expect(merged.children[1].children[1].messages[1]).to.equal("message")
        expect(Protocol.decodeResults(Protocol.encodeResults(merged)).failureCount).to.equal(2)
    end)

    it("should sum every snapshot count and sort obsolete entries by path then key", function()
        const first = shard({ "Alpha" })
        first.snapshotSummary = {
            Failed = 1,
            Matched = 2,
            Obsolete = { { Path = "z.snap", Key = "a" }, { Path = "a.snap", Key = "z" } },
            Removed = 3,
            Updated = 4,
            Written = 5,
        }
        const second = shard({ "Beta" })
        second.snapshotSummary = {
            Failed = 6,
            Matched = 7,
            Obsolete = { { Path = "a.snap", Key = "b" }, { Path = "a.snap", Key = "a" } },
            Removed = 8,
            Updated = 9,
            Written = 10,
        }
        const merged = Results.merge({ second, first }, { "Alpha", "Beta" }, nil, false, 0)
        const summary = merged.snapshotSummary
        expect(summary.Failed).to.equal(7)
        expect(summary.Matched).to.equal(9)
        expect(summary.Removed).to.equal(11)
        expect(summary.Updated).to.equal(13)
        expect(summary.Written).to.equal(15)
        expect(#summary.Obsolete).to.equal(4)
        expect(summary.Obsolete[1].Path).to.equal("a.snap")
        expect(summary.Obsolete[1].Key).to.equal("a")
        expect(summary.Obsolete[2].Key).to.equal("b")
        expect(summary.Obsolete[3].Key).to.equal("z")
        expect(summary.Obsolete[4].Path).to.equal("z.snap")
        reportsMatch(merged, Results.merge({ first, second }, { "Alpha", "Beta" }, nil, false, 0))
        summary.Obsolete[1].Key = "changed"
        expect(second.snapshotSummary.Obsolete[2].Key).to.equal("a")
        expect(first.snapshotSummary.Obsolete[1].Path).to.equal("z.snap")
    end)

    it("should own all nested output and leave every shard unchanged on repeated merges", function()
        const input = shard({ "Spec" })
        input.children[1].children[1].messages = { "original" }
        const before = JsonReporter.format(input)
        const merged = Results.merge({ input }, { "Spec" }, nil, true, 2)
        const second = Results.merge({ input }, { "Spec" }, nil, true, 2)
        expect(JsonReporter.format(input)).to.equal(before)
        expect(input.planNode.children[1].plan).to.equal(input.planNode)
        expect(input.planNode.children[1].children[1].parent).to.equal(input.planNode.children[1])
        expect(merged.children[1] == input.children[1]).to.equal(false)
        expect(merged.planNode.children[1] == input.planNode.children[1]).to.equal(false)
        merged.planNode.children[1].specModule.path[1] = "changed output"
        merged.children[1].children[1].messages[1] = "changed output"
        merged.planNode.children[1].children[1].phrase = "changed output"
        expect(JsonReporter.format(input)).to.equal(before)
        expect(second.children[1].children[1].messages[1]).to.equal("original")
        expect(second.planNode.children[1].specModule.path[1]).to.equal("Spec")
        input.planNode.children[1].specModule.path[1] = "changed input"
        input.children[1].children[1].messages[1] = "changed input"
        expect(second.children[1].children[1].messages[1]).to.equal("original")
        expect(second.planNode.children[1].specModule.path[1]).to.equal("Spec")
    end)

    describe("exact membership", function()
        it("should reject missing shards including a passing empty shard", function()
            rejects(function()
                Results.merge({}, { "Spec" }, nil, false, 0)
            end, 'Missing planned spec "Spec"')
            rejects(function()
                Results.merge({ shard({}) }, { "Spec" }, nil, false, 0)
            end, 'Missing planned spec "Spec"')
        end)

        it("should reject planned roots without results even when every count is zero", function()
            const input = shard({})
            input.planNode:addChild("Spec", TestEnum.NodeType.Describe)
            rejects(function()
                Results.merge({ input }, { "Spec" }, nil, false, 0)
            end, 'Missing completed spec "Spec"')
        end)

        it("should reject unexpected planned roots even without results", function()
            const input = shard({})
            input.planNode:addChild("Unexpected", TestEnum.NodeType.Describe)
            rejects(function()
                Results.merge({ input }, {}, nil, false, 0)
            end, 'Unexpected planned spec "Unexpected"')
        end)

        it("should reject duplicate expected names and duplicate plans within or across shards", function()
            rejects(function()
                Results.merge({ shard({ "Spec" }) }, { "Spec", "Spec" }, nil, false, 0)
            end, "Duplicate expected spec")
            rejects(function()
                Results.merge({ shard({ "Spec", "Spec" }) }, { "Spec" }, nil, false, 0)
            end, "Duplicate planned spec")
            rejects(function()
                Results.merge({ shard({ "Spec" }), shard({ "Spec" }) }, { "Spec" }, nil, false, 0)
            end, "Duplicate planned spec")
        end)

        it("should reject unexpected results rather than discard them", function()
            const input = shard({ "Spec" })
            const session = TestSession.new(input.planNode)
            session.results = input
            session:pushNode({ phrase = "Unexpected", type = TestEnum.NodeType.It })
            session:setError("hidden error")
            session:popNode()
            session:finalize()
            rejects(function()
                Results.merge({ input }, { "Spec" }, nil, false, 0)
            end, 'Unexpected completed spec "Unexpected"')
        end)

        it("should reject detached result impostors with the right name but wrong plan identity", function()
            const input = shard({ "Spec" })
            const replacement = TestPlan.new():addChild("Spec", TestEnum.NodeType.Describe)
            input.children[1] = TestResults.createNode(replacement)
            input.children[1].status = TestEnum.TestStatus.Success
            const session = TestSession.new(input.planNode)
            session.results = input
            session:finalize()
            rejects(function()
                Results.merge({ input }, { "Spec" }, nil, false, 0)
            end, "must refer to its shard's plan root")
        end)

        it("should reject duplicate results even when their names refer to different plan nodes", function()
            const input = shard({ "Spec" })
            const extra = TestResults.createNode(TestPlan.new():addChild("Spec", TestEnum.NodeType.Describe))
            extra.status = TestEnum.TestStatus.Success
            table.insert(input.children, extra)
            rejects(function()
                Results.merge({ input }, { "Spec" }, nil, false, 0)
            end, "Duplicate completed spec")
        end)

        it("should reject non-suite plan roots", function()
            const input = shard({ "Spec" })
            input.planNode.children[1].type = TestEnum.NodeType.It
            const session = TestSession.new(input.planNode)
            session.results = input
            session:finalize()
            rejects(function()
                Results.merge({ input }, { "Spec" }, nil, false, 0)
            end, "Plan roots must be spec suites")
        end)

        it("should reject worker focus guard flags, references, and unmarked guard nodes", function()
            const flagged = shard({ "Spec" })
            flagged.focusGuardFailed = true
            rejects(function()
                Results.merge({ flagged }, { "Spec" }, nil, false, 0)
            end, "defer the focus guard")
            const referenced = shard({ "Spec" })
            referenced.focusGuardNode = referenced.children[1]
            rejects(function()
                Results.merge({ referenced }, { "Spec" }, nil, false, 0)
            end, "defer the focus guard")
            const unmarked = shard({ "Spec" })
            const guard = TestResults.createNode({ phrase = TestSession.FocusGuardPhrase, type = TestEnum.NodeType.It })
            guard.status = TestEnum.TestStatus.Failure
            guard.errors = { "guard failed" }
            table.insert(unmarked.children, guard)
            const session = TestSession.new(unmarked.planNode)
            session.results = unmarked
            session:finalize()
            rejects(function()
                Results.merge({ unmarked }, { "Spec" }, nil, false, 0)
            end, "Unexpected completed spec")
        end)

        it("should reject corrupt or unfinished shards through the protocol", function()
            const badCount = shard({ "Spec" })
            badCount.successCount = 0
            rejects(function()
                Results.merge({ badCount }, { "Spec" }, nil, false, 0)
            end, "does not match the result tree")
            const unfinished = shard({ "Spec" })
            unfinished.children[1].status = nil
            rejects(function()
                Results.merge({ unfinished }, { "Spec" }, nil, false, 0)
            end, "must have a status")
        end)
    end)

    describe("argument validation", function()
        for _, field in { "shards", "names" } do
            it(`should reject sparse or dictionary {field} arrays without dropping entries`, function()
                const sparse = {}
                for _, index in { 2, 3, 4, 6 } do
                    sparse[index] = if field == "shards" then shard({ "Spec" }) else "Spec"
                end
                const dictionary = { Extra = if field == "shards" then shard({ "Spec" }) else "Spec" }
                for _, invalid in { sparse, dictionary, false, "invalid" } do
                    rejects(function()
                        Results.merge(
                            if field == "shards" then invalid else {},
                            if field == "names" then invalid else {},
                            nil,
                            false,
                            0
                        )
                    end)
                end
            end)
        end
        for _, value in { -1, math.huge, -math.huge, 0 / 0, "invalid", false } do
            it(`should reject invalid duration {tostring(value)}`, function()
                rejects(function()
                    Results.merge({}, {}, nil, false, value :: any)
                end, "finite nonnegative")
            end)
        end
        it("should reject invalid names, filter, focus flag, and shard values", function()
            for _, name in { "", false, 42 } do
                rejects(function()
                    Results.merge({}, { name } :: any, nil, false, 0)
                end, "nonempty strings")
            end
            rejects(function()
                Results.merge({}, {}, false :: any, false, 0)
            end, "filter")
            rejects(function()
                Results.merge({}, {}, nil, nil :: any, 0)
            end, "forbidFocus")
            rejects(function()
                Results.merge({ false }, {}, nil, false, 0)
            end, "completed TestResults")
        end)
    end)
end
