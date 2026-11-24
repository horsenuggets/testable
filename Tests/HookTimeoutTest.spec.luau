--[[

HookTimeoutTest.spec

Tests for the time budgets of lifecycle hooks. Covers the pure helper that picks a hook's
budget, the lookup of a budget that a hook set on itself, and full runs where beforeAll
and afterAll hooks yield past their budget. The full runs happen in a subprocess so each
case gets its own Testable instance, in both the parallel and sequential paths, and every
budget is a fraction of a second to keep the suite fast.

--]]

const LifecycleHooks = require("../Source/Testable/LifecycleHooks")
const Subprocess = require("./Helpers/Subprocess")
const TestEnum = require("../Source/Testable/TestEnum")
const TestTimeout = require("../Source/Testable/TestTimeout")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const CONFIG_SOURCE = "the Timeout configuration option"
const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false }
}
const HOOK_SOURCE = "the Timeout option of the hook"
const INVALID_BUDGETS: { any } = { 0, -1, 0 / 0, "1", true, {} }
const SCRIPT_HEADER = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")
    const afterAll, afterEach, beforeAll, beforeEach =
        Testable.afterAll, Testable.afterEach, Testable.beforeAll, Testable.beforeEach
    const describe, it = Testable.describe, Testable.it

    const startTime = os.clock()

    -- Bounds the script on its own, so that a regression in timeout handling fails the
    -- test instead of hanging the outer run.
    task.delay(5, function()
        print("WATCHDOG_FIRED")
        process.exit(2)
    end)

    const function finish(results: any, passed: boolean)
        results:visitAllNodes(function(node)
            if node.planNode.type == "It" then
                print(`NODE|{node.planNode.phrase}|{node.status}`)
            end
        end)
        print("PASSED:" .. tostring(passed))
        print("SUCCESS_COUNT:" .. results.successCount)
        print("FAIL_COUNT:" .. results.failureCount)
        print("RUNNING_FLAG:" .. tostring(_G.__TESTABLE_RUNNING_TEST__))
        print("FINISHED_QUICKLY:" .. tostring(os.clock() - startTime < 5))
        process.exit(if passed then 0 else 1)
    end
]]
const STUCK_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ InjectGlobals = false, Parallel = %s, Timeout = 0.1 })

    local ranPastCancel = false
    local reachedTestAfterStuckHook = false

    const results, passed = Testable.run({
        {
            Name = "Hooks",
            Func = function()
                describe("stuck beforeAll", function()
                    beforeAll(function()
                        coroutine.yield()
                        ranPastCancel = true
                    end)

                    it("never runs", function()
                        reachedTestAfterStuckHook = true
                    end)
                end)

                describe("stuck afterAll", function()
                    afterAll(function()
                        coroutine.yield()
                        ranPastCancel = true
                    end)

                    it("runs before the hook", function() end)
                end)

                describe("quick hooks", function()
                    beforeAll(function()
                        task.wait(0.005)
                    end)

                    afterAll(function() end)

                    it("is left alone", function() end)
                end)
            end,
        },
    })

    -- Gives a hook that was not really cancelled the time to keep running.
    task.wait(0.1)
    print("RAN_PAST_CANCEL:" .. tostring(ranPastCancel))
    print("REACHED_TEST:" .. tostring(reachedTestAfterStuckHook))
    finish(results, passed)
]]
const OWN_BUDGET_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ InjectGlobals = false, Parallel = %s, Timeout = 0.05 })

    const results, passed = Testable.run({
        {
            Name = "Budgets",
            Func = function()
                describe("raised budgets", function()
                    beforeAll(function()
                        task.wait(0.15)
                    end, { Timeout = 5 })

                    afterAll(function()
                        task.wait(0.15)
                    end, { Timeout = math.huge })

                    beforeEach(function()
                        task.wait(0.1)
                    end, { Timeout = 5 })

                    afterEach(function()
                        task.wait(0.1)
                    end, { Timeout = math.huge })

                    it("passes after slow hooks", function() end)
                end)

                describe("lowered beforeAll", function()
                    beforeAll(function()
                        task.wait(0.5)
                    end, { Timeout = 0.01 })

                    it("never runs", function() end)
                end)

                describe("lowered afterEach", function()
                    afterEach(function()
                        task.wait(0.5)
                    end, { Timeout = 0.02 })

                    it("fails after it ran", function() end)
                end)
            end,
        },
    })

    finish(results, passed)
]]
const UNCONFIGURED_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ InjectGlobals = false, Parallel = %s })

    const results, passed = Testable.run({
        {
            Name = "Unconfigured",
            Func = function()
                describe("slow hooks", function()
                    beforeAll(function()
                        task.wait(0.15)
                    end)

                    afterAll(function()
                        task.wait(0.15)
                    end)

                    it("may take their time by default", function() end)
                end)

                describe("own budget", function()
                    afterAll(function()
                        coroutine.yield()
                    end, { Timeout = 0.03 })

                    it("still passes on its own", function() end)
                end)
            end,
        },
    })

    finish(results, passed)
]]
const INVALID_OPTIONS_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ InjectGlobals = false, Parallel = %s })

    const results, passed = Testable.run({
        {
            Name = "Invalid",
            Func = function()
                describe("negative budget", function()
                    beforeAll(function() end, { Timeout = -1 })
                    it("is rejected", function() end)
                end)

                describe("options that are not a table", function()
                    afterEach(function() end, 5)
                    it("is rejected too", function() end)
                end)

                describe("valid sibling", function()
                    beforeAll(function() end, {})
                    it("still runs", function() end)
                end)
            end,
        },
    })

    finish(results, passed)
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

