--[[

LegacyGlobalsTest.spec

Pins the original way of writing specs, where Testable injects describe, it, expect, and
the rest into the spec function as globals. Downstream projects depend on it, so this spec
deliberately requires nothing from Testable and must keep passing unchanged.

--]]

return function()
    describe("injected globals", function()
        local beforeAllRuns = 0
        local beforeEachRuns = 0

        beforeAll(function()
            beforeAllRuns += 1
        end)

        beforeEach(function()
            beforeEachRuns += 1
        end)

        afterEach(function(context)
            expect(context.Ran).to.equal(true)
        end)

        afterAll(function()
            expect(beforeAllRuns).to.equal(1)
            expect(beforeEachRuns).to.equal(4)
        end)

        it("should provide the declaring functions", function(context)
            context.Ran = true

            for _, declare in { describe, fdescribe, fit, it, xdescribe, xit } do
                expect(declare).to.be.a("function")
            end
            for _, hook in { afterAll, afterEach, beforeAll, beforeEach } do
                expect(hook).to.be.a("function")
            end
        end)

        it("should provide expect with the built-in matchers", function(context)
            context.Ran = true

            expect(1 + 1).to.equal(2)
            expect("text").to.be.a("string")
            expect(nil).never.to.be.ok()
            expect(function()
                expect(1).to.equal(2)
            end).to.throw()
        end)

        it("should provide expect.extend and fail", function(context)
            context.Ran = true

            expect.extend({
                beLegacy = function(value)
                    return { message = "Expected the legacy value", pass = value == "legacy" }
                end,
            })

            expect("legacy").to.beLegacy()
            expect(fail).to.be.a("function")
        end)

        it("should run hooks before the test", function(context)
            context.Ran = true

            expect(beforeAllRuns).to.equal(1)
            expect(beforeEachRuns >= 1).to.equal(true)
        end)

        xit("should skip tests declared with xit", function()
            error("A skipped test ran.")
        end)
    end)

    describe("nested blocks", function()
        describe("inner block", function()
            it("should inherit the globals", function()
                expect(describe).to.be.a("function")
                expect(expect).to.be.ok()
            end)
        end)
    end)
end
