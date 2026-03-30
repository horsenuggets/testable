--[[

ExampleTest.spec

A simple example test demonstrating basic Testable usage.

--]]

return function()
    describe("Example Test Suite", function()
        it("should pass this example test", function()
            expect(1 + 1).to.equal(2)
        end)
    end)
end
