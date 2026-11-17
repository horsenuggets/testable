--[[

TestScopeTest.spec

Tests for the per-coroutine scope stack that lets the requirable spec API find the
describe block being collected or the test being run.

--]]

const TestScope = require("../Source/Testable/TestScope")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const function newScope(): TestScope.RunScope
    return {
        ExpectationContext = {},
        Fail = function() end,
        Finished = false,
    }
end

--[[
    Runs the callback on a fresh coroutine, which starts without any scope, and returns
    what the callback returned.
]]
const function onFreshCoroutine<Returns...>(callback: () -> Returns...): Returns...
    return coroutine.wrap(callback)()
end

return function()
    describe("a coroutine without frames", function()
        it("should have no collecting node and no run scope", function()
            const node, scope = onFreshCoroutine(function()
                return TestScope.getCollectingNode(), TestScope.getRunScope()
            end)

            expect(node).to.equal(nil)
            expect(scope).to.equal(nil)
        end)

        it("should reject an exit without a matching enter", function()
            const ok, message = onFreshCoroutine(function()
                return pcall(TestScope.exit)
            end)

            expect(ok).to.equal(false)
            expect(string.find(tostring(message), "without a matching enter", 1, true)).to.be.ok()
        end)
    end)

    describe("the frame stack", function()
        it("should report only the innermost frame", function()
            const node = {}
            const scope = newScope()
            const seen = onFreshCoroutine(function()
                const steps = {}

                TestScope.enterRun(scope)
                table.insert(steps, { Node = TestScope.getCollectingNode(), Scope = TestScope.getRunScope() })

                -- A running test that plans a nested set of tests is collecting, not running.
                TestScope.enterCollection(node)
                table.insert(steps, { Node = TestScope.getCollectingNode(), Scope = TestScope.getRunScope() })

                TestScope.exit()
                table.insert(steps, { Node = TestScope.getCollectingNode(), Scope = TestScope.getRunScope() })

                TestScope.exit()
                table.insert(steps, { Node = TestScope.getCollectingNode(), Scope = TestScope.getRunScope() })

                return steps
            end)

            expect(seen[1].Node).to.equal(nil)
            expect(seen[1].Scope).to.equal(scope)
            expect(seen[2].Node).to.equal(node)
            expect(seen[2].Scope).to.equal(nil)
            expect(seen[3].Node).to.equal(nil)
            expect(seen[3].Scope).to.equal(scope)
            expect(seen[4].Node).to.equal(nil)
            expect(seen[4].Scope).to.equal(nil)
        end)

        it("should keep the frames of different coroutines apart", function()
            const first = newScope()
            const second = newScope()
            const seen = {}

            const function hold(name: string, scope: TestScope.RunScope): thread
                const thread = coroutine.create(function()
                    TestScope.enterRun(scope)
                    coroutine.yield()
                    seen[name] = TestScope.getRunScope()
                    TestScope.exit()
                end)
                coroutine.resume(thread)
                return thread
            end

            const firstThread = hold("First", first)
            const secondThread = hold("Second", second)

            -- Neither coroutine's scope leaks into this one or into the other.
            expect(TestScope.getRunScope()).never.to.equal(first)
            expect(TestScope.getRunScope()).never.to.equal(second)

            coroutine.resume(firstThread)
            coroutine.resume(secondThread)

            expect(seen.First).to.equal(first)
            expect(seen.Second).to.equal(second)
        end)

        it("should keep a scope across yields of its coroutine", function()
            const scope = newScope()
            local seen = nil

            const thread = coroutine.create(function()
                TestScope.enterRun(scope)
                coroutine.yield()
                coroutine.yield()
                seen = TestScope.getRunScope()
                TestScope.exit()
            end)

            coroutine.resume(thread)
            coroutine.resume(thread)
            coroutine.resume(thread)

            expect(seen).to.equal(scope)
        end)
    end)
end
