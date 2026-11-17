--[[

TimeoutTest.spec

Tests for per-test time budgets. Covers the pure budget helpers, the Timeout configuration
option, and full runs where tests and hooks yield past their budget. The full runs happen
in a subprocess so each case gets its own Testable instance, in both the parallel and
sequential paths, and every budget is a fraction of a second to keep the suite fast.

--]]

const Subprocess = require("./Helpers/Subprocess")
const TestTimeout = require("../Source/Testable/TestTimeout")
const Testable = require("../Source/Testable")

const Config = Testable.Config

const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
const INVALID_BUDGETS: { any } = { 0, -1, 0 / 0, "1", true, {} }
const SCRIPT_HEADER = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")

    const startTime = os.clock()

    -- Bounds the script on its own, so that a regression in timeout handling fails the
    -- test instead of hanging the outer run.
    task.delay(5, function()
        print("WATCHDOG_FIRED")
        process.exit(2)
    end)

    const function busyWait(seconds: number)
        const busyStart = os.clock()
        while os.clock() - busyStart < seconds do
        end
    end

    const function finish(results: any, passed: boolean)
        print("PASSED:" .. tostring(passed))
        print("SUCCESS_COUNT:" .. results.successCount)
        print("FAIL_COUNT:" .. results.failureCount)
        print("RUNNING_FLAG:" .. tostring(_G.__TESTABLE_RUNNING_TEST__))
        print("FINISHED_QUICKLY:" .. tostring(os.clock() - startTime < 5))
        process.exit(if passed then 0 else 1)
    end
]]
const TEST_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ Parallel = %s, Timeout = 0.1 })

    local afterEachCount = 0
    local ranPastCancel = false

    const results, passed = Testable.run({
        {
            Name = "Timeouts",
            Func = function()
                afterEach(function()
                    afterEachCount += 1
                end)

                it("yields forever", function()
                    coroutine.yield()
                    ranPastCancel = true
                end)

                it("finishes in time", function()
                    task.wait(0.005)
                end)

                it("finishes without yielding", function() end)

                it("raises its budget", function()
                    task.wait(0.2)
                end, { Timeout = 5 })

                it("lowers its budget", function()
                    task.wait(0.05)
                    ranPastCancel = true
                end, { Timeout = 0.01 })

                it("turns its budget off", function()
                    task.wait(0.2)
                end, { Timeout = math.huge })
            end,
        },
    })

    -- Gives a test that was not really cancelled the time to keep running.
    task.wait(0.1)
    print("AFTER_EACH_COUNT:" .. afterEachCount)
    print("RAN_PAST_CANCEL:" .. tostring(ranPastCancel))
    finish(results, passed)
]]
const BUSY_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ Parallel = %s })

    local ranPastCancel = false

    const results, passed = Testable.run({
        {
            Name = "Busy",
            Func = function()
                it("overruns without yielding", function()
                    busyWait(0.03)
                end, { Timeout = 0.01 })

                it("works and then yields past its budget", function()
                    busyWait(0.03)
                    task.wait(0.03)
                    ranPastCancel = true
                end, { Timeout = 0.04 })

                it("fails on its own while over budget", function()
                    busyWait(0.03)
                    error("own failure")
                end, { Timeout = 0.02 })

                it("does quick work within its budget", function()
                    busyWait(0.002)
                end, { Timeout = 2 })
            end,
        },
    })

    task.wait(0.1)
    print("RAN_PAST_CANCEL:" .. tostring(ranPastCancel))
    finish(results, passed)
]]
const HOOK_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ Parallel = %s, Timeout = 0.05 })

    local reachedTestAfterStuckHook = false

    const results, passed = Testable.run({
        {
            Name = "Hooks",
            Func = function()
                describe("slow beforeAll and afterAll", function()
                    beforeAll(function()
                        task.wait(0.15)
                    end, { Timeout = 5 })

                    afterAll(function()
                        task.wait(0.15)
                    end, { Timeout = 5 })

                    it("is held to the budgets the hooks raised", function() end)
                end)

                describe("stuck beforeEach", function()
                    beforeEach(function()
                        coroutine.yield()
                    end)

                    it("fails before the test runs", function()
                        reachedTestAfterStuckHook = true
                    end)
                end)

                describe("stuck afterEach", function()
                    afterEach(function()
                        coroutine.yield()
                    end)

                    it("fails after the test runs", function() end)
                end)
            end,
        },
    })

    print("REACHED_TEST:" .. tostring(reachedTestAfterStuckHook))
    finish(results, passed)
]]
const DISABLED_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ Parallel = %s })

    const results, passed = Testable.run({
        {
            Name = "Disabled",
            Func = function()
                it("may take its time by default", function()
                    task.wait(0.15)
                end)

                it("still honors its own budget", function()
                    coroutine.yield()
                end, { Timeout = 0.02 })

                Testable.it("honors a budget set through the required it", function()
                    coroutine.yield()
                end, { Timeout = 0.03 })
            end,
        },
    })

    finish(results, passed)
]]
const INVALID_OPTIONS_SCRIPT_TEMPLATE = SCRIPT_HEADER
    .. [[
    Testable.configure({ Parallel = %s })

    const results, passed = Testable.run({
        {
            Name = "Invalid",
            Func = function()
                describe("negative budget", function()
                    it("is rejected", function() end, { Timeout = -1 })
                end)

                describe("options that are not a table", function()
                    it("is rejected too", function() end, 5)
                end)

                describe("valid sibling", function()
                    it("still runs", function() end, {})
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

return function()
    describe("TestTimeout.isValid()", function()
        it("accepts positive numbers and math.huge", function()
            for _, budget in { 0.001, 1, 30, math.huge } do
                expect(TestTimeout.isValid(budget)).to.equal(true)
            end
        end)

        it("rejects everything else", function()
            expect(TestTimeout.isValid(nil)).to.equal(false)
            for _, budget in INVALID_BUDGETS do
                expect(TestTimeout.isValid(budget)).to.equal(false)
            end
        end)
    end)

    describe("TestTimeout.resolve()", function()
        it("prefers the budget of the test in every combination", function()
            const candidates: { any } = { "none", 0.5, math.huge }
            for _, testCandidate in candidates do
                for _, configCandidate in candidates do
                    const testTimeout = if testCandidate == "none" then nil else testCandidate
                    const configTimeout = if configCandidate == "none" then nil else configCandidate
                    const budget, source = TestTimeout.resolve(testTimeout, configTimeout)

                    local expected = configTimeout
                    if testTimeout ~= nil then
                        expected = testTimeout
                    end

                    if expected == nil or expected == math.huge then
                        expect(budget).to.equal(nil)
                        expect(source).to.equal(nil)
                    else
                        expect(budget).to.equal(expected)
                        expect(source).to.equal(
                            if testTimeout ~= nil
                                then "the Timeout option of the test"
                                else "the Timeout configuration option"
                        )
                    end
                end
            end
        end)

        it("returns the same result when called twice", function()
            const firstBudget, firstSource = TestTimeout.resolve(2, 1)
            const secondBudget, secondSource = TestTimeout.resolve(2, 1)
            expect(firstBudget).to.equal(secondBudget)
            expect(firstSource).to.equal(secondSource)
        end)

        it("rejects invalid budgets", function()
            for _, budget in INVALID_BUDGETS do
                expect(function()
                    TestTimeout.resolve(budget, nil)
                end).to.throw()
                expect(function()
                    TestTimeout.resolve(nil, budget)
                end).to.throw()
            end
        end)
    end)

    describe("TestTimeout.formatMessage()", function()
        it("names the subject, the budget, and where the budget came from", function()
            expect(TestTimeout.formatMessage("The test", 0.05, "the Timeout configuration option")).to.equal(
                "The test timed out after exceeding its budget of 0.05 seconds, "
                    .. "set by the Timeout configuration option."
            )
        end)

        it("uses the singular for a budget of one second", function()
            const message = TestTimeout.formatMessage("The test", 1, "the Timeout option of the test")
            expect(contains(message, "budget of 1 second,")).to.equal(true)
        end)

        it("uses the plural for other budgets", function()
            const message = TestTimeout.formatMessage("The test", 2, "the Timeout option of the test")
            expect(contains(message, "budget of 2 seconds,")).to.equal(true)
        end)
    end)

    describe("Timeout configuration option", function()
        -- These tests never yield between changing the option and resetting it, so tests
        -- running in parallel never see the changed value.
        it("is off by default, can be set, and is cleared by a reset", function()
            expect(Config.Timeout).to.equal(nil)
            Testable.configure({ Timeout = 2.5 })
            const configured = Config.Timeout
            Testable.resetConfig()
            expect(configured).to.equal(2.5)
            expect(Config.Timeout).to.equal(nil)
        end)

        it("rejects invalid budgets and keeps the old value", function()
            for _, budget in INVALID_BUDGETS do
                expect(function()
                    Testable.configure({ Timeout = budget })
                end).to.throw("Timeout must be a positive number of seconds")
                expect(Config.Timeout).to.equal(nil)
            end
        end)
    end)

    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            it("fails tests that run out of time and lets the rest of the run finish", function()
                const ok, output = Subprocess.runScript(string.format(TEST_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "PASSED:false")).to.equal(true)
                expect(contains(output, "FINISHED_QUICKLY:true")).to.equal(true)
                expect(contains(output, "SUCCESS_COUNT:4")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
                expect(
                    countOccurrences(
                        output,
                        "The test timed out after exceeding its budget of 0.1 seconds, "
                            .. "set by the Timeout configuration option."
                    )
                ).to.equal(1)
                expect(
                    countOccurrences(
                        output,
                        "The test timed out after exceeding its budget of 0.01 seconds, "
                            .. "set by the Timeout option of the test."
                    )
                ).to.equal(1)
            end)

            it("cancels the timed out test and still runs afterEach for every test", function()
                const _, output = Subprocess.runScript(string.format(TEST_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(contains(output, "AFTER_EACH_COUNT:6")).to.equal(true)
                expect(contains(output, "RAN_PAST_CANCEL:false")).to.equal(true)
                expect(contains(output, "RUNNING_FLAG:nil")).to.equal(true)
            end)

            it("counts work done before the first yield against the budget", function()
                const ok, output = Subprocess.runScript(string.format(BUSY_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "WATCHDOG_FIRED")).to.equal(false)
                expect(contains(output, "SUCCESS_COUNT:1")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:3")).to.equal(true)
                expect(contains(output, "The test timed out after exceeding its budget of 0.01 seconds")).to.equal(true)
                expect(contains(output, "The test timed out after exceeding its budget of 0.04 seconds")).to.equal(true)
                expect(contains(output, "RAN_PAST_CANCEL:false")).to.equal(true)
                expect(contains(output, "own failure")).to.equal(true)
                expect(contains(output, "budget of 0.02 seconds")).to.equal(false)
            end)

            it(
                "gives beforeEach and afterEach hooks the budget and lets beforeAll and afterAll raise theirs",
                function()
                    const ok, output =
                        Subprocess.runScript(string.format(HOOK_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                    expect(ok).to.equal(false)
                    expect(contains(output, "FINISHED_QUICKLY:true")).to.equal(true)
                    expect(contains(output, "SUCCESS_COUNT:1")).to.equal(true)
                    expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
                    expect(contains(output, "REACHED_TEST:false")).to.equal(true)
                    expect(contains(output, "The beforeEach hook timed out after exceeding its budget of 0.05 seconds")).to.equal(
                        true
                    )
                    expect(contains(output, "The afterEach hook timed out after exceeding its budget of 0.05 seconds")).to.equal(
                        true
                    )
                    expect(contains(output, "The test timed out")).to.equal(false)
                    expect(contains(output, "RUNNING_FLAG:nil")).to.equal(true)
                end
            )

            it("leaves tests without a budget alone when the option is not configured", function()
                const ok, output =
                    Subprocess.runScript(string.format(DISABLED_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "SUCCESS_COUNT:1")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
                expect(countOccurrences(output, "timed out after exceeding its budget")).to.equal(2)
                expect(contains(output, "budget of 0.02 seconds, set by the Timeout option of the test.")).to.equal(
                    true
                )
                expect(contains(output, "budget of 0.03 seconds, set by the Timeout option of the test.")).to.equal(
                    true
                )
            end)

            it("reports invalid test options as planning errors", function()
                const ok, output =
                    Subprocess.runScript(string.format(INVALID_OPTIONS_SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(ok).to.equal(false)
                expect(contains(output, "SUCCESS_COUNT:1")).to.equal(true)
                expect(contains(output, 'The Timeout option of "is rejected" must be a positive number of seconds.')).to.equal(
                    true
                )
                expect(contains(output, 'The options of "is rejected too" must be a table, got number.')).to.equal(true)
            end)
        end)
    end
end
