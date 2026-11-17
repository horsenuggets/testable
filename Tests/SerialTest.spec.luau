--[[

SerialTest.spec

Tests the Serial option of it blocks and describe blocks. A serial test runs with no
other test of the run executing at the same time, and a serial describe block keeps every
test under it from overlapping with anything else or with each other. The tests record
when each test starts and stops, then check which intervals overlap.

--]]

const Testable = require("../Source/Testable")
const task = require("@lune/task")
const TestPlanner = Testable.TestPlanner
const TestRunner = Testable.TestRunner
const afterAll, beforeAll, beforeEach = Testable.afterAll, Testable.beforeAll, Testable.beforeEach
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

-- Long enough that two tests that are allowed to overlap always do, short enough that
-- the whole spec stays fast.
const WINDOW = 0.04

const function runSuite(body: () -> ()): any
    return TestRunner.runPlan(TestPlanner.createPlan({
        { method = body, path = { "Suite" }, pathStringForSorting = "suite" },
    }))
end

const function planSuite(body: () -> ()): any
    return TestPlanner.createPlan({ { method = body, path = { "Suite" }, pathStringForSorting = "suite" } })
end

--[[
    Records the start and the end of a test into the shared log.
]]
const function recording(events: { string }, name: string): () -> ()
    return function()
        table.insert(events, `{name} enter`)
        task.wait(WINDOW)
        table.insert(events, `{name} exit`)
    end
end

const function indexOf(events: { string }, entry: string): number?
    for index, value in ipairs(events) do
        if value == entry then
            return index
        end
    end
    return nil
end

--[[
    Tells whether the recorded intervals of two tests overlap in time.
]]
const function overlaps(events: { string }, left: string, right: string): boolean
    const leftEnter, leftExit = indexOf(events, `{left} enter`), indexOf(events, `{left} exit`)
    const rightEnter, rightExit = indexOf(events, `{right} enter`), indexOf(events, `{right} exit`)
    assert(leftEnter ~= nil and leftExit ~= nil, `"{left}" has to record both its start and its end`)
    assert(rightEnter ~= nil and rightExit ~= nil, `"{right}" has to record both its start and its end`)

    return not (leftExit < rightEnter or rightExit < leftEnter)
end

return function()
    describe("Serial tests", function()
        it("run with no other test of the run executing at the same time", function()
            const events: { string } = {}

            runSuite(function()
                it("first", recording(events, "first"))
                it("serial", recording(events, "serial"), { Serial = true })
                it("last", recording(events, "last"))
            end)

            expect(overlaps(events, "serial", "first")).to.equal(false)
            expect(overlaps(events, "serial", "last")).to.equal(false)
        end)

        it("keep each other waiting even in different describe blocks", function()
            const events: { string } = {}

            runSuite(function()
                describe("one", function()
                    it("serial one", recording(events, "one"), { Serial = true })
                end)

                describe("two", function()
                    it("serial two", recording(events, "two"), { Serial = true })
                end)
            end)

            expect(overlaps(events, "one", "two")).to.equal(false)
        end)

        it("leave ordinary tests running alongside each other", function()
            const events: { string } = {}

            runSuite(function()
                it("first", recording(events, "first"))
                it("second", recording(events, "second"))
            end)

            expect(overlaps(events, "first", "second")).to.equal(true)
        end)

        it("make every test of a serial describe block wait for the others", function()
            const events: { string } = {}

            runSuite(function()
                describe("serial block", function()
                    it("first", recording(events, "first"))
                    it("second", recording(events, "second"))
                end, { Serial = true })
            end)

            expect(overlaps(events, "first", "second")).to.equal(false)
        end)

        it("keep a focused serial describe block serial", function()
            const events: { string } = {}

            runSuite(function()
                Testable.describeFOCUS("serial block", function()
                    it("first", recording(events, "first"))
                    it("second", recording(events, "second"))
                end, { Serial = true })
            end)

            expect(overlaps(events, "first", "second")).to.equal(false)
        end)

        it("keep the beforeAll and afterAll hooks of other blocks waiting", function()
            const events: { string } = {}

            runSuite(function()
                describe("one", function()
                    it("serial", recording(events, "serial"), { Serial = true })
                end)

                describe("two", function()
                    beforeAll(recording(events, "beforeAll"))
                    afterAll(recording(events, "afterAll"))
                    it("ordinary", function() end)
                end)
            end)

            expect(overlaps(events, "serial", "beforeAll")).to.equal(false)
            expect(overlaps(events, "serial", "afterAll")).to.equal(false)
        end)

        it("stay alone when a serial test turns Parallel off while it runs", function()
            const events: { string } = {}

            runSuite(function()
                describe("one", function()
                    it("serial", function()
                        Testable.configure({ Parallel = false })
                        recording(events, "serial")()
                        Testable.configure({ Parallel = true })
                    end, { Serial = true })
                end)

                describe("two", function()
                    it("ordinary", recording(events, "ordinary"))
                end)
            end)

            expect(overlaps(events, "serial", "ordinary")).to.equal(false)
        end, { Serial = true })

        it("are rejected when the option is not a boolean", function()
            const plan = planSuite(function()
                it("test", function() end, { Serial = "yes" :: any })
            end)

            expect(string.find(plan.children[1].loadError, "Serial option", 1, true) ~= nil).to.equal(true)
        end)

        it("are rejected on lifecycle hooks, which always run inside a test", function()
            const plan = planSuite(function()
                beforeEach(function() end, { Serial = true } :: any)
            end)

            expect(string.find(plan.children[1].loadError, "Serial", 1, true) ~= nil).to.equal(true)
        end)
    end)
end
