--[[
    Contains the logic to run a test plan and gather test results from it.

    TestRunner accepts a TestPlan object, executes the planned tests, and
    produces a TestResults object. While the tests are running, the system's
    state is contained inside a TestSession object.

    Modified to support parallel test execution via task.spawn.
]]

local LifecycleHooks = require("./LifecycleHooks")
local task = if task then task else require("@lune/task")
local TestEnum = require("./TestEnum")
local TestResults = require("./TestResults")
local TestSession = require("./TestSession")

local RUNNING_GLOBAL = "__TESTABLE_RUNNING_TEST__"

local TestRunner = {
    environment = {},
    parallelEnabled = true, -- Set to false to disable parallel execution
    verbose = false, -- Set to true to enable detailed logging
}

--[[
    Logs messages when verbose mode is enabled.

    @param ... - Messages to log
]]
local function log(...: any): ()
    if TestRunner.verbose then
        print("[Testable]", ...)
    end
end

--[[
    Wraps an expectation context with a public API.

    @param expectationContext - The expectation context to wrap
    @return A callable table that provides the expect() API
]]
local function wrapExpectContextWithPublicApi(expectationContext: any): any
    return setmetatable({
        extend = function(...)
            expectationContext:extend(...)
        end,
    }, {
        __call = function(_self, ...)
            return expectationContext:startExpectationChain(...)
        end,
    })
end

--[[
    Runs the given TestPlan and returns a TestResults object representing the
    results of the run.

    @param plan - The TestPlan to execute
    @return TestResults object containing the test execution results
]]
function TestRunner.runPlan(plan: any): any
    log("Starting test plan execution...")
    local session = TestSession.new(plan)
    local lifecycleHooks = LifecycleHooks.new()

    local exclusiveNodes = plan:findNodes(function(node)
        return node.modifier == TestEnum.NodeModifier.Focus
    end)

    session.hasFocusNodes = #exclusiveNodes > 0

    if session.hasFocusNodes then
        log("Focus nodes detected, other tests will be skipped.")
    end

    TestRunner.runPlanNode(session, plan, lifecycleHooks)

    log("Test plan execution complete.")

    return session:finalize()
end

