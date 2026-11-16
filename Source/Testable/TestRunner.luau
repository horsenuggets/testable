--[[

TestRunner

Contains the logic to run a test plan and gather test results from it. TestRunner accepts
a TestPlan object, executes the planned tests, and produces a TestResults object. Supports
parallel test execution via task.spawn.

--]]

const Config = require("./Config")
const LifecycleHooks = require("./LifecycleHooks")
const SnapshotManager = require("./Snapshots/SnapshotManager")
const SpecApi = require("./SpecApi")
const task = if task then task else require("@lune/task")
const TestEnum = require("./TestEnum")
const TestFilter = require("./TestFilter")
const TestResults = require("./TestResults")
const TestScope = require("./TestScope")
const TestSession = require("./TestSession")
const TestTimeout = require("./TestTimeout")

const RUNNING_GLOBAL = "__TESTABLE_RUNNING_TEST__"
const RUNNING_COUNT_GLOBAL = "__TESTABLE_RUNNING_COUNT__"

const TestRunner = {
    environment = {},
}

-- Helper to acquire a slot of the semaphore that limits concurrent test execution across
-- all describe blocks of one run. Every run has its own semaphore (see TestSession.new),
-- because a test that starts a nested run holds its slot until the nested run finishes.
-- If both shared one semaphore, the nested tests could wait forever for slots that are
-- all held by the tests waiting on them.
const function acquireGlobalSlot(globalSemaphore: TestSession.Semaphore)
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

-- Helper to release a slot of a run's semaphore
const function releaseGlobalSlot(globalSemaphore: TestSession.Semaphore)
    while globalSemaphore.lock do
        task.wait()
    end
    globalSemaphore.lock = true
    globalSemaphore.activeCount = globalSemaphore.activeCount - 1
    globalSemaphore.lock = false
end

