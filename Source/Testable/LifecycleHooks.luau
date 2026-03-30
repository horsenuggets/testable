--[[

LifecycleHooks

Manages lifecycle hooks (beforeAll, afterAll, beforeEach, afterEach) for test execution.
Maintains a stack of hooks that can be pushed and popped as test nodes are entered and
exited.

--]]

local TestEnum = require("./TestEnum")

local LifecycleHooks = {}
LifecycleHooks.__index = LifecycleHooks

--[[
    Creates a new LifecycleHooks manager.

    @return A new LifecycleHooks object
]]
function LifecycleHooks.new(): any
    local self = {
        _stack = {},
    }
    return setmetatable(self, LifecycleHooks)
end

--[[
    Returns an array of `beforeEach` hooks in FIFO order.

    @return Array of beforeEach hook functions
]]
function LifecycleHooks:getBeforeEachHooks(): { any }
    local key = TestEnum.NodeType.BeforeEach
    local hooks = {}

    for _, level in ipairs(self._stack) do
        for _, hook in ipairs(level[key]) do
            table.insert(hooks, hook)
        end
    end

    return hooks
end

--[[
    Returns an array of `afterEach` hooks in FILO order.

    @return Array of afterEach hook functions
]]
function LifecycleHooks:getAfterEachHooks(): { any }
    local key = TestEnum.NodeType.AfterEach
    local hooks = {}

    for _, level in ipairs(self._stack) do
        for _, hook in ipairs(level[key]) do
            table.insert(hooks, 1, hook)
        end
    end

    return hooks
end

--[[
    Pushes uncalled beforeAll and afterAll hooks back up the stack.
]]
function LifecycleHooks:popHooks(): ()
    table.remove(self._stack, #self._stack)
end

--[[
    Pushes hooks from the given plan node onto the stack.

    @param planNode - The plan node to extract hooks from
]]
function LifecycleHooks:pushHooksFrom(planNode: any): ()
    assert(planNode ~= nil)

    table.insert(self._stack, {
        [TestEnum.NodeType.BeforeAll] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeAll),
        [TestEnum.NodeType.AfterAll] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterAll),
        [TestEnum.NodeType.BeforeEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeEach),
        [TestEnum.NodeType.AfterEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterEach),
    })
end

--[[
    Get the beforeAll hooks from the current level.

    @return Array of beforeAll hook functions
]]
function LifecycleHooks:getBeforeAllHooks(): { any }
    return self._stack[#self._stack][TestEnum.NodeType.BeforeAll]
end

--[[
    Get the afterAll hooks from the current level.

    @return Array of afterAll hook functions
]]
function LifecycleHooks:getAfterAllHooks(): { any }
    return self._stack[#self._stack][TestEnum.NodeType.AfterAll]
end

--[[
    Internal helper to extract hooks of a specific type from nodes.

    @param nodes - Array of plan nodes to search
    @param key - The NodeType to filter by
    @return Array of callback functions matching the type
]]
function LifecycleHooks:_getHooksOfType(nodes: { any }, key: string): { any }
    local hooks = {}

    for _, node in ipairs(nodes) do
        if node.type == key then
            table.insert(hooks, node.callback)
        end
    end

    return hooks
end

return LifecycleHooks
