--[[

ExpectationTest

Tests for all expectation matchers in the Testable framework, including equality checks,
type assertions, nil checks, numeric comparisons, error throwing, and negation.

--]]

return function()
    describe("expect().to.equal()", function()
        it("should pass when values are equal", function()
            expect(5).to.equal(5)
            expect("hello").to.equal("hello")
            expect(true).to.equal(true)
            expect(nil).to.equal(nil)
        end)

        it("should fail when values are not equal", function()
            expect(function()
                expect(5).to.equal(6)
            end).to.throw()
        end)

        it("should handle table references", function()
            local t = { 1, 2, 3 }
            expect(t).to.equal(t)
        end)

        it("should fail for different tables with same content", function()
            expect(function()
                expect({ 1, 2, 3 }).to.equal({ 1, 2, 3 })
            end).to.throw()
        end)
    end)

    describe("expect().to.be.ok()", function()
        it("should pass for non-nil values", function()
            expect(true).to.be.ok()
            expect(false).to.be.ok()
            expect(0).to.be.ok()
            expect("").to.be.ok()
            expect({}).to.be.ok()
        end)

        it("should fail for nil", function()
            expect(function()
                expect(nil).to.be.ok()
            end).to.throw()
        end)
    end)

    describe("expect().to.be.a() / expect().to.be.an()", function()
        it("should pass for correct types", function()
            expect(5).to.be.a("number")
            expect("hello").to.be.a("string")
            expect(true).to.be.a("boolean")
            expect({}).to.be.a("table")
            expect(function() end).to.be.a("function")
        end)

        it("should work with 'an' alias", function()
            expect({}).to.be.an("table")
        end)

        it("should fail for incorrect types", function()
            expect(function()
                expect(5).to.be.a("string")
            end).to.throw()
        end)
    end)

    describe("expect().to.be.near()", function()
        it("should pass for values within default tolerance", function()
            expect(1.0).to.be.near(1.0)
            expect(1.0).to.be.near(1.0 + 1e-8)
        end)

        it("should pass for values within custom tolerance", function()
            expect(1.0).to.be.near(1.5, 0.5)
            expect(10).to.be.near(11, 2)
        end)

        it("should fail for values outside tolerance", function()
            expect(function()
                expect(1.0).to.be.near(2.0)
            end).to.throw()
        end)

        it("should fail for values outside custom tolerance", function()
            expect(function()
                expect(1.0).to.be.near(2.0, 0.5)
            end).to.throw()
        end)
    end)

    describe("expect().to.throw()", function()
        it("should pass when function throws", function()
            expect(function()
                error("test error")
            end).to.throw()
        end)

        it("should fail when function does not throw", function()
            expect(function()
                expect(function()
                    -- does nothing
                end).to.throw()
            end).to.throw()
        end)

        it("should pass when error contains substring", function()
            expect(function()
                error("specific error message")
            end).to.throw("specific")
        end)

        it("should fail when error does not contain substring", function()
            expect(function()
                expect(function()
                    error("specific error message")
                end).to.throw("different")
            end).to.throw()
        end)
    end)

    describe("negation with .never", function()
        it("should negate equal", function()
            expect(5).never.to.equal(6)
        end)

        it("should fail negated equal when values match", function()
            expect(function()
                expect(5).never.to.equal(5)
            end).to.throw()
        end)

        it("should negate ok", function()
            expect(nil).never.to.be.ok()
        end)

        it("should fail negated ok for non-nil", function()
            expect(function()
                expect(true).never.to.be.ok()
            end).to.throw()
        end)

        it("should negate type check", function()
            expect(5).never.to.be.a("string")
        end)

        it("should negate near", function()
            expect(1.0).never.to.be.near(100.0)
        end)

        it("should negate throw", function()
            expect(function()
                -- does nothing
            end).never.to.throw()
        end)

        it("should negate throw with substring", function()
            expect(function()
                error("actual error")
            end).never.to.throw("different")
        end)
    end)

    describe("chaining readability keywords", function()
        it("should allow 'to' chaining", function()
            expect(5).to.equal(5)
        end)

        it("should allow 'be' chaining", function()
            expect(5).to.be.a("number")
        end)

        it("should allow 'been' chaining", function()
            expect(5).to.been.a("number")
        end)

        it("should allow 'have' chaining", function()
            expect(5).to.have.been.a("number")
        end)

        it("should allow 'was' chaining", function()
            expect(5).was.a("number")
        end)

        it("should allow 'at' chaining", function()
            expect(5).at.been.a("number")
        end)
    end)

    describe("expectation chaining", function()
        it("should allow multiple assertions on same value", function()
            expect(5).to.be.a("number").to.equal(5).to.be.ok()
        end)

        it("should reset negation after each assertion", function()
            expect(5).never.to.equal(6).to.equal(5)
        end)
    end)
end
