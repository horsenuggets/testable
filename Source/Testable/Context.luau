--[[

Context

The Context object implements a key-value store for passing data between lifecycle hooks
and tests. It also allows for a new Context object to inherit the entries from an existing
one.

--]]
local Context = {}

--[[
    Creates a new Context, optionally inheriting from a parent Context.

    @param parent - Optional parent Context to inherit key-value pairs from
    @return A new Context object
]]
function Context.new(parent: any?): any
    local meta = {}
    local index = {}
    meta.__index = index

    if parent then
        for key, value in pairs(getmetatable(parent).__index) do
            index[key] = value
        end
    end

    function meta.__newindex(_obj, key, value)
        index[key] = value
    end

    return setmetatable({}, meta)
end

return Context
