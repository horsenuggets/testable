--[[

LifecycleHooks

Manages lifecycle hooks (beforeAll, afterAll, beforeEach, afterEach) for test execution.
Maintains a stack of hooks that can be pushed and popped as test nodes are entered and
exited.

--]]

const TestEnum = require("./TestEnum")
const HOOK_TYPES = {
    [TestEnum.NodeType.AfterAll] = true,
    [TestEnum.NodeType.AfterEach] = true,
    [TestEnum.NodeType.BeforeAll] = true,
    [TestEnum.NodeType.BeforeEach] = true,
}
const TIMEOUTS_KEY = "Timeouts"

const LifecycleHooks = {}
LifecycleHooks.__index = LifecycleHooks

--[[
    Creates a new LifecycleHooks manager.

    @return A new LifecycleHooks object
]]
function LifecycleHooks.new(): any
    const self = {
        _stack = {},
    }
    return setmetatable(self, LifecycleHooks)
end

--[[
    Returns an array of `beforeEach` hooks in FIFO order.

    @return Array of beforeEach hook functions
]]
function LifecycleHooks:getBeforeEachHooks(): { any }
    const key = TestEnum.NodeType.BeforeEach
    const hooks = {}

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
    const key = TestEnum.NodeType.AfterEach
    const hooks = {}

    for _, level in ipairs(self._stack) do
        for _, hook in ipairs(level[key]) do
            table.insert(hooks, 1, hook)
        end
    end

    return hooks
end

--[[
    Returns a manager with its own copy of the current stack. Describe blocks that run in
    parallel each need one, because pushing onto a shared stack would hand one block the
    hooks of whichever block pushed last.

    @return A new LifecycleHooks object that shares the current levels
]]
function LifecycleHooks:fork(): any
    const forked = LifecycleHooks.new()
    for _, level in ipairs(self._stack) do
        table.insert(forked._stack, level)
    end
    return forked
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

    -- The time budgets that hooks set on themselves, by hook type and then by callback.
    const timeouts = {}
    for _, node in ipairs(planNode.children) do
        if HOOK_TYPES[node.type] and node.timeout ~= nil then
            timeouts[node.type] = timeouts[node.type] or {}
            timeouts[node.type][node.callback] = node.timeout
        end
    end

    table.insert(self._stack, {
        [TestEnum.NodeType.BeforeAll] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeAll),
        [TestEnum.NodeType.AfterAll] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterAll),
        [TestEnum.NodeType.BeforeEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeEach),
        [TestEnum.NodeType.AfterEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterEach),
        [TIMEOUTS_KEY] = timeouts,
    })
end

--[[
    Returns the time budget a hook set on itself with its Timeout option. The innermost
    level that registered the hook wins.

    @param hookType - The NodeType of the hook, such as TestEnum.NodeType.BeforeAll
    @param hook - The hook function
    @return The budget in seconds, or nil when the hook did not set one
]]
function LifecycleHooks:getHookTimeout(hookType: string, hook: any): number?
    assert(HOOK_TYPES[hookType], "hookType must be a lifecycle hook node type")

    for index = #self._stack, 1, -1 do
        const timeouts = self._stack[index][TIMEOUTS_KEY][hookType]
        if timeouts ~= nil and timeouts[hook] ~= nil then
            return timeouts[hook]
        end
    end

    return nil
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
    const hooks = {}

    for _, node in ipairs(nodes) do
        if node.type == key then
            table.insert(hooks, node.callback)
        end
    end

    return hooks
end

return LifecycleHooks
