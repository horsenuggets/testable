--[[

UnrequiredModule

A coverage fixture that no test ever requires, so its coverage has to come from compiling
it without running it.

--]]

const UnrequiredModule = {}

function UnrequiredModule.greet(name: string): string
    return `Hello, {name}.`
end

function UnrequiredModule.sum(values: { number }): number
    local total = 0
    for _, value in values do
        total += value
    end
    return total
end

return UnrequiredModule