const function countOccurrences(output: string, text: string): number
    local count = 0
    local position = 1
    while true do
        const first, last = string.find(output, text, position, true)
        if first == nil or last == nil then
            return count
        end
        count += 1
        position = last + 1
    end
end

const function hookNode(nodeType: string, callback: () -> (), timeout: number?): any
    return { callback = callback, timeout = timeout, type = nodeType }
end

return function()
    describe("TestTimeout.resolveHook()", function()
        it("prefers the budget of the hook in every combination", function()
            const candidates: { any } = { "none", 0.5, math.huge }
            for _, hookCandidate in candidates do
                for _, inheritedCandidate in { "none", 0.25 } :: { any } do
                    const hookTimeout = if hookCandidate == "none" then nil else hookCandidate
                    const inheritedBudget = if inheritedCandidate == "none" then nil else inheritedCandidate
                    const inheritedSource = if inheritedBudget ~= nil then CONFIG_SOURCE else nil
                    const budget, source = TestTimeout.resolveHook(hookTimeout, inheritedBudget, inheritedSource)

                    if hookTimeout == math.huge then
                        expect(budget).to.equal(nil)
                        expect(source).to.equal(nil)
                    elseif hookTimeout ~= nil then
                        expect(budget).to.equal(hookTimeout)
                        expect(source).to.equal(HOOK_SOURCE)
                    else
                        expect(budget).to.equal(inheritedBudget)
                        expect(source).to.equal(inheritedSource)
                    end
                end
            end
        end)

        it("returns the same result when called twice", function()
            const firstBudget, firstSource = TestTimeout.resolveHook(2, 1, CONFIG_SOURCE)
            const secondBudget, secondSource = TestTimeout.resolveHook(2, 1, CONFIG_SOURCE)
            expect(firstBudget).to.equal(secondBudget)
            expect(firstSource).to.equal(secondSource)
        end)

        it("rejects invalid budgets and a budget without its source", function()
            for _, budget in INVALID_BUDGETS do
                expect(function()
                    TestTimeout.resolveHook(budget, nil, nil)
                end).to.throw()
                expect(function()
                    TestTimeout.resolveHook(nil, budget, CONFIG_SOURCE)
                end).to.throw()
            end
            expect(function()
                TestTimeout.resolveHook(nil, 1, nil)
            end).to.throw("inheritedBudget and inheritedSource must be given together")
            expect(function()
                TestTimeout.resolveHook(nil, nil, CONFIG_SOURCE)
            end).to.throw("inheritedBudget and inheritedSource must be given together")
        end)
    end)

    describe("LifecycleHooks hook budgets", function()
        -- Lists the budgets of the given hooks in order, with false for a hook that set
        -- none, so the arrays have no holes.
        const function budgets(hooks: { LifecycleHooks.Hook }): { number | boolean }
            const result = {}
            for _, hook in hooks do
                table.insert(result, if hook.timeout == nil then false else hook.timeout)
            end
            return result
        end

        it("carries the budget a hook set on itself and nothing for the others", function()
            const hooks = LifecycleHooks.new()
            hooks:pushHooksFrom({
                children = {
                    hookNode(TestEnum.NodeType.BeforeAll, function() end, 3),
                    hookNode(TestEnum.NodeType.BeforeAll, function() end, nil)
                }
            })

            expect(budgets(hooks:getBeforeAllHooks())).to.deepEqual({ 3, false })
        end)

        it("keeps every registration of the same function apart", function()
            const shared = function() end
            const hooks = LifecycleHooks.new()
            hooks:pushHooksFrom({
                children = {
                    hookNode(TestEnum.NodeType.BeforeAll, shared, 1),
                    hookNode(TestEnum.NodeType.BeforeAll, shared, 7),
                    hookNode(TestEnum.NodeType.AfterEach, shared, 2),
                    hookNode(TestEnum.NodeType.BeforeEach, shared, nil)
                }
            })

            expect(budgets(hooks:getBeforeAllHooks())).to.deepEqual({ 1, 7 })
            expect(budgets(hooks:getAfterEachHooks())).to.deepEqual({ 2 })
            expect(budgets(hooks:getBeforeEachHooks())).to.deepEqual({ false })
            expect(budgets(hooks:getAfterAllHooks())).to.deepEqual({})
        end)

        it("keeps the budget of each level when nested blocks reuse a function", function()
            const shared = function() end
            const hooks = LifecycleHooks.new()
            hooks:pushHooksFrom({ children = { hookNode(TestEnum.NodeType.BeforeEach, shared, 4) } })
            hooks:pushHooksFrom({ children = { hookNode(TestEnum.NodeType.BeforeEach, shared, 5) } })
            const forked = hooks:fork()

            expect(budgets(hooks:getBeforeEachHooks())).to.deepEqual({ 4, 5 })
            expect(budgets(hooks:getAfterEachHooks())).to.deepEqual({})

            hooks:popHooks()
            expect(budgets(hooks:getBeforeEachHooks())).to.deepEqual({ 4 })
            expect(budgets(forked:getBeforeEachHooks())).to.deepEqual({ 4, 5 })
        end)

        it("ignores nodes that are not hooks", function()
            const hooks = LifecycleHooks.new()
            hooks:pushHooksFrom({ children = { hookNode(TestEnum.NodeType.It, function() end, 9) } })

            expect(budgets(hooks:getBeforeAllHooks())).to.deepEqual({})
            expect(budgets(hooks:getBeforeEachHooks())).to.deepEqual({})
        end)
    end)

    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            it("fails a stuck beforeAll or afterAll hook and lets the rest of the run finish", function()
                const ok, output = Subprocess.runScript(string.format(STUCK_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "WATCHDOG_FIRED")).to.equal(false)
                expect(contains(output, "FINISHED_QUICKLY:true")).to.equal(true)
                expect(contains(output, "PASSED:false")).to.equal(true)
                expect(contains(output, "SUCCESS_COUNT:2")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
                expect(
                    countOccurrences(
                        output,
                        `The beforeAll hook timed out after exceeding its budget of 0.1 seconds, set by {CONFIG_SOURCE}.`
                    )
                ).to.equal(1)
                expect(
                    countOccurrences(
                        output,
                        `The afterAll hook timed out after exceeding its budget of 0.1 seconds, set by {CONFIG_SOURCE}.`
                    )
                ).to.equal(1)
                expect(contains(output, "NODE|runs before the hook|Success")).to.equal(true)
                expect(contains(output, "NODE|is left alone|Success")).to.equal(true)
            end)

            it("cancels the stuck hook and never runs the tests behind a stuck beforeAll", function()
                const _, output = Subprocess.runScript(string.format(STUCK_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(contains(output, "RAN_PAST_CANCEL:false")).to.equal(true)
                expect(contains(output, "REACHED_TEST:false")).to.equal(true)
                expect(contains(output, "NODE|never runs|Success")).to.equal(false)
                expect(contains(output, "RUNNING_FLAG:nil")).to.equal(true)
            end)

            it("lets every hook raise, lower, or turn off its own budget", function()
                const ok, output =
                    Subprocess.runScript(string.format(OWN_BUDGET_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "WATCHDOG_FIRED")).to.equal(false)
                expect(contains(output, "NODE|passes after slow hooks|Success")).to.equal(true)
                expect(contains(output, "SUCCESS_COUNT:1")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
                expect(
                    contains(
                        output,
                        `The beforeAll hook timed out after exceeding its budget of 0.01 seconds, set by {HOOK_SOURCE}.`
                    )
                ).to.equal(true)
                expect(
                    contains(
                        output,
                        `The afterEach hook timed out after exceeding its budget of 0.02 seconds, set by {HOOK_SOURCE}.`
                    )
                ).to.equal(true)
                expect(countOccurrences(output, "timed out after exceeding its budget")).to.equal(2)
            end)

            it("leaves hooks without a budget alone when the option is not configured", function()
                const ok, output =
                    Subprocess.runScript(string.format(UNCONFIGURED_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "NODE|may take their time by default|Success")).to.equal(true)
                expect(contains(output, "NODE|still passes on its own|Success")).to.equal(true)
                expect(contains(output, "SUCCESS_COUNT:2")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:1")).to.equal(true)
                expect(countOccurrences(output, "timed out after exceeding its budget")).to.equal(1)
                expect(
                    contains(
                        output,
                        `The afterAll hook timed out after exceeding its budget of 0.03 seconds, set by {HOOK_SOURCE}.`
                    )
                ).to.equal(true)
            end)

            it("reports invalid hook options as planning errors", function()
                const ok, output =
                    Subprocess.runScript(string.format(INVALID_OPTIONS_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "NODE|still runs|Success")).to.equal(true)
                expect(contains(output, "SUCCESS_COUNT:1")).to.equal(true)
                expect(contains(output, 'The Timeout option of "beforeAll" must be a positive number of seconds.')).to.equal(
                    true
                )
                expect(contains(output, 'The options of "afterEach" must be a table, got number.')).to.equal(true)
            end)
        end)
    end
end
