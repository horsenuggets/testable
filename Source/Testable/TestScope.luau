--[[

TestScope

Tracks what each coroutine is currently doing for Testable, so that functions required
from the Testable module (rather than injected into a spec's environment) can find the
describe block being collected or the test being run. Every coroutine has its own stack of
frames, because tests run concurrently under task.spawn and a test may itself plan and run
a nested set of tests.

--]]

-- The state of one running test or lifecycle hook callback.
export type RunScope = {
    -- The ExpectationContext holding the custom matchers visible to this callback.
    ExpectationContext: any,
    -- Marks the callback as failed with the given message.
    Fail: (message: string) -> (),
    -- True once the callback has returned, after which failures can't be recorded.
    Finished: boolean
}

type Frame = {
    Node: any?,
    Scope: RunScope?
}

-- Keyed weakly so that the stack of a thread that dies mid-callback is collected with it.
const stacks: { [thread]: { Frame } } = setmetatable({}, { __mode = "k" }) :: any

const TestScope = {}

const function push(frame: Frame)
    const thread = coroutine.running()
    local stack = stacks[thread]
    if stack == nil then
        stack = {}
        stacks[thread] = stack
    end
    table.insert(stack, frame)
end

const function peek(): Frame?
    const stack = stacks[coroutine.running()]
    return if stack ~= nil then stack[#stack] else nil
end

--[[
    Marks the calling coroutine as collecting the given plan node, until the matching
    call to TestScope.exit.

    @param node - The TestPlan node whose callback is about to be expanded
]]
function TestScope.enterCollection(node: any)
    assert(type(node) == "table", "node must be a table")

    push({ Node = node })
end

--[[
    Marks the calling coroutine as running a test or hook callback with the given scope,
    until the matching call to TestScope.exit.

    @param scope - The scope of the callback that is about to run
]]
function TestScope.enterRun(scope: RunScope)
    assert(type(scope) == "table", "scope must be a table")

    push({ Scope = scope })
end

--[[
    Leaves the frame most recently entered on the calling coroutine.
]]
function TestScope.exit()
    const thread = coroutine.running()
    const stack = stacks[thread]
    assert(stack ~= nil and #stack > 0, "TestScope.exit was called without a matching enter")

    table.remove(stack)
    if #stack == 0 then
        stacks[thread] = nil
    end
end

--[[
    Returns the plan node the calling coroutine is collecting right now. This is nil while
    the coroutine is running a test, even if that test is nested inside a collection.

    @return The plan node being collected, or nil
]]
function TestScope.getCollectingNode(): any?
    const frame = peek()
    return if frame ~= nil then frame.Node else nil
end

--[[
    Returns the scope of the test or hook the calling coroutine is running right now. This
    is nil while the coroutine is collecting, and in coroutines that Testable did not
    start itself.

    @return The scope of the running callback, or nil
]]
function TestScope.getRunScope(): RunScope?
    const frame = peek()
    return if frame ~= nil then frame.Scope else nil
end

return TestScope
