--[[

TestSession

Represents the state relevant while executing a test plan. Used by TestRunner to produce
a TestResults object. Uses the same tree building structure as TestPlanBuilder and keeps
track of a stack of nodes that represent the current path through the tree.

--]]

const Context = require("./Context")
const ExpectationContext = require("./ExpectationContext")
const TestEnum = require("./TestEnum")
const TestResults = require("./TestResults")
const FILTERED_SKIP_REASON = "Excluded by the filter."

-- Limits how many tests of one run execute at the same time. The lowercase keys match the
-- other session fields.
export type Semaphore = {
    activeCount: number,
    lock: boolean,
}

const TestSession = {}

TestSession.__index = TestSession

--[[
    Create a TestSession related to the given TestPlan.

    The resulting TestResults object will be linked to this TestPlan.

    @param plan - The TestPlan to execute
    @return A new TestSession object
]]
function TestSession.new(plan: any): any
    const self = {
        results = TestResults.new(plan),
        nodeStack = {},
        contextStack = {},
        expectationContextStack = {},
        hasFocusNodes = false,
        -- Owned by this run alone, so a run nested inside one of its tests gets its own.
        semaphore = { activeCount = 0, lock = false } :: Semaphore,
    }

    setmetatable(self, TestSession)

    return self
end

--[[
    Calculate success, failure, and skipped test counts in the tree at the
    current point in the execution. Tests excluded by the filter count as skipped and
    are also tallied on their own as filteredCount. A describe node whose body errored during
    planning also counts as a failure, since the error is recorded on the describe
    node itself rather than on any of its it nodes.
]]
function TestSession:calculateTotals(): ()
    const results = self.results

    results.successCount = 0
    results.failureCount = 0
    results.skippedCount = 0
    results.filteredCount = 0

    results:visitAllNodes(function(node)
        const status = node.status
        const nodeType = node.planNode.type

        if nodeType == TestEnum.NodeType.It then
            if status == TestEnum.TestStatus.Success then
                results.successCount += 1
            elseif status == TestEnum.TestStatus.Failure then
                results.failureCount += 1
            elseif status == TestEnum.TestStatus.Skipped then
                results.skippedCount += 1
                -- Filtered-out tests are a subset of the skipped ones
                if node.planNode.filteredOut then
                    results.filteredCount += 1
                end
            end
        elseif
            nodeType == TestEnum.NodeType.Describe
            and node.planNode.loadError ~= nil
            and status == TestEnum.TestStatus.Failure
        then
            results.failureCount += 1
        end
    end)
end

--[[
    Gathers all of the errors reported by tests and puts them at the top level
    of the TestResults object.
]]
function TestSession:gatherErrors(): ()
    const results = self.results

    results.errors = {}

    results:visitAllNodes(function(node)
        if #node.errors > 0 then
            for _, message in ipairs(node.errors) do
                table.insert(results.errors, message)
            end
        end
    end)
end

--[[
    Calculates test totals, verifies the tree is valid, and returns results.

    @return The final TestResults object
]]
function TestSession:finalize(): any
    if #self.nodeStack ~= 0 then
        error("Cannot finalize TestResults with nodes still on the stack!", 2)
    end

    self:calculateTotals()
    self:gatherErrors()

    return self.results
end

