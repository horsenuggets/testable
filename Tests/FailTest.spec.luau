--[[

FailTest

Tests for the fail() function in the Testable framework.

--]]

return function()
    describe("fail() function", function()
        it("should be available in test environment", function()
            expect(fail).to.be.a("function")
        end)

        -- Note: We can't easily test that fail() actually fails a test from within
        -- a test, because calling fail() would fail the current test. The following
        -- tests verify fail() exists and is callable.
    end)
end
