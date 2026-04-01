--[[

SampleModule

A simple module used as a test fixture for coverage tests. Contains
exported functions and local helper functions to verify that
file-level coverage captures both.

--]]

local function helper(value: number): number
    return value * 2
end

local SampleModule = {}

function SampleModule.add(a: number, b: number): number
    return a + b
end

function SampleModule.subtract(a: number, b: number): number
    return a - b
end

function SampleModule.double(value: number): number
    return helper(value)
end

function SampleModule.unused()
    return "never called"
end

return SampleModule
