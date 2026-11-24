--[[

SpecApi

The spec API as plain functions that a spec can require from Testable and keep in locals
(e.g., `const describe, it, expect = Testable.describe, Testable.it, Testable.expect`),
instead of relying on globals injected into the spec function. Each function looks up what
the calling coroutine is doing through TestScope and forwards to the describe block being
collected or the test being run.

The functions are generated from the table TestPlan.newEnvironment builds, so anything
added there is exported from here without a second list to maintain. Only the types below
are written by hand, and SpecApiTest fails when they fall behind.

--]]

const Expectation = require("./Expectation")
const TestPlan = require("./TestPlan")
const TestScope = require("./TestScope")

-- The result a custom matcher returns. The lowercase keys are the TestEZ matcher contract.
export type MatcherResult = {
    message: string?,
    pass: boolean
}

-- A custom matcher passed to `expect.extend`, called with the received value first.
export type Matcher = (received: any, ...any) -> MatcherResult

-- A built-in matcher, which can be called with a dot (`expect(1).to.equal(1)`) or with a
-- colon (`expect(1).to:equal(1)`) and returns the expectation so that chains can continue.
type MatcherMethod<Self, Arguments...> = ((Arguments...) -> Self) & ((self: Self, Arguments...) -> Self)

--[[
    The chain returned by `expect(value)`. Pass the shape of any custom matchers as
    `Custom` to have them typed too, e.g. `Expectation<{ beEven: () -> any }>`.

    When adding a built-in matcher to Expectation, add it to the matcher group below.
]]
export type Expectation<Custom = {}> = Custom & {
    -- Words that only make a chain read better.
    at: Expectation<Custom>,
    be: Expectation<Custom>,
    been: Expectation<Custom>,
    have: Expectation<Custom>,
    to: Expectation<Custom>,
    was: Expectation<Custom>,

    -- Inverts the matcher that follows.
    never: Expectation<Custom>,

    -- Matchers, each listed with the arguments it takes after the expectation itself.
    a: MatcherMethod<Expectation<Custom>, string>,
    an: MatcherMethod<Expectation<Custom>, string>,
    contain: MatcherMethod<Expectation<Custom>, any>,
    deepEqual: MatcherMethod<Expectation<Custom>, any>,
    equal: MatcherMethod<Expectation<Custom>, any>,
    falsy: MatcherMethod<Expectation<Custom>, ()>,
    greaterThan: MatcherMethod<Expectation<Custom>, number | string>,
    greaterThanOrEqual: MatcherMethod<Expectation<Custom>, number | string>,
    length: MatcherMethod<Expectation<Custom>, number>,
    lessThan: MatcherMethod<Expectation<Custom>, number | string>,
    lessThanOrEqual: MatcherMethod<Expectation<Custom>, number | string>,
    match: MatcherMethod<Expectation<Custom>, string>,
    matchSnapshot: MatcherMethod<Expectation<Custom>, string?>,
    near: MatcherMethod<Expectation<Custom>, (number, number?)>,
    none: MatcherMethod<Expectation<Custom>, ()>,
    ok: MatcherMethod<Expectation<Custom>, ()>,
    throw: MatcherMethod<Expectation<Custom>, string?>,
    truthy: MatcherMethod<Expectation<Custom>, ()>
}

-- The `expect` function, which also carries `expect.extend` for adding custom matchers.
export type Expect<Custom = {}> = ((value: any) -> Expectation<Custom>) & {
    extend: (matchers: { [string]: Matcher }) -> ()
}

-- The options a describe block accepts as the third argument of `describe`.
export type BlockOptions = {
    -- Runs the tests of the block one at a time, with no other test of the run executing
    -- while they do. What tests that share global state need.
    Serial: boolean?
}

-- The options a single test accepts as the third argument of `it`.
export type TestOptions = {
    -- Runs the test with no other test of the run executing at the same time. What tests
    -- that share global state need.
    Serial: boolean?,
    -- The time budget of the test in seconds, which wins over the configured Timeout.
    Timeout: number?
}

-- The options a lifecycle hook accepts as its second argument.
export type HookOptions = {
    -- The time budget of the hook in seconds, which wins over the one it would inherit.
    Timeout: number?
}

type Callback = (...any) -> ...any
type Declare = (phrase: string, callback: Callback, options: BlockOptions?) -> ()
-- A skip variant, which takes an optional reason that is reported with the skipped tests.
type DeclareSkipped = (phrase: string, callback: Callback, reason: string?) -> ()
type DeclareTest = (phrase: string, callback: Callback, options: TestOptions?) -> ()
type Hook = (callback: Callback, options: HookOptions?) -> ()

--[[
    Everything a spec can require from Testable. Apart from `bindTest`, `expect`, and
    `fail`, every field mirrors an entry of the table TestPlan.newEnvironment builds, so
    add a field here whenever an entry is added there.
]]
export type Api = {
    afterAll: Hook,
    afterEach: Hook,
    beforeAll: Hook,
    beforeEach: Hook,
    bindTest: <Arguments..., Returns...>(callback: (Arguments...) -> Returns...) -> (Arguments...) -> Returns...,
    describe: Declare,
    describeFOCUS: Declare,
    describeSKIP: DeclareSkipped,
    expect: Expect,
    fail: (message: any?) -> (),
    fdescribe: Declare,
    fit: DeclareTest,
    FIXME: (message: string?) -> (),
    FOCUS: () -> (),
    HACK_NO_XPCALL: () -> (),
    it: DeclareTest,
    itFIXME: (phrase: string, callback: Callback, message: string?) -> (),
    itFOCUS: DeclareTest,
    itSKIP: DeclareSkipped,
    itTODO: (phrase: string) -> (),
    SKIP: (reason: string?) -> (),
    xdescribe: DeclareSkipped,
    xit: DeclareSkipped
}

