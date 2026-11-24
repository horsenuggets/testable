--[[

WorkerProtocolTest.spec

Pins the worker boundary's plain-data contract, class reconstruction, reporter parity,
and exact completion identities. Invalid workers must fail explicitly rather than turn
missing or corrupt results into a passing run.

--]]

const JUnitReporter = require("../Source/Testable/Reporters/JUnitReporter")
const JsonReporter = require("../Source/Testable/Reporters/JsonReporter")
const Protocol = require("../Source/Testable/Workers/Protocol")
const TestEnum = require("../Source/Testable/TestEnum")
const TestPlan = require("../Source/Testable/TestPlan")
const TestResults = require("../Source/Testable/TestResults")
const TestSession = require("../Source/Testable/TestSession")
const Testable = require("../Source/Testable")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")
const ToolError = require("../Source/Testable/ToolError")
const serde = require("@lune/serde")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it
const FILES = { "Tests/First.spec.luau", "Tests/Second.spec.luau" }
const TEXT_OPTIONS = { AlphabeticalSort = false, Color = false, Indent = "   ", PrintSkipped = true }

const function rejects(callback: () -> (), fragment: string?)
    const ok, message = pcall(callback)
    expect(ok).to.equal(false)
    expect(string.find(tostring(message), "Invalid worker protocol.", 1, true) ~= nil).to.equal(true)
    if fragment ~= nil then
        expect(string.find(tostring(message), fragment, 1, true) ~= nil).to.equal(true)
    end
end

const function plain(value: any, active: any?)
    const kind = type(value)
    expect(kind == "table" or kind == "string" or kind == "boolean" or kind == "number" or kind == "nil").to.equal(true)
    if kind == "table" then
        expect(getmetatable(value)).to.equal(nil)
        const stack = active or {}
        expect(stack[value]).to.equal(nil)
        stack[value] = true
        for _, item in pairs(value) do
            plain(item, stack)
        end
        stack[value] = nil
    end
end

const function fixture(): any
    const plan = TestPlan.new({ Unsafe = function() end })
    plan.filter = "selected"
    plan.forbidFocus = true
    const suite = plan:addChild("Spec", TestEnum.NodeType.Describe, TestEnum.NodeModifier.Focus)
    suite.collected = true
    suite.serial = true
    suite.callback = function() end
    suite.specModule = {
        method = function() end,
        path = { "Spec", "Tests" },
        pathStringForSorting = "tests.spec",
        snapshotPath = "Tests/Spec.spec.luau",
    }
    const success = suite:addChild("selected", TestEnum.NodeType.It)
    success.timeout = 2
    success.filteredOut = false
    const group = suite:addChild("group", TestEnum.NodeType.Describe, TestEnum.NodeModifier.Skip)
    group.skipReason = "group reason"
    const skipped = group:addChild("skipped", TestEnum.NodeType.It, TestEnum.NodeModifier.Skip)
    skipped.skipReason = "todo"
    const filtered = suite:addChild("filtered", TestEnum.NodeType.It)
    filtered.filteredOut = true
    const excluded = suite:addChild("excluded", TestEnum.NodeType.It)
    const failed = suite:addChild("failed", TestEnum.NodeType.It)
    const broken = plan:addChild("Broken", TestEnum.NodeType.Describe)
    broken.collected = true
    broken.loadError = "collection failure"
    -- The plan contains nodes that never generated results, including hooks.
    suite:addChild("beforeEach_0", TestEnum.NodeType.BeforeEach).timeout = 1
    plan:addChild("Unexecuted", TestEnum.NodeType.Describe)

    const session = TestSession.new(plan)
    const results = session.results
    const suiteResult = TestResults.createNode(suite)
    suiteResult.status = TestEnum.TestStatus.Failure
    suiteResult.duration = 1.5
    const function add(parent: any, node: any, status: string, duration: number?): any
        const result = TestResults.createNode(node)
        result.status = status
        result.duration = duration
        table.insert(parent.children, result)
        return result
    end
    add(suiteResult, success, TestEnum.TestStatus.Success, 0.25).messages = { "diagnostic" }
    const groupResult = add(suiteResult, group, TestEnum.TestStatus.Skipped, 0)
    add(groupResult, skipped, TestEnum.TestStatus.Skipped).skipReason = "todo"
    add(suiteResult, filtered, TestEnum.TestStatus.Skipped).skipReason = TestEnum.SkipReason.Filter
    const excludedResult = add(suiteResult, excluded, TestEnum.TestStatus.Skipped)
    excludedResult.skipReason = TestEnum.SkipReason.Focus
    excludedResult.excludedByFocus = true
    add(suiteResult, failed, TestEnum.TestStatus.Failure, 0.5).errors = { "assertion failed", "stack line" }
    table.insert(results.children, suiteResult)
    add(results, broken, TestEnum.TestStatus.Failure, 0.125).errors = { broken.loadError }
    session.forbidFocus = true
    session:finalize()
    results.duration = 2
    results.snapshotSummary = {
        Failed = 1,
        Matched = 2,
        Obsolete = { { Key = "old key", Path = "Tests/__snapshots__/Spec.snap" } },
        Removed = 3,
        Updated = 4,
        Written = 5,
    }
    results.snapshots = { Results = results, Finish = function() end }
    return results