--[[
    Run the given test plan node and its descendants, using the given test
    session to store all of the results.

    @param session - The TestSession to store results in
    @param planNode - The plan node to execute
    @param lifecycleHooks - The LifecycleHooks manager for before/after hooks
]]
function TestRunner.runPlanNode(session: any, planNode: any, lifecycleHooks: any): ()
    --[[
        Runs a callback function in a protected environment with error handling.

        @param callback - The function to execute
        @param messagePrefix - Optional prefix for error messages
        @return success: boolean, errorMessage: string?
    ]]
    local function runCallback(callback: (any) -> (), messagePrefix: string?): (boolean, string?)
        local success = true
        local errorMessage
        -- Any code can check RUNNING_GLOBAL to fork behavior based on
        -- whether a test is running. We use this to avoid accessing
        -- protected APIs; it's a workaround that will go away someday.
        _G[RUNNING_GLOBAL] = true

        messagePrefix = messagePrefix or ""

        local testEnvironment = getfenv(callback)

        for key, value in pairs(TestRunner.environment) do
            testEnvironment[key] = value
        end

        testEnvironment.fail = function(message)
            if message == nil then
                message = "fail() was called."
            end

            success = false
            errorMessage = messagePrefix .. debug.traceback(tostring(message), 2)
        end

        testEnvironment.expect = wrapExpectContextWithPublicApi(session:getExpectationContext())

        local context = session:getContext()

        local nodeSuccess, nodeResult = xpcall(function()
            callback(context)
        end, function(message)
            return messagePrefix .. debug.traceback(tostring(message), 2)
        end)

        -- If a node threw an error, we prefer to use that message over
        -- one created by fail() if it was set.
        if not nodeSuccess then
            success = false
            errorMessage = nodeResult
        end

        _G[RUNNING_GLOBAL] = nil

        return success, errorMessage
    end

    local function runNode(childPlanNode)
        -- Errors can be set either via `error` propagating upwards or
        -- by a test calling fail([message]).

        for _, hook in ipairs(lifecycleHooks:getBeforeEachHooks()) do
            local success, errorMessage = runCallback(hook, "beforeEach hook: ")
            if not success then
                return false, errorMessage
            end
        end

        local testSuccess, testErrorMessage = runCallback(childPlanNode.callback)

        for _, hook in ipairs(lifecycleHooks:getAfterEachHooks()) do
            local success, errorMessage = runCallback(hook, "afterEach hook: ")
            if not success then
                if not testSuccess then
                    return false,
                        testErrorMessage
                            .. "\nWhile cleaning up the failed test another error was found:\n"
                            .. errorMessage
                end
                return false, errorMessage
            end
        end

        if not testSuccess then
            return false, testErrorMessage
        end

        return true, nil
    end

    lifecycleHooks:pushHooksFrom(planNode)

    local halt = false
    for _, hook in ipairs(lifecycleHooks:getBeforeAllHooks()) do
        local success, errorMessage = runCallback(hook, "beforeAll hook: ")
        if not success then
            session:addDummyError("beforeAll", errorMessage)
            halt = true
        end
    end

    if not halt then
        -- Collect all "it" tests and describe blocks at this level
        local itTests = {}
        local describeBlocks = {}

        for _, childPlanNode in ipairs(planNode.children) do
            if childPlanNode.type == TestEnum.NodeType.It then
                table.insert(itTests, childPlanNode)
            elseif childPlanNode.type == TestEnum.NodeType.Describe then
                table.insert(describeBlocks, childPlanNode)
            end
        end

        -- Run "it" tests in parallel if enabled
        if TestRunner.parallelEnabled and #itTests > 0 then
            log(string.format("Running %d tests in parallel...", #itTests))
            local completed = 0
            local total = #itTests
            local startTime = os.clock()
            local mutex = {}

            -- Pre-create all test nodes to maintain proper order in tree
            local testNodes = {}
            local testContexts = {}
            local testExpectationContexts = {}
            for i, childPlanNode in ipairs(itTests) do
                local node = TestResults.createNode(childPlanNode)
                local lastNode = session.nodeStack[#session.nodeStack] or session.results
                table.insert(lastNode.children, node)
                testNodes[i] = node

                -- Pre-create contexts
                local Context = require("./Context")
                local ExpectationContext = require("./ExpectationContext")
                local lastContext = session.contextStack[#session.contextStack]
                testContexts[i] = Context.new(lastContext)
                local lastExpectationContext = session.expectationContextStack[#session.expectationContextStack]
                testExpectationContexts[i] = ExpectationContext.new(lastExpectationContext)
            end

            -- Now run tests in parallel
            for i, childPlanNode in ipairs(itTests) do
                task.spawn(function()
                    log(string.format("  [%d/%d] Starting: %s", i, total, childPlanNode.phrase))

                    -- Create isolated session for this test that writes to the pre-created node
                    local testSession = {
                        results = session.results,
                        nodeStack = { testNodes[i] },
                        contextStack = { testContexts[i] },
                        expectationContextStack = { testExpectationContexts[i] },
                        hasFocusNodes = session.hasFocusNodes,
                    }
                    setmetatable(testSession, { __index = TestSession })

                    local shouldSkip = testSession:shouldSkip()

                    if shouldSkip then
                        log(string.format("  [%d/%d] Skipped: %s", i, total, childPlanNode.phrase))
                        testSession:setSkipped()
                    else
                        -- Run the test (parallel execution here)
                        local testStartTime = os.clock()
                        local success, errorMessage = runNode(childPlanNode)
                        local testDuration = os.clock() - testStartTime

                        if success then
                            testSession:setSuccess()
                            log(
                                string.format(
                                    "  [%d/%d] ✓ Passed: %s (%.2fs)",
                                    i,
                                    total,
                                    childPlanNode.phrase,
                                    testDuration
                                )
                            )
                        else
                            testSession:setError(errorMessage)
                            log(
                                string.format(
                                    "  [%d/%d] ✗ Failed: %s (%.2fs)",
                                    i,
                                    total,
                                    childPlanNode.phrase,
                                    testDuration
                                )
                            )
                            if TestRunner.verbose then
                                print("    Error:", errorMessage)
                            end
                        end
                    end

                    while mutex.locked do
                        task.wait()
                    end
                    mutex.locked = true
                    completed = completed + 1
                    local remaining = total - completed
                    log(string.format("  Progress: %d/%d complete, %d remaining", completed, total, remaining))
                    mutex.locked = false
                end)
            end

            -- Wait for all tests to complete
            while completed < total do
                task.wait()
            end

            local totalDuration = os.clock() - startTime
            log(string.format("Parallel execution complete: %d tests in %.2fs", total, totalDuration))
        elseif #itTests > 0 then
            -- Run tests sequentially
            if not TestRunner.parallelEnabled then
                log(string.format("Running %d tests sequentially (parallel disabled)...", #itTests))
            else
                log(string.format("Running %d tests sequentially...", #itTests))
            end

            for i, childPlanNode in ipairs(itTests) do
                log(string.format("  [%d/%d] Running: %s", i, #itTests, childPlanNode.phrase))
                local testStartTime = os.clock()

                session:pushNode(childPlanNode)
                if session:shouldSkip() then
                    session:setSkipped()
                    log(string.format("  [%d/%d] Skipped: %s", i, #itTests, childPlanNode.phrase))
                else
                    local success, errorMessage = runNode(childPlanNode)
                    local testDuration = os.clock() - testStartTime

                    if success then
                        session:setSuccess()
                        log(
                            string.format(
                                "  [%d/%d] ✓ Passed: %s (%.2fs)",
                                i,
                                #itTests,
                                childPlanNode.phrase,
                                testDuration
                            )
                        )
                    else
                        session:setError(errorMessage)
                        log(
                            string.format(
                                "  [%d/%d] ✗ Failed: %s (%.2fs)",
                                i,
                                #itTests,
                                childPlanNode.phrase,
                                testDuration
                            )
                        )
                    end
                end
                session:popNode()
            end
        end

        -- Process describe blocks in parallel if enabled
        if TestRunner.parallelEnabled and #describeBlocks > 0 then
            log(string.format("Running %d describe blocks in parallel...", #describeBlocks))
            local completed = 0
            local total = #describeBlocks
            local startTime = os.clock()
            local mutex = {}

            -- Pre-create result nodes for all describe blocks in the correct order
            local describeNodes = {}
            for i, childPlanNode in ipairs(describeBlocks) do
                local node = TestResults.createNode(childPlanNode)
                local lastNode = session.nodeStack[#session.nodeStack] or session.results
                table.insert(lastNode.children, node)
                describeNodes[i] = node
            end

            for i, childPlanNode in ipairs(describeBlocks) do
                task.spawn(function()
                    log(string.format("  [%d/%d] Starting describe block: %s", i, total, childPlanNode.phrase))
                    local blockStartTime = os.clock()

                    -- Create an isolated sub-session for this describe block
                    -- that will write to our pre-created node
                    local subSession = {
                        results = session.results,
                        nodeStack = {},
                        contextStack = {},
                        expectationContextStack = {},
                        hasFocusNodes = session.hasFocusNodes,
                    }
                    setmetatable(subSession, { __index = TestSession })

                    -- Copy the parent's context stack
                    for _, ctx in ipairs(session.contextStack) do
                        table.insert(subSession.contextStack, ctx)
                    end
                    for _, ctx in ipairs(session.expectationContextStack) do
                        table.insert(subSession.expectationContextStack, ctx)
                    end

                    -- Push the describe node using our pre-created node
                    while mutex.locked do
                        task.wait()
                    end
                    mutex.locked = true
                    table.insert(subSession.nodeStack, describeNodes[i])

                    local Context = require("./Context")
                    local ExpectationContext = require("./ExpectationContext")
                    local lastContext = subSession.contextStack[#subSession.contextStack]
                    local context = Context.new(lastContext)
                    table.insert(subSession.contextStack, context)
                    local lastExpectationContext =
                        subSession.expectationContextStack[#subSession.expectationContextStack]
                    local expectationContext = ExpectationContext.new(lastExpectationContext)
                    table.insert(subSession.expectationContextStack, expectationContext)
                    mutex.locked = false

                    -- Run the describe block with its own isolated session
                    TestRunner.runPlanNode(subSession, childPlanNode, lifecycleHooks)

                    -- Handle results
                    while mutex.locked do
                        task.wait()
                    end
                    mutex.locked = true
                    if childPlanNode.loadError then
                        local message = "Error during planning: " .. childPlanNode.loadError
                        subSession:setError(message)
                        log(string.format("  [%d/%d] ✗ Planning error in: %s", i, total, childPlanNode.phrase))
                    else
                        subSession:setStatusFromChildren()
                    end

                    completed = completed + 1
                    local blockDuration = os.clock() - blockStartTime
                    local remaining = total - completed
                    log(
                        string.format(
                            "  [%d/%d] Completed describe block: %s (%.2fs)",
                            i,
                            total,
                            childPlanNode.phrase,
                            blockDuration
                        )
                    )
                    log(
                        string.format(
                            "  Progress: %d/%d describe blocks complete, %d remaining",
                            completed,
                            total,
                            remaining
                        )
                    )
                    mutex.locked = false
                end)
            end

            -- Wait for all describe blocks to complete
            while completed < total do
                task.wait()
            end

            local totalDuration = os.clock() - startTime
            log(string.format("Parallel describe block execution complete: %d blocks in %.2fs", total, totalDuration))
        elseif #describeBlocks > 0 then
            -- Run describe blocks sequentiallyif #describeBlocks > 0 then
            -- Run describe blocks sequentially
            for _, childPlanNode in ipairs(describeBlocks) do
                log(string.format("Entering describe block: %s", childPlanNode.phrase))
                session:pushNode(childPlanNode)
                TestRunner.runPlanNode(session, childPlanNode, lifecycleHooks)

                if childPlanNode.loadError then
                    local message = "Error during planning: " .. childPlanNode.loadError
                    session:setError(message)
                    log(string.format("✗ Planning error in: %s", childPlanNode.phrase))
                else
                    session:setStatusFromChildren()
                end
                session:popNode()
                log(string.format("Exiting describe block: %s", childPlanNode.phrase))
            end
        end
    end

    for _, hook in ipairs(lifecycleHooks:getAfterAllHooks()) do
        local success, errorMessage = runCallback(hook, "afterAll hook: ")
        if not success then
            session:addDummyError("afterAll", errorMessage)
        end
    end

    lifecycleHooks:popHooks()
end

return TestRunner
