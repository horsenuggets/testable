--!nocheck

--[[

ExpectationContext

Manages the expectation context for tests, allowing custom matchers to be extended and
providing the expect() API for test assertions.

--]]

const Expectation = require("./Expectation")
const checkMatcherNameCollisions = Expectation.checkMatcherNameCollisions

const function copy(t)
    const result = {}

    for key, value in pairs(t) do
        result[key] = value
    end

    return result
end

const ExpectationContext = {}
ExpectationContext.__index = ExpectationContext

function ExpectationContext.new(parent)
    const self = {
        _extensions = parent and copy(parent._extensions) or {},
    }

    return setmetatable(self, ExpectationContext)
end

function ExpectationContext:startExpectationChain(...)
    const expectation = Expectation.new(...):extend(self._extensions)
    expectation._snapshotScope = self._snapshotScope

    return expectation
end

--[[
    Ties this context to the test it belongs to, so that snapshot assertions made through
    it know which test is running. Each test has its own context, so the first binding
    stays for the whole test and its hooks.
]]
function ExpectationContext:bindSnapshotScope(snapshots, planNode)
    if self._snapshotScope == nil and snapshots ~= nil and planNode ~= nil then
        self._snapshotScope = snapshots:CreateScope(planNode)
    end
end

function ExpectationContext:extend(config)
    for key, value in pairs(config) do
        assert(self._extensions[key] == nil, string.format("Cannot reassign %q in expect.extend", key))
        assert(checkMatcherNameCollisions(key), string.format("Cannot overwrite matcher %q; it already exists", key))

        self._extensions[key] = value
    end
end

return ExpectationContext
