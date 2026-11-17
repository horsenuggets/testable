--[[

TestTimeout

Pure helpers for time budgets. Validates budgets, decides which budget applies to a test
or a lifecycle hook, and builds the failure message for one that ran out of time. Budgets
are in seconds. A nil budget, or math.huge, means there is no limit.

--]]

const TestTimeout = {}

--[[
    Checks that a value is usable as a time budget, which means a number greater than
    zero. math.huge is allowed and means no limit.

    @param value - The value to check
    @return valid - True if the value is a usable budget
]]
function TestTimeout.isValid(value: any): boolean
    return type(value) == "number" and value > 0
end

--[[
    Decides which budget applies to a test. A budget set on the test itself wins over the
    configured one, and math.huge turns the limit off.

    @param testTimeout - The budget set on the test, if any
    @param configTimeout - The configured budget, if any
    @return budget - The budget in seconds, or nil when the test has no limit
    @return source - Where the budget came from, or nil when the test has no limit
]]
function TestTimeout.resolve(testTimeout: number?, configTimeout: number?): (number?, string?)
    assert(testTimeout == nil or TestTimeout.isValid(testTimeout), "testTimeout must be a positive number")
    assert(configTimeout == nil or TestTimeout.isValid(configTimeout), "configTimeout must be a positive number")

    local budget = configTimeout
    local source = "the Timeout configuration option"
    if testTimeout ~= nil then
        budget = testTimeout
        source = "the Timeout option of the test"
    end

    if budget == nil or budget == math.huge then
        return nil, nil
    end

    return budget, source
end

--[[
    Decides which budget applies to a lifecycle hook. A budget set on the hook itself wins
    over the one it would otherwise inherit, and math.huge turns the limit off. A
    beforeEach or afterEach hook inherits the budget of the test it surrounds, while a
    beforeAll or afterAll hook inherits the configured one.

    @param hookTimeout - The budget set on the hook, if any
    @param inheritedBudget - The budget the hook falls back to, if any
    @param inheritedSource - Where the inherited budget came from, if there is one
    @return budget - The budget in seconds, or nil when the hook has no limit
    @return source - Where the budget came from, or nil when the hook has no limit
]]
function TestTimeout.resolveHook(
    hookTimeout: number?,
    inheritedBudget: number?,
    inheritedSource: string?
): (number?, string?)
    assert(hookTimeout == nil or TestTimeout.isValid(hookTimeout), "hookTimeout must be a positive number")
    assert(inheritedBudget == nil or TestTimeout.isValid(inheritedBudget), "inheritedBudget must be a positive number")
    assert(inheritedSource == nil or type(inheritedSource) == "string", "inheritedSource must be a string or nil")
    assert(
        (inheritedBudget == nil) == (inheritedSource == nil),
        "inheritedBudget and inheritedSource must be given together"
    )

    if hookTimeout == nil then
        if inheritedBudget == math.huge then
            return nil, nil
        end
        return inheritedBudget, inheritedSource
    end

    if hookTimeout == math.huge then
        return nil, nil
    end

    return hookTimeout, "the Timeout option of the hook"
end

--[[
    Builds the failure message for something that ran out of time.

    @param subject - What timed out, such as "Test" or "beforeEach hook"
    @param budget - The budget in seconds that was exceeded
    @param source - Where the budget came from
    @return message - The failure message
]]
function TestTimeout.formatMessage(subject: string, budget: number, source: string): string
    assert(type(subject) == "string", "subject must be a string")
    assert(TestTimeout.isValid(budget), "budget must be a positive number")
    assert(type(source) == "string", "source must be a string")

    const unit = if budget == 1 then "second" else "seconds"
    return `{subject} timed out after exceeding its budget of {string.format("%g", budget)} {unit}, set by {source}.`
end

return TestTimeout