end

return function()
    describe("tool error transfers", function()
        it("should reconstruct local error identity for every kind without transferring metatables", function()
            for _, kind in pairs(ToolError.Kind) do
                const original = ToolError.new(kind, "The worker could not provide a verdict.")
                const dto = Protocol.encodeProblem(original, "run", 2)
                plain(dto)
                const decoded = Protocol.decodeProblem(dto, "run", 2)
                expect(ToolError.is(decoded)).to.equal(true)
                expect(decoded ~= original).to.equal(true)
                expect(decoded.Kind).to.equal(kind)
                expect(decoded.Message).to.equal(original.Message)
                dto.Message = "changed after decoding"
                expect(decoded.Message).to.equal(original.Message)
            end
        end)

        it("should reject foreign identities and malformed or executable problem data", function()
            const original = ToolError.new(ToolError.Kind.EmptyFilter, "Nothing matched.")
            const base = Protocol.encodeProblem(original, "run", 2)
            for _, mutate in
                {
                    function(dto)
                        dto.Version = 99
                    end,
                    function(dto)
                        dto.RunId = "other"
                    end,
                    function(dto)
                        dto.JobId = 3
                    end,
                    function(dto)
                        dto.Kind = "Unknown"
                    end,
                    function(dto)
                        dto.Message = nil
                    end,
                    function(dto)
                        dto.Message = function() end
                    end,
                    function(dto)
                        dto.Extra = true
                    end,
                    function(dto)
                        dto.Message = dto
                    end,
                    function(dto)
                        setmetatable(dto, {})
                    end,
                }
            do
                const dto = table.clone(base)
                mutate(dto)
                rejects(function()
                    Protocol.decodeProblem(dto, "run", 2)
                end)
            end
            rejects(function()
                Protocol.decodeProblem(base, "", 2)
            end)
            rejects(function()
                Protocol.decodeProblem(base, "run", 0)
            end)
            rejects(function()
                Protocol.encodeProblem({ Kind = "EmptyFilter", Message = "lookalike" }, "run", 2)
            end)
        end)
    end)

    describe("result transfers", function()
        it("should reconstruct the original classes and retain every result and full plan node", function()
            const original = fixture()
            const dto = Protocol.encodeResults(original)
            plain(dto)
            const decoded = Protocol.decodeResults(serde.decode("json", serde.encode("json", dto)))
            expect(getmetatable(decoded)).to.equal(TestResults)
            expect(getmetatable(decoded.planNode)).to.equal(TestPlan)
            expect(decoded:visualize()).to.equal(original:visualize())
            expect(decoded.planNode:visualize()).to.equal(original.planNode:visualize())
            expect(#decoded.planNode:findNodes(function()
                return true
            end)).to.equal(10)
            expect(decoded.planNode.filter).to.equal("selected")
            expect(decoded.planNode.forbidFocus).to.equal(true)
            expect(decoded.planNode.extraEnvironment).to.equal(nil)
            expect(decoded.snapshots).to.equal(nil)
            expect(decoded.duration).to.equal(2)
            expect(decoded.successCount).to.equal(1)
            expect(decoded.failureCount).to.equal(3)
            expect(decoded.skippedCount).to.equal(3)
            expect(decoded.filteredCount).to.equal(1)
            expect(decoded.focusExcludedCount).to.equal(1)
            expect(decoded.focusGuardFailed).to.equal(true)
            expect(decoded.focusGuardNode).to.equal(decoded.children[3])
            expect(decoded.focusGuardNode.planNode:getFullName()).to.equal(TestSession.FocusGuardPhrase)
            expect(decoded.focusGuardNode.planNode.plan).to.equal(decoded.planNode)
            expect(#decoded.errors).to.equal(4)
            const suite = decoded.planNode.children[1]
            expect(decoded.children[1].planNode).to.equal(suite)
            expect(suite.plan).to.equal(decoded.planNode)
            expect(suite.parent).to.equal(nil)
            expect(suite.callback).to.equal(nil)
            expect(suite.serial).to.equal(true)
            expect(suite.collected).to.equal(true)
            expect(suite.modifier).to.equal(TestEnum.NodeModifier.Focus)
            expect(suite.specModule.method).to.equal(nil)
            expect(suite.specModule.pathStringForSorting).to.equal("tests.spec")
            expect(suite.specModule.snapshotPath).to.equal("Tests/Spec.spec.luau")
            expect(suite.specModule.path[2]).to.equal("Tests")
            expect(suite.children[1].parent).to.equal(suite)
            expect(suite.children[1].plan).to.equal(decoded.planNode)
            expect(suite.children[1]:getFullName()).to.equal("Spec selected")
            expect(suite.children[1].timeout).to.equal(2)
            expect(suite.children[1].filteredOut).to.equal(false)
            expect(suite.children[2].skipReason).to.equal("group reason")
            expect(suite.children[2].children[1].modifier).to.equal(TestEnum.NodeModifier.Skip)
            expect(decoded.children[1].children[2].children[1].duration).to.equal(nil)
            expect(decoded.children[1].children[2].children[1].skipReason).to.equal("todo")
            expect(decoded.children[1].children[1].messages[1]).to.equal("diagnostic")
            expect(decoded.planNode.children[2].loadError).to.equal("collection failure")
            expect(dto.Plan.Children[1].Id).to.equal(1)
            expect(dto.Plan.Children[1].Children[1].Id).to.equal(2)
            expect(dto.Results.Children[1].Children[1].PlanId).to.equal(2)
            expect(#dto.Plan.Children).to.equal(3)
            expect(#dto.Detached).to.equal(1)
            local visited = 0
            decoded:visitAllNodes(function()
                visited += 1
            end)
            expect(visited).to.equal(9)
            const session = TestSession.new(decoded.planNode)
            session.results = decoded
            session.forbidFocus = true
            session:finalize()
            expect(#decoded.children).to.equal(3)
            expect(decoded.failureCount).to.equal(3)
        end)

        it("should preserve exact output from all tree reporters", function()
            const original = fixture()
            const decoded = Protocol.decodeResults(Protocol.encodeResults(original))
            expect(JsonReporter.format(decoded)).to.equal(JsonReporter.format(original))
            expect(JUnitReporter.format(decoded)).to.equal(JUnitReporter.format(original))
            expect(table.concat(TextReporter.format(decoded, TEXT_OPTIONS), "\n")).to.equal(
                table.concat(TextReporter.format(original, TEXT_OPTIONS), "\n")
            )
        end)

        it("should round-trip real runner output including focus and planning failures", function()
            const plan = Testable.TestPlanner.createPlan({
                {
                    method = function()
                        Testable.itFOCUS("selected", function() end)
                        Testable.it("excluded", function() end)
                        Testable.itSKIP("skipped", function() end, "not ready")
                        Testable.describe("broken", function()
                            error("planning failed")
                        end)
                    end,
                    path = { "ActualSpec" },
                    pathStringForSorting = "actualspec",
                    snapshotPath = "Tests/ActualSpec.spec.luau",
                },
            })
            plan.forbidFocus = true
            const original = Testable.TestRunner.runPlan(plan)
            const decoded = Protocol.decodeResults(Protocol.encodeResults(original))
            expect(decoded.failureCount).to.equal(2)
            expect(decoded.focusExcludedCount).to.equal(1)
            expect(decoded.focusGuardNode.planNode:getFullName()).to.equal(TestSession.FocusGuardPhrase)
            expect(JsonReporter.format(decoded)).to.equal(JsonReporter.format(original))
            expect(JUnitReporter.format(decoded)).to.equal(JUnitReporter.format(original))
        end)

        it("should retain synthetic hook failures without adding them to the original plan", function()
            const plan = Testable.TestPlanner.createPlan({
                {
                    method = function()
                        Testable.beforeAll(function()
                            error("hook failed")
                        end)
                        Testable.it("never runs", function() end)
                    end,
                    path = { "HookSpec" },
                    pathStringForSorting = "hookspec",
                },
            })
            const original = Testable.TestRunner.runPlan(plan)
            const dto = Protocol.encodeResults(original)
            const decoded = Protocol.decodeResults(dto)
            expect(decoded.failureCount).to.equal(1)
            expect(#dto.Detached).to.equal(1)
            expect(decoded.planNode:visualize()).to.equal(plan:visualize())
            expect(JsonReporter.format(decoded)).to.equal(JsonReporter.format(original))
            expect(JUnitReporter.format(decoded)).to.equal(JUnitReporter.format(original))
        end)

        it("should support a new empty result and preserve absent optional fields", function()
            const original = TestResults.new(TestPlan.new())
            const decoded = Protocol.decodeResults(Protocol.encodeResults(original))
            expect(decoded.successCount).to.equal(0)
            expect(decoded.focusExcludedCount).to.equal(nil)
            expect(decoded.focusGuardFailed).to.equal(nil)
            expect(decoded.status).to.equal(nil)
            expect(decoded.snapshotSummary).to.equal(nil)
            expect(#decoded.children).to.equal(0)
        end)

        for _, field in { "Plan", "Results" } do
            it(`should reject hidden sparse children in {field}`, function()
                const dto = Protocol.encodeResults(TestResults.new(TestPlan.new()))
                const children = {}
                for _, index in { 2, 3, 4, 6 } do
                    children[index] = {
                        Children = {},
                        Errors = { "hidden failure" },
                        Id = 999,
                        PlanId = 999,
                        Status = TestEnum.TestStatus.Failure,
                    }
                end
                dto[field].Children = children
                rejects(function()
                    Protocol.decodeResults(dto)
                end, "dense array")
            end)
        end

        it("should isolate inputs and outputs at every nested boundary", function()
            const original = fixture()
            const dto = Protocol.encodeResults(original)
            const decoded = Protocol.decodeResults(dto)
            original.planNode.children[1].specModule.path[1] = "changed original"
            original.snapshotSummary.Obsolete[1].Key = "changed original"
            original.children[1].children[5].errors[1] = "changed original"
            expect(dto.Plan.Children[1].SpecModule.Path[1]).to.equal("Spec")
            expect(dto.Results.SnapshotSummary.Obsolete[1].Key).to.equal("old key")
            expect(dto.Results.Children[1].Children[5].Errors[1]).to.equal("assertion failed")
            dto.Plan.Children[1].SpecModule.Path[1] = "changed wire"
            dto.Results.SnapshotSummary.Obsolete[1].Key = "changed wire"
            dto.Results.Children[1].Children[5].Errors[1] = "changed wire"
            expect(decoded.planNode.children[1].specModule.path[1]).to.equal("Spec")
            expect(decoded.snapshotSummary.Obsolete[1].Key).to.equal("old key")
            expect(decoded.children[1].children[5].errors[1]).to.equal("assertion failed")
            const second = Protocol.decodeResults(Protocol.encodeResults(decoded))
            decoded.children[1].children[1].messages[1] = "changed decoded"
            expect(second.children[1].children[1].messages[1]).to.equal("diagnostic")
        end)

        it("should preserve stable plan identities even when result order differs", function()
            const original = fixture()
            const children = original.children[1].children
            children[1], children[2] = children[2], children[1]
            const dto = Protocol.encodeResults(original)
            expect(dto.Results.Children[1].Children[2].PlanId).to.equal(2)
            const decoded = Protocol.decodeResults(dto)
            expect(decoded.children[1].children[2].planNode).to.equal(decoded.planNode.children[1].children[1])
        end)

        const malformed = {
            {
                Name = "unknown version",
                Change = function(dto)
                    dto.Version = 2
                end,
            },
            {
                Name = "missing plan",
                Change = function(dto)
                    dto.Plan = nil
                end,
            },
            {
                Name = "missing results",
                Change = function(dto)
                    dto.Results = nil
                end,
            },
            {
                Name = "unknown field",
                Change = function(dto)
                    dto.Executable = true
                end,
            },
            {
                Name = "invalid status",
                Change = function(dto)
                    dto.Results.Children[1].Status = "Passed"
                end,
            },
            {
                Name = "unfinished node",
                Change = function(dto)
                    dto.Results.Children[1].Status = nil
                end,
            },
            {
                Name = "wrong error type",
                Change = function(dto)
                    dto.Results.Errors = { 1 }
                end,
            },
            {
                Name = "missing errors",
                Change = function(dto)
                    dto.Results.Errors = nil
                end,
            },
            {
                Name = "wrong total",
                Change = function(dto)
                    dto.Results.FailureCount = 0
                end,
            },
            {
                Name = "fractional total",
                Change = function(dto)
                    dto.Results.SuccessCount = 0.5
                end,
            },
            {
                Name = "wrong root errors",
                Change = function(dto)
                    dto.Results.Errors[1] = "wrong"
                end,
            },
            {
                Name = "invalid reference",
                Change = function(dto)
                    dto.Results.Children[1].PlanId = 999
                end,
            },
            {
                Name = "wrong result parent",
                Change = function(dto)
                    dto.Results.Children[1].Children[1].PlanId = dto.Plan.Children[3].Id
                end,
            },
            {
                Name = "duplicate test phrase",
                Change = function(dto)
                    dto.Plan.Children[1].Children[3].Phrase = "selected"
                end,
            },
            {
                Name = "unused detached node",
                Change = function(dto)
                    const extra = Protocol.encodeResults(fixture()).Detached[1]
                    extra.Id += 1
                    table.insert(dto.Detached, extra)
                end,
            },
            {
                Name = "userdata",
                Change = function(dto)
                    dto.Results.SnapshotSummary.Userdata = newproxy(false)
                end,
            },
            {
                Name = "executable spec metadata",
                Change = function(dto)
                    dto.Plan.Children[1].SpecModule.Method = "unsafe"
                end,
            },
            {
                Name = "duplicate result",
                Change = function(dto)
                    table.insert(dto.Results.Children, dto.Results.Children[1])
                end,
            },
            {
                Name = "duplicate plan id",
                Change = function(dto)
                    dto.Plan.Children[2].Id = 1
                end,
            },
            {
                Name = "missing phrase",
                Change = function(dto)
                    dto.Plan.Children[1].Phrase = nil
                end,
            },
            {
                Name = "invalid node type",
                Change = function(dto)
                    dto.Plan.Children[1].Type = "Test"
                end,
            },
            {
                Name = "invalid modifier",
                Change = function(dto)
                    dto.Plan.Children[1].Modifier = "Unknown"
                end,
            },
            {
                Name = "invalid metadata",
                Change = function(dto)
                    dto.Plan.Children[1].SpecModule.Path = { false }
                end,
            },
            {
                Name = "invalid timeout",
                Change = function(dto)
                    dto.Plan.Children[1].Timeout = 0
                end,
            },
            {
                Name = "negative duration",
                Change = function(dto)
                    dto.Results.Duration = -1
                end,
            },
            {
                Name = "nan duration",
                Change = function(dto)
                    dto.Results.Duration = 0 / 0
                end,
            },
            {
                Name = "infinite duration",
                Change = function(dto)
                    dto.Results.Duration = math.huge
                end,
            },
            {
                Name = "sparse array",
                Change = function(dto)
                    dto.Plan.Children[10] = dto.Plan.Children[1]
                end,
            },
            {
                Name = "dictionary children",
                Change = function(dto)
                    dto.Results.Children.Extra = {}
                end,
            },
            {
                Name = "cyclic children",
                Change = function(dto)
                    dto.Plan.Children[1].Children[1] = dto.Plan.Children[1]
                end,
            },
            {
                Name = "cyclic summary",
                Change = function(dto)
                    dto.Results.SnapshotSummary.Obsolete = dto.Results.SnapshotSummary
                end,
            },
            {
                Name = "function",
                Change = function(dto)
                    dto.Results.SnapshotSummary.Callback = function() end
                end,
            },
            {
                Name = "thread",
                Change = function(dto)
                    dto.Results.SnapshotSummary.Thread = coroutine.create(function() end)
                end,
            },
            {
                Name = "metatable",
                Change = function(dto)
                    setmetatable(dto.Results, {})
                end,
            },
            {
                Name = "missing summary count",
                Change = function(dto)
                    dto.Results.SnapshotSummary.Matched = nil
                end,
            },
            {
                Name = "invalid obsolete entry",
                Change = function(dto)
                    dto.Results.SnapshotSummary.Obsolete[1].Key = false
                end,
            },
            {
                Name = "missing focus guard",
                Change = function(dto)
                    dto.FocusGuardId = nil
                end,
            },
            {
                Name = "wrong focus guard",
                Change = function(dto)
                    dto.FocusGuardId = 2
                end,
            },
            {
                Name = "invalid guard flag",
                Change = function(dto)
                    dto.Results.FocusGuardFailed = "true"
                end,
            },
        }
        for _, case in malformed do
            it(`should reject a DTO with {case.Name}`, function()
                const dto = Protocol.encodeResults(fixture())
                case.Change(dto)
                rejects(function()
                    Protocol.decodeResults(dto)
                end)
            end)
        end

        it("should reject missing results even when a worker reports successful completion", function()
            rejects(function()
                Protocol.encodeResults(nil)
            end, "non-nil")
            rejects(function()
                Protocol.decodeResults(nil)
            end, "non-nil")
            rejects(function()
                Protocol.decodeResults(true)
            end, "non-nil")
        end)

        it("should reject malformed runtime results rather than dropping failures", function()
            const result = fixture()
            result.failureCount = 0
            rejects(function()
                Protocol.encodeResults(result)
            end, "FailureCount")
            const cyclic = fixture()
            table.insert(cyclic.children, cyclic)
            rejects(function()
                Protocol.encodeResults(cyclic)
            end, "cyclic")
            const badSummary = fixture()
            badSummary.snapshotSummary.Obsolete[1].Key = function() end
            rejects(function()
                Protocol.encodeResults(badSummary)
            end, "plain values")
            const badPlan = fixture()
            table.insert(badPlan.planNode.children, badPlan.planNode.children[1])
            rejects(function()
                Protocol.encodeResults(badPlan)
            end, "cyclic")
        end)
    end)

    describe("completion manifests", function()
        it("should copy and validate exact ordered run, job, assignment, and completion identities", function()
            const assigned = table.clone(FILES)
            const completed = table.clone(FILES)
            const manifest = Protocol.makeManifest("run", 1, assigned, completed)
            const validated = Protocol.validateManifest(manifest, "run", 1, FILES)
            expect(manifest.Version).to.equal(1)
            expect(manifest.RunId).to.equal("run")
            expect(manifest.JobId).to.equal(1)
            plain(manifest)
            assigned[1] = "changed assignment"
            completed[1] = "changed completion"
            expect(manifest.Assigned[1]).to.equal(FILES[1])
            expect(manifest.Completed[1]).to.equal(FILES[1])
            manifest.Assigned[1] = "changed manifest"
            manifest.Completed[1] = "changed manifest"
            expect(validated.Assigned[1]).to.equal(FILES[1])
            expect(validated.Completed[1]).to.equal(FILES[1])
        end)

        it("should support an empty assignment without inventing completed files", function()
            const manifest = Protocol.makeManifest("empty", 2, {}, {})
            expect(#Protocol.validateManifest(manifest, "empty", 2, {}).Completed).to.equal(0)
        end)

        const malformed = {
            {
                Name = "wrong run",
                Change = function(value)
                    value.RunId = "other"
                end,
            },
            {
                Name = "wrong job",
                Change = function(value)
                    value.JobId = 2
                end,
            },
            {
                Name = "wrong version",
                Change = function(value)
                    value.Version = 2
                end,
            },
            {
                Name = "missing assignment",
                Change = function(value)
                    value.Assigned = nil
                end,
            },
            {
                Name = "missing completion",
                Change = function(value)
                    value.Completed = nil
                end,
            },
            {
                Name = "missing completed file",
                Change = function(value)
                    table.remove(value.Completed)
                end,
            },
            {
                Name = "unexpected completed file",
                Change = function(value)
                    table.insert(value.Completed, "Other.spec.luau")
                end,
            },
            {
                Name = "duplicate completed file",
                Change = function(value)
                    value.Completed[2] = value.Completed[1]
                end,
            },
            {
                Name = "duplicate assigned file",
                Change = function(value)
                    value.Assigned[2] = value.Assigned[1]
                end,
            },
            {
                Name = "wrong assigned order",
                Change = function(value)
                    value.Assigned[1], value.Assigned[2] = value.Assigned[2], value.Assigned[1]
                end,
            },
            {
                Name = "wrong completed order",
                Change = function(value)
                    value.Completed[1], value.Completed[2] = value.Completed[2], value.Completed[1]
                end,
            },
            {
                Name = "wrong assigned identity",
                Change = function(value)
                    value.Assigned[1] = "Other.spec.luau"
                end,
            },
            {
                Name = "wrong completed identity",
                Change = function(value)
                    value.Completed[1] = "Other.spec.luau"
                end,
            },
            {
                Name = "empty identity",
                Change = function(value)
                    value.Completed[1] = ""
                end,
            },
            {
                Name = "non-string identity",
                Change = function(value)
                    value.Completed[1] = 1
                end,
            },
            {
                Name = "sparse completion",
                Change = function(value)
                    value.Completed[5] = "Other.spec.luau"
                end,
            },
            {
                Name = "extra field",
                Change = function(value)
                    value.Extra = true
                end,
            },
            {
                Name = "cyclic data",
                Change = function(value)
                    value.Completed[1] = value
                end,
            },
            {
                Name = "metatable",
                Change = function(value)
                    setmetatable(value, {})
                end,
            },
        }
        for _, case in malformed do
            it(`should reject a manifest with {case.Name}`, function()
                const value = Protocol.makeManifest("run", 1, FILES, FILES)
                case.Change(value)
                rejects(function()
                    Protocol.validateManifest(value, "run", 1, FILES)
                end)
            end)
        end

        it("should reject invalid coordinator inputs and nil completion", function()
            const manifest = Protocol.makeManifest("run", 1, FILES, FILES)
            rejects(function()
                Protocol.validateManifest(nil, "run", 1, FILES)
            end)
            rejects(function()
                Protocol.validateManifest(manifest, "", 1, FILES)
            end)
            rejects(function()
                Protocol.validateManifest(manifest, "run", 0, FILES)
            end)
            rejects(function()
                Protocol.validateManifest(manifest, "run", 0.5, FILES)
            end)
            rejects(function()
                Protocol.validateManifest(manifest, "run", math.huge, FILES)
            end)
            rejects(function()
                Protocol.validateManifest(manifest, "run", 1, { FILES[1], FILES[1] })
            end)
            rejects(function()
                Protocol.makeManifest("run", 1, FILES, { FILES[1] })
            end)
        end)
    end)
end
