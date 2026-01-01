local Testable = require("../Source/Testable")
local process = require("@lune/process")

local TESTS = {
    { Name = "ExampleTest", Func = require("./Tests/ExampleTest") },
}

local function runTests()
    local _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

runTests()
