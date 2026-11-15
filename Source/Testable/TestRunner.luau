--[[

TestRunner

Contains the logic to run a test plan and gather test results from it. TestRunner accepts
a TestPlan object, executes the planned tests, and produces a TestResults object. Supports
parallel test execution via task.spawn.

--]]

const Config = require("./Config")
const LifecycleHooks = require("./LifecycleHooks")
const task = if task then task else require("@lune/task")
const TestEnum = require("./TestEnum")
const TestResults = require("./TestResults")
const TestSession = require("./TestSession")

const RUNNING_GLOBAL = "__TESTABLE_RUNNING_TEST__"
const RUNNING_COUNT_GLOBAL = "__TESTABLE_RUNNING_COUNT__"

-- Global semaphore for limiting concurrent test execution across all describe blocks
const globalSemaphore = { activeCount = 0, lock = false }

const TestRunner = {
    environment = {},
}

-- Helper to acquire a global semaphore slot
const function acquireGlobalSlot()
    while true do
        while globalSemaphore.lock do
            task.wait()
        end
        globalSemaphore.lock = true
        if globalSemaphore.activeCount < Config.MaxConcurrency then
            globalSemaphore.activeCount = globalSemaphore.activeCount + 1
            globalSemaphore.lock = false
            return
        end
        globalSemaphore.lock = false
        task.wait()
    end
end

-- Helper to release a global semaphore slot
const function releaseGlobalSlot()
    while globalSemaphore.lock do
        task.wait()
    end
    globalSemaphore.lock = true
    globalSemaphore.activeCount = globalSemaphore.activeCount - 1
    globalSemaphore.lock = false
end

--[[
    Logs messages when verbose mode is enabled.

    @param ... - Messages to log
]]
const function log(...: any): ()
    if Config.Verbose then
        print("[Testable]", ...)
    end
end

