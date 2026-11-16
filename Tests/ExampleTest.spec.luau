--[[

ExampleTest.spec

A simple example test demonstrating basic Testable usage.

--]]

const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

return function()
    describe("Example Test Suite", function()
        it("should pass this example test", function()
            expect(1 + 1).to.equal(2)
        end)
    end)
end
