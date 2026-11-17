--[[

ToolError

An identifiable error that Testable throws when a run can't produce a meaningful verdict,
such as a filter that selects no tests, a coverage threshold with nothing measured, or
configuration options that are not valid. These are distinct from test failures, which are reported through the "passed" return
value of a run instead of being thrown.

--]]

export type Kind = "EmptyCoverage" | "EmptyFilter" | "InvalidConfiguration" | "InvalidReporters"

export type ToolError = {
    Kind: Kind,
    Message: string,
}

const KINDS = {
    EmptyCoverage = "EmptyCoverage" :: Kind,
    EmptyFilter = "EmptyFilter" :: Kind,
    InvalidConfiguration = "InvalidConfiguration" :: Kind,
    InvalidReporters = "InvalidReporters" :: Kind,
}

const ToolError = {}

const metatable = {
    __tostring = function(self: ToolError): string
        return self.Message
    end,
}

--[[
    Creates a tool error. Throw it with error() so callers can catch it with pcall and
    recognize it with ToolError.is.

    @param kind - Which tool error this is, one of ToolError.Kind
    @param message - A complete sentence describing what went wrong
    @return The tool error object
]]
function ToolError.new(kind: Kind, message: string): ToolError
    assert(KINDS[kind] ~= nil, "kind must be one of ToolError.Kind")
    assert(type(message) == "string", "message must be a string")

    return setmetatable({ Kind = kind, Message = message }, metatable) :: any
end

--[[
    Tells whether a caught error value is a tool error.

    @param value - Any value, usually the second result of pcall
    @return True if the value was created by ToolError.new
]]
function ToolError.is(value: any): boolean
    return type(value) == "table" and getmetatable(value) == metatable
end

ToolError.Kind = KINDS

return ToolError