const OUTSIDE_COLLECTION_HINT = "Tests, describe blocks, and hooks must be registered while the spec is being "
    .. "collected, from the spec function or a describe body that Testable is running."
const UNKNOWN_THREAD_HINT = "Testable only knows which test a call belongs to on the coroutine that runs the test "
    .. "or hook. Call it from there, or wrap the function that other threads run with Testable.bindTest."

const SpecApi = {}

--[[
    Returns the scope a run-time call belongs to. The scope of the calling coroutine wins,
    and the fallback covers callers that are bound to a scope some other way.
]]
const function resolveRunScope(fallbackScope: TestScope.RunScope?): TestScope.RunScope?
    return TestScope.getRunScope() or fallbackScope
end

--[[
    Creates a `fail` function. It fails the test or hook the calling coroutine is running,
    or the one of the fallback scope when the coroutine is not running one.

    @param fallbackScope - The scope to use for calls from coroutines without their own
    @return The `fail` function
]]
function SpecApi.createFail(fallbackScope: TestScope.RunScope?): (message: any?) -> ()
    return function(message: any?)
        const scope = resolveRunScope(fallbackScope)

        if scope == nil then
            error(`Cannot call "fail" outside of a running test or hook. {UNKNOWN_THREAD_HINT}`, 2)
        end
        if scope.Finished then
            error('Cannot call "fail" after its test or hook has finished running.', 2)
        end

        scope.Fail(debug.traceback(tostring(if message == nil then "fail() was called." else message), 2))
    end
end

--[[
    Creates an `expect` function. Custom matchers come from the test or hook the calling
    coroutine is running, or from the fallback scope when the coroutine is not running
    one. Without either, only the built-in matchers are available.

    @param fallbackScope - The scope to use for calls from coroutines without their own
    @return The callable `expect` table
]]
function SpecApi.createExpect(fallbackScope: TestScope.RunScope?): Expect
    const expect = setmetatable({
        extend = function(matchers: { [string]: Matcher })
            const scope = resolveRunScope(fallbackScope)

            if scope == nil then
                if TestScope.getCollectingNode() ~= nil then
                    error('Cannot call "expect.extend" from within a "describe" node.', 2)
                end
                error(`Cannot call "expect.extend" outside of a running test or hook. {UNKNOWN_THREAD_HINT}`, 2)
            end

            scope.ExpectationContext:extend(matchers)
        end
    }, {
        __call = function(_self, ...)
            const scope = resolveRunScope(fallbackScope)

            if scope == nil then
                return Expectation.new(...)
            end

            return scope.ExpectationContext:startExpectationChain(...)
        end
    })

    return expect :: any
end

--[[
    Wraps a function so that whichever coroutine calls it counts as part of the test or
    hook that is running right now. Use it for callbacks a test hands to other threads
    (e.g., through task.spawn), which Testable otherwise can't tie back to the test.

    @param callback - The function that other coroutines will call
    @return The wrapped function, which passes arguments and results through
]]
function SpecApi.bindTest<Arguments..., Returns...>(callback: (Arguments...) -> Returns...): (Arguments...) -> Returns...
    assert(type(callback) == "function", "callback must be a function")

    const scope = TestScope.getRunScope()
    if scope == nil then
        error('Cannot call "bindTest" outside of a running test or hook.', 2)
    end

    return function(...)
        TestScope.enterRun(scope)
        const results = table.pack(pcall(callback, ...))
        TestScope.exit()

        if not results[1] then
            error(results[2], 0)
        end

        return table.unpack(results, 2, results.n)
    end
end

--[[
    Creates the function exported for one key of the spec environment. It forwards to the
    entry with the same key in the environment of the node being collected.
]]
const function createCollector(key: string): Callback
    return function(...)
        const node = TestScope.getCollectingNode()

        if node == nil then
            if TestScope.getRunScope() ~= nil then
                error(`Cannot call "{key}" while a test or hook is running. {OUTSIDE_COLLECTION_HINT}`, 2)
            end
            error(`Cannot call "{key}" outside of a spec. {OUTSIDE_COLLECTION_HINT}`, 2)
        end

        return node.environment[key](...)
    end
end

--[[
    Builds the requirable API. The keys come from a spec environment built for a
    placeholder node, which is safe because the environment only touches its node when one
    of its functions is called.

    @return The table of functions that Testable exports to specs
]]
function SpecApi.create(): Api
    const api = {}

    for key, value in TestPlan.newEnvironment({}) do
        if type(value) == "function" then
            api[key] = createCollector(key)
        end
    end

    api.bindTest = SpecApi.bindTest
    api.expect = SpecApi.createExpect()
    api.fail = SpecApi.createFail()

    return api :: any
end

return SpecApi
