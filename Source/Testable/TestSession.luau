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
const FOCUS_GUARD_PHRASE = "Focus guard"

-- Limits how many tests of one run execute at the same time. The lowercase keys match the
-- other session fields. A test or describe block marked as serial takes the whole
-- semaphore for itself, which waits for the shared holders to finish and keeps new ones
-- from starting until it is released. While a writer waits, new shared holders wait too,
-- so a long run of ordinary tests cannot starve it.
export type Semaphore = {
    activeCount: number,
    exclusive: boolean,
    exclusiveWaiting: number,
    lock: boolean,
}

const TestSession = {}

TestSession.__index = TestSession

-- The name of the failed test that stands for a tripped focus guard in the results.
TestSession.FocusGuardPhrase = FOCUS_GUARD_PHRASE

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
        forbidFocus = false,
        hasFocusNodes = false,
        -- Owned by this run alone, so a run nested inside one of its tests gets its own.
        semaphore = { activeCount = 0, exclusive = false, exclusiveWaiting = 0, lock = false } :: Semaphore,
        -- True for the sessions of a run that is inside a serial test or describe block,
        -- where nothing else executes and the semaphore is not needed.
        holdsExclusive = false,
        -- Whether the run schedules tests in parallel, read from Config once when the
        -- run starts.
        parallel = true,
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
    results.focusExcludedCount = 0

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
                -- Filtered-out and focus-excluded tests are subsets of the skipped ones
                if node.planNode.filteredOut then
                    results.filteredCount += 1
                end
                if node.excludedByFocus then
                    results.focusExcludedCount += 1
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
    Fails the run when focus is forbidden and a focus modifier excluded at least one
    test. The failure is recorded as a failed test at the top of the results tree, so the
    totals, the gathered errors, and every reporter that reads the tree all see the run
    as failed. It needs the focus count from calculateTotals, and the totals and errors
    have to be worked out again afterward to take the new node in.
]]
function TestSession:applyFocusGuard(): ()
    const results = self.results

    results.focusGuardFailed = self.forbidFocus == true and results.focusExcludedCount > 0

    -- The node is only added once, so finalizing again doesn't fail the run twice.
    if results.focusGuardFailed and results.focusGuardNode == nil then
        const node = TestResults.createNode({ phrase = FOCUS_GUARD_PHRASE, type = TestEnum.NodeType.It })
        node.duration = 0
        node.status = TestEnum.TestStatus.Failure
        table.insert(node.errors, TestSession.formatFocusGuardError(results.focusExcludedCount))
        table.insert(results.children, node)
        results.focusGuardNode = node
    end
end

--[[
    Builds the error reported when the focus guard fails a run.

    @param excludedCount - How many tests were excluded by focus
    @return The error message
]]
function TestSession.formatFocusGuardError(excludedCount: number): string
    assert(type(excludedCount) == "number", "excludedCount must be a number")
    const tests = if excludedCount == 1 then "1 test was" else `{excludedCount} tests were`
    return `Focus is forbidden by "ForbidFocus", but {tests} excluded by a focus modifier. `
        .. 'Remove every "itFOCUS", "fit", "describeFOCUS", "fdescribe", and "FOCUS" before committing.'
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
    self:applyFocusGuard()
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
    const expectationContext = self.expectationContextStack[#self.expectationContextStack]

    -- Snapshot assertions need to know which test they run in. Tests run concurrently, so
    -- that identity travels with each test's own context instead of a global.
    const node = self.nodeStack[#self.nodeStack]
    expectationContext:bindSnapshotScope(self.results.snapshots, node and node.planNode)

    return expectationContext
end

--[[
    Tells whether the current test we're in should be skipped, and why.

    The decision walks the plan tree from the current test up to its root rather than
    the node stack, because the sessions that run tests in parallel only hold the test's
    own node.

    @return skip - True if the current test should be skipped
    @return reason - Why the test is skipped, if a reason is known
    @return excludedByFocus - True if the test is only skipped because other tests are
        focused
]]
function TestSession:shouldSkip(): (boolean, string?, boolean)
    assert(#self.nodeStack > 0, "Attempting to check skip status on empty stack")
    local planNode = self.nodeStack[#self.nodeStack].planNode

    -- The filter narrows first, so a test it excluded is skipped whatever its modifiers,
    -- and it never counts as excluded by focus
    if planNode.filteredOut then
        return true, TestEnum.SkipReason.Filter, false
    end

    while planNode ~= nil do
        -- Skipped tests are still skipped. The nearest reason wins, so a test's own
        -- reason overrides its describe block's reason.
        if planNode.modifier == TestEnum.NodeModifier.Skip then
            local reasonNode = planNode
            while reasonNode ~= nil do
                if reasonNode.modifier == TestEnum.NodeModifier.Skip and reasonNode.skipReason ~= nil then
                    return true, reasonNode.skipReason, false
                end
                reasonNode = reasonNode.parent
            end
            return true, nil, false
        end

        -- Focused tests are the only ones that aren't skipped
        if self.hasFocusNodes and planNode.modifier == TestEnum.NodeModifier.Focus then
            return false, nil, false
        end

        planNode = planNode.parent
    end

    -- If our test tree had any exclusive tests, then normal tests are skipped!
    if self.hasFocusNodes then
        return true, TestEnum.SkipReason.Focus, true
    end

    return false, nil, false
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

    @param reason - Why the test was skipped, if a reason is known
    @param excludedByFocus - True if the test was only skipped because other tests are
        focused
]]
function TestSession:setSkipped(reason: string?, excludedByFocus: boolean?)
    assert(#self.nodeStack > 0, "Attempting to set skipped status on empty stack")
    const last = self.nodeStack[#self.nodeStack]
    last.status = TestEnum.TestStatus.Skipped
    last.skipReason = reason
    last.excludedByFocus = excludedByFocus == true
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
