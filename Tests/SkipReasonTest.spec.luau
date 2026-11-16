--[[

SkipReasonTest.spec

Tests todo tests and skip reasons. Covers how the skip variants record a reason on the
plan, how a session resolves the reason for a test, how the text reporter prints it, and
that reasons reach the results in both the parallel and sequential paths.

--]]

const IsolatedRun = require("./Helpers/IsolatedRun")
const TestEnum = require("../Source/Testable/TestEnum")
const TestPlan = require("../Source/Testable/TestPlan")
const TestSession = require("../Source/Testable/TestSession")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")

const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
const FOCUS = TestEnum.NodeModifier.Focus
const NONE = TestEnum.NodeModifier.None
const SKIP = TestEnum.NodeModifier.Skip
const SKIPPED = TestEnum.TestStatus.Skipped
const SUCCESS = TestEnum.TestStatus.Success
const MODIFIERS = { NONE, SKIP, FOCUS }

const function noop() end

--[[
    Creates a plan with a single root describe node and returns that node. Its
    environment holds the same functions a spec file sees as globals.
]]
const function newRoot(): any
    const plan = TestPlan.new()
    plan:addRoot({ "Root" }, noop)
    return plan.children[1]
end

const function resultNode(phrase: string, status: string?, skipReason: string?, children: { any }?): any
    return { children = children or {}, planNode = { phrase = phrase }, skipReason = skipReason, status = status }
end

const function reporterOptions(printSkipped: boolean, color: boolean?): TextReporter.Options
    return { AlphabeticalSort = false, Color = color == true, Indent = "   ", PrintSkipped = printSkipped }
end

--[[
    Resolves the skip decision for a plan node the way a parallel test session does, with
    only the test's own node on the stack.
]]
const function resolveSkip(planNode: any, hasFocusNodes: boolean): (boolean, string?, boolean)
    const session = TestSession.new(planNode.plan)
    session.hasFocusNodes = hasFocusNodes
    session:pushNode(planNode)
    return session:shouldSkip()
end

