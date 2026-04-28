#!/usr/bin/env -S lune run

--[[

RunTests

Discovers and executes all test suites from the Tests directory. Exits with the
appropriate status code.

--]]

local process = require("@lune/process")

local Dotenv = require("./Helpers/Dotenv")
local Testable = require("../Source/Testable")

Dotenv.load()

local function runTests()
    local _, passed = Testable.run(script.Parent.Parent.Tests)
    process.exit(if passed then 0 else 1)
end

runTests()