--[[
    Create a new test result node and push it onto the navigation stack.

    @param planNode - The plan node to create a result for
]]
function TestSession:pushNode(planNode: any): ()
    const node = TestResults.createNode(planNode)
    const lastNode = self.nodeStack[#self.nodeStack] or self.results
    table.insert(lastNode.children, node)
    table.insert(self.nodeStack, node)

    const lastContext = self.contextStack[#self.contextStack]
    const context = Context.new(lastContext)
    table.insert(self.contextStack, context)

    const lastExpectationContext = self.expectationContextStack[#self.expectationContextStack]
    const expectationContext = ExpectationContext.new(lastExpectationContext)
    table.insert(self.expectationContextStack, expectationContext)
end

--[[
    Pops a node off of the navigation stack.
]]
function TestSession:popNode(): ()
    assert(#self.nodeStack > 0, "Tried to pop from an empty node stack!")
    table.remove(self.nodeStack, #self.nodeStack)
    table.remove(self.contextStack, #self.contextStack)
    table.remove(self.expectationContextStack, #self.expectationContextStack)
end

--[[
    Gets the Context object for the current node.

    @return The current Context object
]]
function TestSession:getContext(): any
    assert(#self.contextStack > 0, "Tried to get context from an empty stack!")
    return self.contextStack[#self.contextStack]
end

--[[
    Gets the ExpectationContext object for the current node.

    @return The current ExpectationContext object
]]
function TestSession:getExpectationContext(): any
    assert(#self.expectationContextStack > 0, "Tried to get expectationContext from an empty stack!")
    return self.expectationContextStack[#self.expectationContextStack]
end

--[[
    Tells whether the current test we're in should be skipped.

    @return True if the current test should be skipped
]]
function TestSession:shouldSkip(): boolean
    -- The filter narrows first, so a test it excluded is skipped whatever its modifiers
    const current = self.nodeStack[#self.nodeStack]
    if current ~= nil and current.planNode.filteredOut then
        return true
    end

    -- Walk up the plan tree instead of the node stack. Parallel execution gives every
    -- test and describe block its own stack that starts at that node, so the stack
    -- alone would miss modifiers on enclosing describe blocks.
    local planNode = if current ~= nil then current.planNode else nil

    while planNode ~= nil do
        -- Skipped tests are still skipped
        if planNode.modifier == TestEnum.NodeModifier.Skip then
            return true
        end

        -- If our test tree had any exclusive tests, then focused tests are the only
        -- ones that aren't skipped
        if self.hasFocusNodes and planNode.modifier == TestEnum.NodeModifier.Focus then
            return false
        end

        planNode = planNode.parent
    end

    return self.hasFocusNodes
end

--[[
    Set the current node's status to Success.
]]
function TestSession:setSuccess()
    assert(#self.nodeStack > 0, "Attempting to set success status on empty stack")
    self.nodeStack[#self.nodeStack].status = TestEnum.TestStatus.Success
end

--[[
    Set the current node's status to Skipped.
]]
function TestSession:setSkipped()
    assert(#self.nodeStack > 0, "Attempting to set skipped status on empty stack")
    const node = self.nodeStack[#self.nodeStack]
    node.status = TestEnum.TestStatus.Skipped
    -- Reporters that show skip reasons can tell filtered-out tests from other skips
    if node.planNode.filteredOut then
        node.skipReason = FILTERED_SKIP_REASON
    end
end

--[[
    Set the current node's status to Failure and adds a message to its list of
    errors.

    @param message - The error message to add
]]
function TestSession:setError(message: string): ()
    assert(#self.nodeStack > 0, "Attempting to set error status on empty stack")
    const last = self.nodeStack[#self.nodeStack]
    last.status = TestEnum.TestStatus.Failure
    table.insert(last.errors, message)
end

--[[
    Add a dummy child node to the current node to hold the given error. This
    allows an otherwise empty describe node to report an error in a more natural
    way.

    @param phrase - The phrase/name for the dummy error node
    @param message - The error message
]]
function TestSession:addDummyError(phrase: string, message: string): ()
    self:pushNode({ type = TestEnum.NodeType.It, phrase = phrase })
    self:setError(message)
    self:popNode()
    self.nodeStack[#self.nodeStack].status = TestEnum.TestStatus.Failure
end

--[[
    Set the current node's status based on that of its children. If all children
    are skipped, mark it as skipped. If any are fails, mark it as failed.
    Otherwise, mark it as success.
]]
function TestSession:setStatusFromChildren()
    assert(#self.nodeStack > 0, "Attempting to set status from children on empty stack")

    const last = self.nodeStack[#self.nodeStack]
    local status = TestEnum.TestStatus.Success
    local skipped = true

    -- If all children were skipped, then we were skipped
    -- If any child failed, then we failed!
    for _, child in ipairs(last.children) do
        if child.status ~= TestEnum.TestStatus.Skipped then
            skipped = false

            if child.status == TestEnum.TestStatus.Failure then
                status = TestEnum.TestStatus.Failure
            end
        end
    end

    if skipped then
        status = TestEnum.TestStatus.Skipped
    end

    last.status = status
end

return TestSession
