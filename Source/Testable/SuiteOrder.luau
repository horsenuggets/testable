--[[

SuiteOrder

Validates preferred spec identities and orders discovered modules without changing them.
Unlisted specs remain alphabetical, and preferences never change suite membership.

--]]

const SuiteOrder = {}

function SuiteOrder.problem(order: any): string?
    if type(order) ~= "table" then
        return "SuiteOrder must be an array"
    end
    const seen = {}
    local count = 0
    for index, name in order do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #order then
            return "SuiteOrder must be a dense array"
        end
        if type(name) ~= "string" or name:find("%S") == nil then
            return "SuiteOrder entries must be non-empty strings"
        end
        if seen[name] then
            return "SuiteOrder entries must be unique"
        end
        seen[name] = true
        count += 1
    end
    return if count == #order then nil else "SuiteOrder must be a dense array"
end

const function identity(path: { string }): string
    assert(type(path) == "table")
    const names = {}
    for index = #path, 1, -1 do
        table.insert(names, path[index])
    end
    return table.concat(names, " ")
end

function SuiteOrder.modules(modules: { any }, order: { string }?): { any }
    assert(type(modules) == "table")
    if order ~= nil then
        const problem = SuiteOrder.problem(order)
        assert(problem == nil, problem)
    end
    const priorities = {}
    if order ~= nil then
        for index, name in order do
            priorities[name] = index
        end
    end
    const ordered = table.clone(modules)
    table.sort(ordered, function(left, right)
        const leftPriority = priorities[identity(left.path)] or math.huge
        const rightPriority = priorities[identity(right.path)] or math.huge
        return if leftPriority == rightPriority
            then left.pathStringForSorting < right.pathStringForSorting
            else leftPriority < rightPriority
    end)
    return ordered
end

return SuiteOrder
