--[[
    The Context object implements a write-once key-value store. It also allows
    for a new Context object to inherit the entries from an existing one.
]]
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
        assert(index[key] == nil, string.format("Cannot reassign %s in context", tostring(key)))
        index[key] = value
    end

    return setmetatable({}, meta)
end

return Context