--[[
    Wraps an expectation context with a public API.

    @param expectationContext - The expectation context to wrap
    @return A callable table that provides the expect() API
]]
const function wrapExpectContextWithPublicApi(expectationContext: any): any
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
    const session = TestSession.new(plan)
    const lifecycleHooks = LifecycleHooks.new()

    const exclusiveNodes = plan:findNodes(function(node)
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
    const function runCallback(callback: (any) -> (), inputMessagePrefix: string?): (boolean, string?)
        local success = true
        local errorMessage
        -- Any code can check RUNNING_GLOBAL to fork behavior based on
        -- whether a test is running. We use this to avoid accessing
        -- protected APIs; it's a workaround that will go away someday.
        -- Use a counter instead of boolean to handle parallel test execution safely.
        _G[RUNNING_COUNT_GLOBAL] = (_G[RUNNING_COUNT_GLOBAL] or 0) + 1
        _G[RUNNING_GLOBAL] = true

        const messagePrefix: string = inputMessagePrefix or ""

        const testEnvironment = getfenv(callback)

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

        const context = session:getContext()

        const nodeSuccess, nodeResult = xpcall(function()
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

        -- Decrement the counter and only clear the flag when no tests are running
        _G[RUNNING_COUNT_GLOBAL] = (_G[RUNNING_COUNT_GLOBAL] or 1) - 1
        if _G[RUNNING_COUNT_GLOBAL] <= 0 then
            _G[RUNNING_GLOBAL] = nil
            _G[RUNNING_COUNT_GLOBAL] = nil
        end

        return success, errorMessage
    end

    const function runNode(childPlanNode)
        -- Errors can be set either via `error` propagating upwards or
        -- by a test calling fail([message]).

        for _, hook in ipairs(lifecycleHooks:getBeforeEachHooks()) do
            const success, errorMessage = runCallback(hook, "beforeEach hook: ")
            if not success then
                return false, errorMessage
            end
        end

        const testSuccess, testErrorMessage = runCallback(childPlanNode.callback)

        for _, hook in ipairs(lifecycleHooks:getAfterEachHooks()) do
            const success, errorMessage = runCallback(hook, "afterEach hook: ")
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
        const success, errorMessage = runCallback(hook, "beforeAll hook: ")
        if not success then
            session:addDummyError("beforeAll", errorMessage)
            halt = true
        end
    end

    if not halt then
        -- Collect all "it" tests and describe blocks at this level
        const itTests = {}
        const describeBlocks = {}

        for _, childPlanNode in ipairs(planNode.children) do
            if childPlanNode.type == TestEnum.NodeType.It then
                table.insert(itTests, childPlanNode)
            elseif childPlanNode.type == TestEnum.NodeType.Describe then
                table.insert(describeBlocks, childPlanNode)
            end
        end

        -- Run "it" tests in parallel if enabled
        if Config.Parallel and #itTests > 0 then
            log(string.format("Running %d tests in parallel (max %d concurrent)...", #itTests, Config.MaxConcurrency))
            local completed = 0
            const total = #itTests
            const startTime = os.clock()
            local completionLock = false

            -- Pre-create all test nodes to maintain proper order in tree
            const testNodes = {}
            const testContexts = {}
            const testExpectationContexts = {}
            for i, childPlanNode in ipairs(itTests) do
                const node = TestResults.createNode(childPlanNode)
                const lastNode = session.nodeStack[#session.nodeStack] or session.results
                table.insert(lastNode.children, node)
                testNodes[i] = node

                -- Pre-create contexts
                const Context = require("./Context")
                const ExpectationContext = require("./ExpectationContext")
                const lastContext = session.contextStack[#session.contextStack]
                testContexts[i] = Context.new(lastContext)
                const lastExpectationContext = session.expectationContextStack[#session.expectationContextStack]
                testExpectationContexts[i] = ExpectationContext.new(lastExpectationContext)
            end

            -- Now run tests in parallel with global concurrency limit
            for i, childPlanNode in ipairs(itTests) do
                task.spawn(function()
                    -- Wait for a global slot to become available
                    acquireGlobalSlot()

                    log(string.format("  [%d/%d] Starting: %s", i, total, childPlanNode.phrase))

                    -- Create isolated session for this test that writes to the pre-created node
                    const testSession = {
                        results = session.results,
                        nodeStack = { testNodes[i] },
                        contextStack = { testContexts[i] },
                        expectationContextStack = { testExpectationContexts[i] },
                        hasFocusNodes = session.hasFocusNodes,
                    }
                    setmetatable(testSession, { __index = TestSession })

                    const shouldSkip = testSession:shouldSkip()

                    if shouldSkip then
                        log(string.format("  [%d/%d] Skipped: %s", i, total, childPlanNode.phrase))
                        testSession:setSkipped()
                    else
                        -- Run the test (parallel execution here)
                        const testStartTime = os.clock()
                        const success, errorMessage = runNode(childPlanNode)
                        const testDuration = os.clock() - testStartTime

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
                            if Config.Verbose then
                                print("    Error:", errorMessage)
                            end
                        end
                    end

                    -- Release the global slot and update completion count
                    releaseGlobalSlot()
                    while completionLock do
                        task.wait()
                    end
                    completionLock = true
                    completed = completed + 1
                    log(string.format("  Progress: %d/%d complete, %d remaining", completed, total, total - completed))
                    completionLock = false
                end)
            end

            -- Wait for all tests to complete
            while completed < total do
                task.wait()
            end

            const totalDuration = os.clock() - startTime
            log(string.format("Parallel execution complete: %d tests in %.2fs", total, totalDuration))
        elseif #itTests > 0 then
            -- Run tests sequentially
            if not Config.Parallel then
                log(string.format("Running %d tests sequentially (parallel disabled)...", #itTests))
            else
                log(string.format("Running %d tests sequentially...", #itTests))
            end

            for i, childPlanNode in ipairs(itTests) do
                log(string.format("  [%d/%d] Running: %s", i, #itTests, childPlanNode.phrase))
                const testStartTime = os.clock()

                session:pushNode(childPlanNode)
                if session:shouldSkip() then
                    session:setSkipped()
                    log(string.format("  [%d/%d] Skipped: %s", i, #itTests, childPlanNode.phrase))
                else
                    const success, errorMessage = runNode(childPlanNode)
                    const testDuration = os.clock() - testStartTime

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

        -- Process describe blocks in parallel if enabled (using global concurrency limit)
        if Config.Parallel and #describeBlocks > 0 then
            log(string.format("Running %d describe blocks in parallel...", #describeBlocks))
            local completed = 0
            const total = #describeBlocks
            const startTime = os.clock()
            const mutex: { locked: boolean? } = {}

            -- Pre-create result nodes for all describe blocks in the correct order
            const describeNodes = {}
            for i, childPlanNode in ipairs(describeBlocks) do
                const node = TestResults.createNode(childPlanNode)
                const lastNode = session.nodeStack[#session.nodeStack] or session.results
                table.insert(lastNode.children, node)
                describeNodes[i] = node
            end

            for i, childPlanNode in ipairs(describeBlocks) do
                task.spawn(function()
                    log(string.format("  [%d/%d] Starting describe block: %s", i, total, childPlanNode.phrase))
                    const blockStartTime = os.clock()

                    -- Create an isolated sub-session for this describe block
                    -- that will write to our pre-created node
                    const subSession = {
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

                    const Context = require("./Context")
                    const ExpectationContext = require("./ExpectationContext")
                    const lastContext = subSession.contextStack[#subSession.contextStack]
                    const context = Context.new(lastContext)
                    table.insert(subSession.contextStack, context)
                    const lastExpectationContext =
                        subSession.expectationContextStack[#subSession.expectationContextStack]
                    const expectationContext = ExpectationContext.new(lastExpectationContext)
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
                        const message = "Error during planning: " .. childPlanNode.loadError
                        subSession:setError(message)
                        log(string.format("  [%d/%d] ✗ Planning error in: %s", i, total, childPlanNode.phrase))
                    else
                        subSession:setStatusFromChildren()
                    end

                    completed = completed + 1
                    const blockDuration = os.clock() - blockStartTime
                    const remaining = total - completed
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

            const totalDuration = os.clock() - startTime
            log(string.format("Parallel describe block execution complete: %d blocks in %.2fs", total, totalDuration))
        elseif #describeBlocks > 0 then
            -- Run describe blocks sequentially
            for _, childPlanNode in ipairs(describeBlocks) do
                log(string.format("Entering describe block: %s", childPlanNode.phrase))
                session:pushNode(childPlanNode)
                TestRunner.runPlanNode(session, childPlanNode, lifecycleHooks)

                if childPlanNode.loadError then
                    const message = "Error during planning: " .. childPlanNode.loadError
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
        const success, errorMessage = runCallback(hook, "afterAll hook: ")
        if not success then
            session:addDummyError("afterAll", errorMessage)
        end
    end

    lifecycleHooks:popHooks()
end

return TestRunner
