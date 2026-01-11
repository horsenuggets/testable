--[[

LifecycleTest

Tests for lifecycle hooks in the Testable framework including beforeEach, afterEach,
beforeAll, and afterAll hooks.

--]]

return function()
    describe("beforeEach and afterEach", function()
        local counter = 0

        beforeEach(function()
            counter += 1
        end)

        afterEach(function()
            counter += 10
        end)

        it("should run beforeEach before first test", function()
            expect(counter % 10).to.equal(1)
        end)

        it("should run beforeEach and afterEach between tests", function()
            -- After first test: counter = 1 + 10 = 11
            -- Before second test: counter = 11 + 1 = 12
            expect(counter % 10).to.equal(2)
        end)

        it("should continue running hooks for third test", function()
            -- After second test: counter = 12 + 10 = 22
            -- Before third test: counter = 22 + 1 = 23
            expect(counter % 10).to.equal(3)
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

    describe("context passing to beforeEach", function()
        beforeEach(function(context)
            context.setupValue = "from beforeEach"
        end)

        it("should receive context set in beforeEach", function(context)
            expect(context.setupValue).to.equal("from beforeEach")
        end)
    end)

    describe("context passing to test", function()
        it("should allow setting keys in test", function(context)
            context.testValue = "from test"
            expect(context.testValue).to.equal("from test")
        end)
    end)

    describe("context write-once behavior", function()
        it("should allow setting a key once", function(context)
            context.myKey = "value"
            expect(context.myKey).to.equal("value")
        end)

        it("should error when reassigning a key", function(context)
            context.anotherKey = "first"
            expect(function()
                context.anotherKey = "second"
            end).to.throw("Cannot reassign")
        end)
    end)

    describe("context inheritance in nested describes", function()
        beforeEach(function(context)
            context.outer = "outer value"
        end)

        describe("nested context", function()
            beforeEach(function(context)
                context.inner = "inner value"
            end)

            it("should have both outer and inner context values", function(context)
                expect(context.outer).to.equal("outer value")
                expect(context.inner).to.equal("inner value")
            end)
        end)
    end)
end
