--[[

TestTimeout

Pure helpers for per-test time budgets. Validates budgets, decides which budget applies
to a test, and builds the failure message for a test that ran out of time. Budgets are in
seconds. A nil budget, or math.huge, means the test may run for as long as it likes.

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
