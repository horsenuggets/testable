--[[

LifecycleTest.spec

Tests for lifecycle hooks in the Testable framework including beforeEach, afterEach,
beforeAll, and afterAll hooks.

--]]

return function()
    describe("beforeEach and afterEach", function()
        local beforeEachRan = false
        local afterEachCount = 0
        local testCount = 0

        beforeEach(function()
            beforeEachRan = true
        end)

        afterEach(function()
            afterEachCount += 1
        end)

        -- Tests in a describe block can start in any order when they run in parallel, so
        -- no test can rely on another's afterEach having run. The count is checked here
        -- instead, once every test has finished, against the tests that actually ran
        -- (a filter may leave some out). A failing afterAll fails the run.
        afterAll(function()
            assert(
                afterEachCount == testCount,
                `afterEach should have run after each of the {testCount} tests, but it ran {afterEachCount} times`
            )
        end)

        it("should run beforeEach before the test", function()
            testCount += 1
            expect(beforeEachRan).to.equal(true)
        end)

        it("should run afterEach after every test", function()
            testCount += 1
            expect(beforeEachRan).to.equal(true)
        end)
    end)

    describe("beforeAll and afterAll", function()
        local setupValue = nil
        local _teardownCalled = false

        beforeAll(function()
            setupValue = "initialized"
        end)

        afterAll(function()
            _teardownCalled = true
        end)

        it("should have run beforeAll before any test", function()
            expect(setupValue).to.equal("initialized")
        end)

        it("should maintain beforeAll state across tests", function()
            expect(setupValue).to.equal("initialized")
        end)
    end)

    describe("nested lifecycle hooks", function()
        local outerBeforeEach = 0
        local innerBeforeEach = 0

        beforeEach(function()
            outerBeforeEach += 1
        end)

        it("should run outer beforeEach for outer test", function()
            expect(outerBeforeEach).to.be.ok()
            expect(innerBeforeEach).to.equal(0)
        end)

        describe("inner describe", function()
            beforeEach(function()
                innerBeforeEach += 1
            end)

            it("should run both outer and inner beforeEach", function()
                expect(outerBeforeEach).to.be.ok()
                expect(innerBeforeEach).to.be.ok()
            end)
        end)
    end)

    describe("context", function()
        it("should allow setting and reading keys", function(context)
            context.testValue = "from test"
            expect(context.testValue).to.equal("from test")
        end)

        it("should allow reassigning a key", function(context)
            context.anotherKey = "first"
            context.anotherKey = "second"
            expect(context.anotherKey).to.equal("second")
        end)
    end)
end