return function()
    describe("itTODO", function()
        it("should record a skipped test with the todo reason and no body", function()
            const root = newRoot()
            root.environment.itTODO("handles overflow")

            const node = root.children[1]
            expect(#root.children).to.equal(1)
            expect(node.phrase).to.equal("handles overflow")
            expect(node.type).to.equal(TestEnum.NodeType.It)
            expect(node.modifier).to.equal(SKIP)
            expect(node.skipReason).to.equal("todo")
            expect(node.callback).to.equal(nil)
        end)

        it("should reject a body", function()
            const root = newRoot()
            const ok, message = pcall(root.environment.itTODO, "handles overflow", noop)

            expect(ok).to.equal(false)
            expect(string.find(tostring(message), '"itTODO" only takes a name', 1, true) ~= nil).to.equal(true)
            expect(#root.children).to.equal(0)
        end)

        it("should reject any second argument, even nil or a reason", function()
            const root = newRoot()
            expect((pcall(root.environment.itTODO, "explicit nil", nil))).to.equal(false)
            expect((pcall(root.environment.itTODO, "reason", "later"))).to.equal(false)
            expect(#root.children).to.equal(0)
        end)

        it("should reject a duplicate name like any other test", function()
            const root = newRoot()
            root.environment.itTODO("handles overflow")
            expect((pcall(root.environment.itTODO, "handles overflow"))).to.equal(false)
            expect((pcall(root.environment.it, "handles overflow", noop))).to.equal(false)
        end)
    end)

    describe("skip variants", function()
        it("should store an optional reason on the plan node", function()
            for _, name in { "itSKIP", "xit", "describeSKIP", "xdescribe" } do
                const root = newRoot()
                root.environment[name]("with reason", noop, "waiting on the API")
                root.environment[name]("without reason", noop)

                expect(root.children[1].modifier).to.equal(SKIP)
                expect(root.children[1].skipReason).to.equal("waiting on the API")
                expect(root.children[2].modifier).to.equal(SKIP)
                expect(root.children[2].skipReason).to.equal(nil)
            end
        end)

        it("should reject a reason that is not a string", function()
            for _, name in { "itSKIP", "xit", "describeSKIP", "xdescribe", "itFIXME" } do
                const root = newRoot()
                for _, reason in { 1, true, {}, noop } :: { any } do
                    const ok, message = pcall(root.environment[name], "bad reason", noop, reason)
                    expect(ok).to.equal(false)
                    expect(string.find(tostring(message), "must be a string", 1, true) ~= nil).to.equal(true)
                end
                expect(#root.children).to.equal(0)
            end
        end)

        it("should let SKIP mark the enclosing block with an optional reason", function()
            const withReason = newRoot()
            withReason.environment.SKIP("needs a server")
            expect(withReason.modifier).to.equal(SKIP)
            expect(withReason.skipReason).to.equal("needs a server")

            const withoutReason = newRoot()
            withoutReason.environment.SKIP()
            expect(withoutReason.modifier).to.equal(SKIP)
            expect(withoutReason.skipReason).to.equal(nil)

            const badReason = newRoot()
            expect((pcall(badReason.environment.SKIP, 5))).to.equal(false)
            expect(badReason.modifier).to.equal(NONE)
        end)

        it("should give itFIXME and FIXME a fixme reason instead of warning", function()
            const root = newRoot()
            root.environment.itFIXME("broken", noop)
            root.environment.itFIXME("broken with message", noop, "times out")
            expect(root.children[1].modifier).to.equal(SKIP)
            expect(root.children[1].skipReason).to.equal("fixme")
            expect(root.children[1].callback).to.equal(noop)
            expect(root.children[2].skipReason).to.equal("fixme, times out")

            const block = newRoot()
            block.environment.FIXME()
            expect(block.modifier).to.equal(SKIP)
            expect(block.skipReason).to.equal("fixme")

            const blockWithMessage = newRoot()
            blockWithMessage.environment.FIXME("times out")
            expect(blockWithMessage.skipReason).to.equal("fixme, times out")
        end)

        it("should not attach a reason to tests that are not skipped", function()
            const root = newRoot()
            root.environment.it("plain", noop)
            root.environment.itFOCUS("focused", noop)
            root.environment.describe("block", noop)
            root.environment.describeFOCUS("focused block", noop)

            for _, child in root.children do
                expect(child.skipReason).to.equal(nil)
                expect(child.modifier == SKIP).to.equal(false)
            end
        end)
    end)

    describe("TestSession:shouldSkip()", function()
        it("should decide every combination of block modifier, test modifier, and focus", function()
            for _, blockModifier in MODIFIERS do
                for _, testModifier in MODIFIERS do
                    for _, otherFocus in { false, true } do
                        const root = newRoot()
                        const block = root:addChild("block", TestEnum.NodeType.Describe, blockModifier)
                        const middle = block:addChild("middle", TestEnum.NodeType.Describe)
                        const test = middle:addChild("test", TestEnum.NodeType.It, testModifier)
                        const hasFocusNodes = otherFocus or blockModifier == FOCUS or testModifier == FOCUS

                        const skip, reason, excludedByFocus = resolveSkip(test, hasFocusNodes)

                        -- The nearest modifier decides. An unmodified test only runs when
                        -- nothing in the plan is focused.
                        local nearest = testModifier
                        if nearest == NONE then
                            nearest = blockModifier
                        end
                        const expectExcluded = nearest == NONE and hasFocusNodes

                        expect(skip).to.equal(nearest == SKIP or expectExcluded)
                        expect(excludedByFocus).to.equal(expectExcluded)
                        expect(reason).to.equal(if expectExcluded then "excluded by focus" else nil)
                    end
                end
            end
        end)

        it("should propagate a block's reason to its tests", function()
            const root = newRoot()
            root.environment.describeSKIP("block", noop, "needs a server")
            const block = root.children[1]
            block.environment.describe("nested", noop)
            block.children[1].environment.it("deep", noop)
            block.environment.it("direct", noop)

            for _, hasFocusNodes in { false, true } do
                for _, test in { block.children[1].children[1], block.children[2] } do
                    const skip, reason, excludedByFocus = resolveSkip(test, hasFocusNodes)
                    expect(skip).to.equal(true)
                    expect(reason).to.equal("needs a server")
                    expect(excludedByFocus).to.equal(false)
                end
            end
        end)

        it("should prefer the nearest reason and fall back to an outer one", function()
            const root = newRoot()
            root.environment.describeSKIP("outer", noop, "outer reason")
            const outer = root.children[1]
            outer.environment.describeSKIP("inner", noop, "inner reason")
            outer.environment.describeSKIP("silent", noop)
            const inner, silent = outer.children[1], outer.children[2]
            inner.environment.itSKIP("own", noop, "own reason")
            inner.environment.it("inherits inner", noop)
            inner.environment.itSKIP("bare", noop)
            inner.environment.itTODO("unwritten")
            silent.environment.it("inherits outer", noop)

            const expected = {
                { Node = inner.children[1], Reason = "own reason" },
                { Node = inner.children[2], Reason = "inner reason" },
                { Node = inner.children[3], Reason = "inner reason" },
                { Node = inner.children[4], Reason = "todo" },
                { Node = silent.children[1], Reason = "outer reason" },
            }
            for _, case in expected do
                const skip, reason = resolveSkip(case.Node, false)
                expect(skip).to.equal(true)
                expect(reason).to.equal(case.Reason)
            end
        end)

        it("should return the same decision when asked twice", function()
            const root = newRoot()
            root.environment.itSKIP("skipped", noop, "flaky")
            const session = TestSession.new(root.plan)
            session:pushNode(root.children[1])

            const first = { session:shouldSkip() }
            const second = { session:shouldSkip() }
            expect(first[1]).to.equal(second[1])
            expect(first[2]).to.equal(second[2])
            expect(first[3]).to.equal(second[3])
        end)

        it("should store the reason on the result node", function()
            const root = newRoot()
            root.environment.itSKIP("skipped", noop, "flaky")
            const session = TestSession.new(root.plan)
            session:pushNode(root.children[1])
            const _, reason, excludedByFocus = session:shouldSkip()
            session:setSkipped(reason, excludedByFocus)

            const node = session.results.children[1]
            expect(node.status).to.equal(SKIPPED)
            expect(node.skipReason).to.equal("flaky")
            expect(node.excludedByFocus).to.equal(false)

            session:setSkipped()
            expect(node.skipReason).to.equal(nil)
            expect(node.excludedByFocus).to.equal(false)
        end)
    end)

    describe("TextReporter", function()
        it("should show the reason next to skipped tests when they are printed", function()
            const root = resultNode("Root", nil, nil, {
                resultNode("Suite", nil, nil, {
                    resultNode("runs", SUCCESS),
                    resultNode("flaky", SKIPPED, "waiting on the API"),
                    resultNode("unwritten", SKIPPED, "todo"),
                    resultNode("bare", SKIPPED),
                }),
            })

            expect(table.concat(TextReporter.formatTree(root, reporterOptions(true)), "\n")).to.equal(table.concat({
                "✓ Suite",
                "├── ✓ runs",
                "├── ○ flaky (waiting on the API)",
                "├── ○ unwritten (todo)",
                "└── ○ bare",
            }, "\n"))
        end)

        it("should hide reasons along with skipped tests when they are not printed", function()
            const root = resultNode("Root", nil, nil, {
                resultNode("Suite", nil, nil, {
                    resultNode("runs", SUCCESS),
                    resultNode("flaky", SKIPPED, "waiting on the API"),
                }),
            })

            expect(table.concat(TextReporter.formatTree(root, reporterOptions(false)), "\n")).to.equal(
                "✓ Suite\n└── ✓ runs"
            )
        end)

        it("should ignore reasons on tests that were not skipped and empty reasons", function()
            const root = resultNode("Root", nil, nil, {
                resultNode("Suite", nil, nil, {
                    resultNode("runs", SUCCESS, "stale reason"),
                    resultNode("empty", SKIPPED, ""),
                }),
            })

            expect(table.concat(TextReporter.formatTree(root, reporterOptions(true)), "\n")).to.equal(
                "✓ Suite\n├── ✓ runs\n└── ○ empty"
            )
        end)

        it("should keep the same text when color is enabled", function()
            const root = resultNode("Root", nil, nil, {
                resultNode("Suite", nil, nil, { resultNode("flaky", SKIPPED, "waiting on the API") }),
            })
            const colored = table.concat(TextReporter.formatTree(root, reporterOptions(true, true)), "\n")

            expect((colored:gsub("\27%[[%d;]*m", ""))).to.equal("○ Suite\n└── ○ flaky (waiting on the API)")
        end)
    end)

    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            it("should carry reasons through to the results and the report", function()
                const outcome = IsolatedRun.run(
                    [[
                        it("runs", function() end)
                        itSKIP("bare skip", function() end)
                        xit("flaky", function() end, "waiting on the API")
                        itFIXME("broken", function() end, "times out")
                        itTODO("unwritten")
                        describeSKIP("skipped block", function()
                            it("inherits", function() end)
                            itSKIP("overrides", function() end, "own reason")
                            describe("nested", function()
                                it("inherits deeply", function() end)
                            end)
                        end, "needs a server")
                        describe("marked block", function()
                            SKIP("marked later")
                            it("marked", function() end)
                        end)
                    ]],
                    { ForbidFocus = false, Parallel = mode.Parallel, PrintSkipped = true }
                )

                const expected = {
                    ["bare skip"] = "-",
                    ["broken"] = "fixme, times out",
                    ["flaky"] = "waiting on the API",
                    ["inherits"] = "needs a server",
                    ["inherits deeply"] = "needs a server",
                    ["marked"] = "marked later",
                    ["overrides"] = "own reason",
                    ["unwritten"] = "todo",
                }
                for phrase, reason in expected do
                    expect(outcome.Nodes[phrase].Status).to.equal("Skipped")
                    expect(outcome.Nodes[phrase].Reason or "-").to.equal(reason)
                    if reason ~= "-" then
                        expect(string.find(outcome.Output, `○ {phrase} ({reason})`, 1, true) ~= nil).to.equal(true)
                    end
                end

                expect(outcome.Nodes["runs"].Status).to.equal("Success")
                expect(outcome.Nodes["runs"].Reason).to.equal(nil)
                expect(outcome.Passed).to.equal(true)
                expect(outcome.ExitedCleanly).to.equal(true)
                expect(outcome.SuccessCount).to.equal(1)
                expect(outcome.FailureCount).to.equal(0)
                expect(outcome.SkippedCount).to.equal(8)
                expect(outcome.FocusExcludedCount).to.equal(0)
            end)

            it("should never run a skipped or todo test's body", function()
                const outcome = IsolatedRun.run(
                    [[
                        itSKIP("skipped", function()
                            error("skipped body ran")
                        end, "not ready")
                        itFIXME("broken", function()
                            error("fixme body ran")
                        end)
                        describeSKIP("skipped block", function()
                            describe("nested", function()
                                it("nested", function()
                                    error("nested body ran")
                                end)
                            end)
                        end)
                        itTODO("unwritten")
                    ]],
                    { ForbidFocus = false, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(true)
                expect(outcome.FailureCount).to.equal(0)
                expect(outcome.SkippedCount).to.equal(4)
                expect(string.find(outcome.Output, "body ran", 1, true)).to.equal(nil)
                expect(string.find(outcome.Output, "(not ready)", 1, true)).to.equal(nil)
            end)

            it("should fail planning when a todo test is given a body", function()
                const outcome = IsolatedRun.run(
                    [[
                        it("runs", function() end)
                        itTODO("unwritten", function() end)
                    ]],
                    { ForbidFocus = false, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(false)
                expect(outcome.FailureCount).to.equal(1)
                expect(string.find(outcome.Output, '"itTODO" only takes a name', 1, true) ~= nil).to.equal(true)
            end)

            it("should give focus-excluded tests a reason and keep explicit reasons", function()
                const outcome = IsolatedRun.run(
                    [[
                        itFOCUS("focused", function() end)
                        it("excluded", function() end)
                        itSKIP("skipped", function() end, "not ready")
                        describe("block", function()
                            it("excluded in block", function() end)
                        end)
                    ]],
                    { ForbidFocus = false, Parallel = mode.Parallel, PrintSkipped = true }
                )

                expect(outcome.Passed).to.equal(true)
                expect(outcome.Nodes["focused"].Status).to.equal("Success")
                expect(outcome.Nodes["excluded"].Reason).to.equal("excluded by focus")
                expect(outcome.Nodes["excluded in block"].Reason).to.equal("excluded by focus")
                expect(outcome.Nodes["skipped"].Reason).to.equal("not ready")
                expect(outcome.FocusExcludedCount).to.equal(2)
                expect(string.find(outcome.Output, "○ excluded (excluded by focus)", 1, true) ~= nil).to.equal(true)
            end)
        end)
    end
end
