--[[

HelperModule

A second test fixture for coverage tests. Used to verify deduplication
when overlapping coverage roots are provided.

--]]

local HelperModule = {}

function HelperModule.greet(name: string): string
    return `Hello, {name}!`
end

function HelperModule.shout(text: string): string
    return string.upper(text)
end

return HelperModule
