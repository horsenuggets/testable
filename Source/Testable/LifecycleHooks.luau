--[[

LifecycleHooks

Manages lifecycle hooks (beforeAll, afterAll, beforeEach, afterEach) for test execution.
Maintains a stack of hooks that can be pushed and popped as test nodes are entered and
exited. Each hook keeps the time budget its own registration set, so the same function
registered twice, or in nested blocks, gets the budget of each registration.

--]]

const TestEnum = require("./TestEnum")

-- One registration of a hook. The lowercase keys match the plan node fields they come
-- from.
export type Hook = {
    callback: (...any) -> ...any,
    timeout: number?
}

const LifecycleHooks = {}
LifecycleHooks.__index = LifecycleHooks

--[[
    Creates a new LifecycleHooks manager.

    @return A new LifecycleHooks object
]]
function LifecycleHooks.new(): any
    const self = {
        _stack = {}
    }
    return setmetatable(self, LifecycleHooks)
end

--[[
    Returns an array of `beforeEach` hooks in FIFO order.

    @return Array of beforeEach hooks, each with its callback and its own budget
]]
function LifecycleHooks:getBeforeEachHooks(): { Hook }
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

    @return Array of afterEach hooks, each with its callback and its own budget
]]
function LifecycleHooks:getAfterEachHooks(): { Hook }
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

    table.insert(self._stack, {
        [TestEnum.NodeType.BeforeAll] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeAll),
        [TestEnum.NodeType.AfterAll] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterAll),
        [TestEnum.NodeType.BeforeEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeEach),
        [TestEnum.NodeType.AfterEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterEach)
    })
end

--[[
    Get the beforeAll hooks from the current level.

    @return Array of beforeAll hooks, each with its callback and its own budget
]]
function LifecycleHooks:getBeforeAllHooks(): { Hook }
    return self._stack[#self._stack][TestEnum.NodeType.BeforeAll]
end

--[[
    Get the afterAll hooks from the current level.

    @return Array of afterAll hooks, each with its callback and its own budget
]]
function LifecycleHooks:getAfterAllHooks(): { Hook }
    return self._stack[#self._stack][TestEnum.NodeType.AfterAll]
end

--[[
    Internal helper to extract hooks of a specific type from nodes.

    @param nodes - Array of plan nodes to search
    @param key - The NodeType to filter by
    @return Array of hooks matching the type, in registration order
]]
function LifecycleHooks:_getHooksOfType(nodes: { any }, key: string): { Hook }
    const hooks: { Hook } = {}

    for _, node in ipairs(nodes) do
        if node.type == key then
            table.insert(hooks, { callback = node.callback, timeout = node.timeout })
        end
    end

    return hooks
end

return LifecycleHooks