-- Lowers the count of running tests and only clears the flag when no tests are running
const function releaseRunningFlag()
    _G[RUNNING_COUNT_GLOBAL] = (_G[RUNNING_COUNT_GLOBAL] or 1) - 1
    if _G[RUNNING_COUNT_GLOBAL] <= 0 then
        _G[RUNNING_GLOBAL] = nil
        _G[RUNNING_COUNT_GLOBAL] = nil
    end
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
    Runs the given TestPlan and returns a TestResults object representing the
    results of the run.

    @param plan - The TestPlan to execute
    @return TestResults object containing the test execution results
]]
function TestRunner.runPlan(plan: any): any
    log("Starting test plan execution...")
    const session = TestSession.new(plan)
    const planStartTime = os.clock()
    const lifecycleHooks = LifecycleHooks.new()

    session.hasFocusNodes = TestFilter.hasFocus(plan)

    -- Read the snapshot settings before tests run, since tests may call Config.reset().
    const snapshots = SnapshotManager.new({ Store = Config.SnapshotStore, Update = Config.UpdateSnapshots })
    session.results.snapshots = snapshots

    -- The plan captured the focus guard before any spec code ran, so neither planning nor
    -- the tests themselves can turn it off.
    session.forbidFocus = plan.forbidFocus == true

    if session.hasFocusNodes then
        log("Focus nodes detected, other tests will be skipped.")
    end

    TestRunner.runPlanNode(session, plan, lifecycleHooks)

    log("Test plan execution complete.")

    const results = session:finalize()
    results.duration = os.clock() - planStartTime

    -- A focused or filtered run skips tests, so their snapshots must not be mistaken for
    -- obsolete.
    results.snapshotSummary = snapshots:Finish(results, session.hasFocusNodes or plan.filter ~= nil)

    return results
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

        @param callbackSession - The session whose current node the callback belongs to
        @param callback - The function to execute
        @param messagePrefix - Optional prefix for error messages
        @return success: boolean, errorMessage: string?
    ]]
    const function runCallback(
        callbackSession: any,
        callback: (any) -> (),
        inputMessagePrefix: string?
    ): (boolean, string?)
        local success = true
        local errorMessage
        -- Any code can check RUNNING_GLOBAL to fork behavior based on
        -- whether a test is running. We use this to avoid accessing
        -- protected APIs; it's a workaround that will go away someday.
        -- Use a counter instead of boolean to handle parallel test execution safely.
        _G[RUNNING_COUNT_GLOBAL] = (_G[RUNNING_COUNT_GLOBAL] or 0) + 1
        _G[RUNNING_GLOBAL] = true

        const messagePrefix: string = inputMessagePrefix or ""

        const scope: TestScope.RunScope = {
            ExpectationContext = callbackSession:getExpectationContext(),
            Fail = function(message: string)
                success = false
                errorMessage = messagePrefix .. message
            end,
            Finished = false,
        }

        if Config.InjectGlobals then
            const testEnvironment = getfenv(callback)

            for key, value in pairs(TestRunner.environment) do
                testEnvironment[key] = value
            end

            -- Callbacks declared in the same describe block share one environment, so
            -- these bindings are overwritten by whichever callback started last. They
            -- prefer the scope of the calling coroutine and only fall back to this one
            -- for threads that Testable can't tie to a test.
            testEnvironment.fail = SpecApi.createFail(scope)
            testEnvironment.expect = SpecApi.createExpect(scope)
        end

        const context = callbackSession:getContext()

        -- The scope stays on this coroutine's stack while the callback runs, including
        -- across yields, so that the requirable `expect` and `fail` can find it.
        TestScope.enterRun(scope)

        const nodeSuccess, nodeResult = xpcall(function()
            callback(context)
        end, function(message)
            return messagePrefix .. debug.traceback(tostring(message), 2)
        end)

        TestScope.exit()
        scope.Finished = true

        -- If a node threw an error, we prefer to use that message over
        -- one created by fail() if it was set.
        if not nodeSuccess then
            success = false
            errorMessage = nodeResult
        end

        releaseRunningFlag()

        return success, errorMessage
    end

    --[[
        Runs a callback like runCallback, but gives up on it once it has been running for
        longer than the given budget. The callback runs in its own thread so that it can
        be cancelled while the calling thread waits for whichever comes first, the
        callback finishing or the budget running out. Only a callback that yields can be
        interrupted. One that never yields blocks the scheduler, so nothing else gets a
        chance to run until it returns on its own.

        @param callbackSession - The session whose current node the callback belongs to
        @param callback - The function to execute
        @param subject - What is running, for the timeout message
        @param messagePrefix - Optional prefix for error messages
        @param budget - The budget in seconds, or nil to run without a limit
        @param source - Where the budget came from, for the timeout message
        @return success: boolean, errorMessage: string?
    ]]
    const function runCallbackWithBudget(
        callbackSession: any,
        callback: (any) -> (),
        subject: string,
        messagePrefix: string?,
        budget: number?,
        source: string?
    ): (boolean, string?)
        if budget == nil then
            return runCallback(callbackSession, callback, messagePrefix)
        end

        const waiter = coroutine.running()
        local finished = false
        local success = false
        local errorMessage: string? = nil
        local timedOut = false
        local waiting = false

        -- The clock starts before the callback does, because task.spawn runs the callback
        -- up to its first yield before it returns.
        const startTime = os.clock()

        const thread = task.spawn(function()
            success, errorMessage = runCallback(callbackSession, callback, messagePrefix)
            finished = true
            if waiting then
                task.spawn(waiter)
            end
        end)

        if not finished then
            const timer = task.delay(math.max(budget - (os.clock() - startTime), 0), function()
                finished = true
                timedOut = true
                -- The cancelled thread never reaches the end of runCallback, so the
                -- running flag it raised has to be released here instead.
                pcall(task.cancel, thread)
                releaseRunningFlag()
                task.spawn(waiter)
            end)

            waiting = true
            coroutine.yield()

            if not timedOut then
                task.cancel(timer)
            end
        end

        -- A callback that finished on its own can still be over budget, since work that
        -- never yields cannot be interrupted. An error it raised itself is kept.
        if timedOut or (success and os.clock() - startTime > budget) then
            return false, TestTimeout.formatMessage(subject, budget, source :: string)
        end

        return success, errorMessage
    end

    const function runNode(testSession, childPlanNode)
        -- Errors can be set either via `error` propagating upwards or
        -- by a test calling fail([message]).

        -- The test and each of its beforeEach and afterEach hooks get the budget
        -- separately, so a slow hook cannot use up the time of the test itself.
        const budget, budgetSource = TestTimeout.resolve(childPlanNode.timeout, Config.Timeout)

        for _, hook in ipairs(lifecycleHooks:getBeforeEachHooks()) do
            const success, errorMessage = runCallbackWithBudget(
                testSession,
                hook,
                "The beforeEach hook",
                "beforeEach hook: ",
                budget,
                budgetSource
            )
            if not success then
                return false, errorMessage
            end
        end

        const testSuccess, testErrorMessage =
            runCallbackWithBudget(testSession, childPlanNode.callback, "The test", nil, budget, budgetSource)

        for _, hook in ipairs(lifecycleHooks:getAfterEachHooks()) do
            const success, errorMessage =
                runCallbackWithBudget(testSession, hook, "The afterEach hook", "afterEach hook: ", budget, budgetSource)
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

    -- A describe block that the filter left no tests in isn't part of the run, so its
    -- beforeAll and afterAll hooks don't run. Its tests are still visited below so that
    -- they are reported as skipped.
    const filteredOut = TestFilter.excludes(session.results.planNode, planNode)

    local halt = false
    for _, hook in ipairs(if filteredOut then {} else lifecycleHooks:getBeforeAllHooks()) do
        const success, errorMessage = runCallback(session, hook, "beforeAll hook: ")
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
                    acquireGlobalSlot(session.semaphore)

                    log(string.format("  [%d/%d] Starting: %s", i, total, childPlanNode.phrase))

                    -- Create isolated session for this test that writes to the pre-created node
                    -- The node stack keeps the test's ancestors so that a focus or skip
                    -- modifier on an enclosing describe block still applies to it.
                    const testNodeStack = table.clone(session.nodeStack)
                    table.insert(testNodeStack, testNodes[i])

                    const testSession = {
                        results = session.results,
                        nodeStack = testNodeStack,
                        contextStack = { testContexts[i] },
                        expectationContextStack = { testExpectationContexts[i] },
                        hasFocusNodes = session.hasFocusNodes,
                    }
                    setmetatable(testSession, { __index = TestSession })

                    const shouldSkip, skipReason, excludedByFocus = testSession:shouldSkip()

                    if shouldSkip then
                        log(string.format("  [%d/%d] Skipped: %s", i, total, childPlanNode.phrase))
                        testSession:setSkipped(skipReason, excludedByFocus)
                    else
                        -- Run the test (parallel execution here)
                        const testStartTime = os.clock()
                        const success, errorMessage = runNode(testSession, childPlanNode)
                        const testDuration = os.clock() - testStartTime
                        testNodes[i].duration = testDuration

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
                    releaseGlobalSlot(session.semaphore)
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
                const shouldSkip, skipReason, excludedByFocus = session:shouldSkip()
                if shouldSkip then
                    session:setSkipped(skipReason, excludedByFocus)
                    log(string.format("  [%d/%d] Skipped: %s", i, #itTests, childPlanNode.phrase))
                else
                    const success, errorMessage = runNode(session, childPlanNode)
                    const testDuration = os.clock() - testStartTime
                    session.nodeStack[#session.nodeStack].duration = testDuration

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
                        -- Starts from the ancestors so that their focus and skip
                        -- modifiers still apply inside this describe block.
                        nodeStack = table.clone(session.nodeStack),
                        contextStack = {},
                        expectationContextStack = {},
                        hasFocusNodes = session.hasFocusNodes,
                        semaphore = session.semaphore,
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

                    -- Run the describe block with its own isolated session and hook stack
                    TestRunner.runPlanNode(subSession, childPlanNode, lifecycleHooks:fork())

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
                    describeNodes[i].duration = blockDuration
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
                const blockStartTime = os.clock()
                session:pushNode(childPlanNode)
                TestRunner.runPlanNode(session, childPlanNode, lifecycleHooks)
                session.nodeStack[#session.nodeStack].duration = os.clock() - blockStartTime

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

    for _, hook in ipairs(if filteredOut then {} else lifecycleHooks:getAfterAllHooks()) do
        const success, errorMessage = runCallback(session, hook, "afterAll hook: ")
        if not success then
            session:addDummyError("afterAll", errorMessage)
        end
    end

    lifecycleHooks:popHooks()
end

return TestRunner
