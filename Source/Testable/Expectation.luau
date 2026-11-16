--!nocheck

--[[

Expectation

Allows creation of expectation statements designed for behavior-driven testing (BDD).
The Expectation class is exposed to tests as a function called `expect`. Expectations
can be negated using `.never` and throw errors when their conditions are not met.

--]]

const ValueInspector = require("./ValueInspector")

--[[
    The stack level that points at the test code calling a matcher. From a helper called
    by a matcher, the levels are the helper (1), the matcher (2), the bound wrapper made
    by bindSelf (3), and the test (4).
]]
const CALLER_LEVEL = 4
--[[
    Every built-in matcher. Each one is bound to its expectation so that it can be called
    with either . or :
]]
const MATCHER_NAMES = {
    "a",
    "an",
    "contain",
    "deepEqual",
    "equal",
    "falsy",
    "greaterThan",
    "greaterThanOrEqual",
    "length",
    "lessThan",
    "lessThanOrEqual",
    "match",
    "near",
    "none",
    "ok",
    "throw",
    "truthy",
}
--[[
    These keys invert the condition expressed by the Expectation.
]]
const NEGATION_KEYS = {
    never = true,
}
--[[
    These keys don't do anything except make expectations read more cleanly
]]
const SELF_KEYS = {
    to = true,
    be = true,
    been = true,
    have = true,
    was = true,
    at = true,
}

const Expectation = {}

--[[
    Extension of Lua's 'assert' that lets you specify an error level.
]]
const function assertLevel(condition, message, level)
    message = message or "Assertion failed!"
    level = level or 1

    if not condition then
        error(message, level + 1)
    end
end

--[[
    Returns a version of the given method that can be called with either . or :
]]
const function bindSelf(self, method)
    return function(firstArg, ...)
        if firstArg == self then
            return method(self, ...)
        else
            return method(self, firstArg, ...)
        end
    end
end

const function formatMessage(result, trueMessage, falseMessage)
    if result then
        return trueMessage
    else
        return falseMessage
    end
end

--[[
    Describes a value's kind for misuse messages (e.g., "a number", "nil").
]]
const function describeKind(value)
    const kind = typeof(value)

    if kind == "nil" then
        return "nil"
    end

    return `a {kind} value`
end

--[[
    Fails the test because a matcher was used incorrectly, regardless of negation. Must be
    called directly from a matcher so that the error points at the test.
]]
const function misuse(matcherName, detail)
    error(`Matcher "{matcherName}" {detail}`, CALLER_LEVEL)
end

--[[
    Builds a failure message with "Expected" and "Received" lines. The expected line is
    prefixed with "never" when the expectation is negated.
]]
const function comparisonMessage(self, headline, expected, received)
    const expectedPrefix = if self.successCondition then "" else "never "

    return table.concat({
        headline,
        `Expected: {expectedPrefix}{expected}`,
        `Received: {received}`,
    }, "\n")
end

const function isCallable(value)
    if type(value) == "function" then
        return true
    end

    if type(value) == "table" then
        const metatable = getmetatable(value)

        return type(metatable) == "table" and type(rawget(metatable, "__call")) == "function"
    end

    return false
end

--[[
    Create a new expectation
]]
function Expectation.new(value)
    const self = {
        value = value,
        successCondition = true,
        condition = false,
        matchers = {},
        _boundMatchers = {},
    }

    setmetatable(self, Expectation)

    for _, name in MATCHER_NAMES do
        self[name] = bindSelf(self, Expectation[name])
    end

    return self
end

function Expectation.checkMatcherNameCollisions(name)
    if SELF_KEYS[name] or NEGATION_KEYS[name] or Expectation[name] then
        return false
    end

    return true
end

function Expectation:extend(matchers)
    self.matchers = matchers or {}

    for name, implementation in pairs(self.matchers) do
        self._boundMatchers[name] = bindSelf(self, function(_self, ...)
            const result = implementation(self.value, ...)
            const pass = result.pass == self.successCondition

            assertLevel(pass, result.message, 3)
            self:_resetModifiers()
            return self
        end)
    end

    return self
end

function Expectation.__index(self, key)
    -- Keys that don't do anything except improve readability
    if SELF_KEYS[key] then
        return self
    end

    -- Invert your assertion
    if NEGATION_KEYS[key] then
        const newExpectation = Expectation.new(self.value):extend(self.matchers)
        newExpectation.successCondition = not self.successCondition

        return newExpectation
    end

    if self._boundMatchers[key] then
        return self._boundMatchers[key]
    end

    -- Fall back to methods provided by Expectation
    return Expectation[key]
end

--[[
    Called by expectation terminators to reset modifiers in a statement.

    This makes chains like:

        expect(5)
            .never.to.equal(6)
            .to.equal(5)

    Work as expected.
]]
function Expectation:_resetModifiers()
    self.successCondition = true
end

--[[
    Called by matchers to finish an assertion. Fails the test when the condition does not
    agree with the current negation, then resets modifiers so that chaining keeps working.
    The message is built lazily so that passing assertions never pay for formatting. Must
    be called directly from a matcher so that the error points at the test.
]]
function Expectation:_finish(condition, getMessage)
    if (not not condition) ~= self.successCondition then
        error(getMessage(), CALLER_LEVEL)
    end

    self:_resetModifiers()

    return self
end

--[[
    Assert that the expectation value is the given type. The name can be either what
    typeof() reports (e.g., "Vector3") or what type() reports (e.g., "userdata").

    expect(5).to.be.a("number")
    expect(Vector3.zero).to.be.a("Vector3")
]]
function Expectation:a(typeName)
    if type(typeName) ~= "string" then
        misuse("a", `expects a type name string, but received {describeKind(typeName)}.`)
    end

    const primitiveType = type(self.value)
    const richType = typeof(self.value)

    return self:_finish(primitiveType == typeName or richType == typeName, function()
        return formatMessage(
            self.successCondition,
            ("Expected value of type %q, got value %s of type %s"):format(
                typeName,
                ValueInspector.format(self.value),
                richType
            ),
            ("Expected value not of type %q, got value %s of type %s"):format(
                typeName,
                ValueInspector.format(self.value),
                richType
            )
        )
    end)
end

-- Make alias public on class
Expectation.an = Expectation.a

--[[
    Assert that our expectation value is not nil
]]
function Expectation:ok()
    return self:_finish(self.value ~= nil, function()
        return formatMessage(
            self.successCondition,
            ("Expected value %q to be non-nil"):format(tostring(self.value)),
            ("Expected value %q to be nil"):format(tostring(self.value))
        )
    end)
end

--[[
    Assert that our expectation value is nil

    expect(nil).to.be.none()
]]
function Expectation:none()
    return self:_finish(self.value == nil, function()
        return comparisonMessage(self, "Expected value to be nil.", "nil", ValueInspector.format(self.value))
    end)
end

--[[
    Assert that our expectation value is truthy, meaning anything except false and nil

    expect(0).to.be.truthy()
]]
function Expectation:truthy()
    return self:_finish(self.value, function()
        return comparisonMessage(
            self,
            "Expected value to be truthy.",
            "a truthy value",
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value is falsy, meaning false or nil

    expect(false).to.be.falsy()
]]
function Expectation:falsy()
    return self:_finish(not self.value, function()
        return comparisonMessage(
            self,
            "Expected value to be falsy.",
            "a falsy value",
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value is equal to another value
]]
function Expectation:equal(otherValue)
    return self:_finish(self.value == otherValue, function()
        local headline = "Expected values to be equal."

        if
            self.successCondition
            and type(self.value) == "table"
            and type(otherValue) == "table"
            and ValueInspector.deepEqual(self.value, otherValue)
        then
            headline ..= ' The tables have the same contents but are different references, so use "deepEqual" to compare by contents.'
        end

        return comparisonMessage(
            self,
            headline,
            `{ValueInspector.format(otherValue)} ({typeof(otherValue)})`,
            `{ValueInspector.format(self.value)} ({typeof(self.value)})`
        )
    end)
end

--[[
    Assert that our expectation value is structurally equal to another value. Tables are
    compared recursively by contents, and NaN is considered equal to NaN.

    expect({ 1, { 2 } }).to.deepEqual({ 1, { 2 } })
]]
function Expectation:deepEqual(otherValue)
    return self:_finish(ValueInspector.deepEqual(self.value, otherValue), function()
        return comparisonMessage(
            self,
            "Expected values to be deeply equal.",
            ValueInspector.format(otherValue),
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value contains another value. Strings are searched for a
    plain substring, and arrays are searched for a deeply equal element.

    expect("hello world").to.contain("world")
    expect({ 1, 2, 3 }).to.contain(2)
]]
function Expectation:contain(item)
    local found = false

    if type(self.value) == "string" then
        if type(item) ~= "string" then
            misuse("contain", `expects a string to search a string for, but received {describeKind(item)}.`)
        end

        found = self.value:find(item, 1, true) ~= nil
    elseif type(self.value) == "table" then
        for _, element in ipairs(self.value) do
            if ValueInspector.deepEqual(element, item) then
                found = true
                break
            end
        end
    else
        misuse("contain", `expects the value to be a string or a table, but it is {describeKind(self.value)}.`)
    end

    return self:_finish(found, function()
        return comparisonMessage(
            self,
            if type(self.value) == "string"
                then "Expected string to contain the substring."
                else "Expected array to contain the element.",
            ValueInspector.format(item),
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that the length of our expectation value, as reported by #, is the given number

    expect({ 1, 2, 3 }).to.have.length(3)
]]
function Expectation:length(expectedLength)
    if type(self.value) ~= "string" and type(self.value) ~= "table" then
        misuse("length", `expects the value to be a string or a table, but it is {describeKind(self.value)}.`)
    end

    if type(expectedLength) ~= "number" then
        misuse("length", `expects a number for the length, but received {describeKind(expectedLength)}.`)
    end

    const actualLength = #self.value

    return self:_finish(actualLength == expectedLength, function()
        const message = comparisonMessage(
            self,
            "Expected value to have the given length.",
            `length {ValueInspector.format(expectedLength)}`,
            `length {actualLength}`
        )

        return `{message}\nValue: {ValueInspector.format(self.value)}`
    end)
end

--[[
    Assert that our string expectation value matches a Luau string pattern

    expect("abc123").to.match("%a+%d+")
]]
function Expectation:match(pattern)
    if type(self.value) ~= "string" then
        misuse("match", `expects the value to be a string, but it is {describeKind(self.value)}.`)
    end

    if type(pattern) ~= "string" then
        misuse("match", `expects a string pattern, but received {describeKind(pattern)}.`)
    end

    const ok, found = pcall(string.find, self.value, pattern)

    if not ok then
        misuse("match", `received the malformed pattern {ValueInspector.format(pattern)}. {tostring(found)}`)
    end

    return self:_finish(found ~= nil, function()
        return comparisonMessage(
            self,
            "Expected string to match the pattern.",
            `pattern {ValueInspector.format(pattern)}`,
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Returns whether the expectation value and the other value can be ordered against each
    other, which is only true for two numbers or two strings.
]]
const function isOrderable(value, otherValue)
    const valueType = type(value)

    return (valueType == "number" or valueType == "string") and valueType == type(otherValue)
end

const function describeOrderingMisuse(value, otherValue)
    return `expects two numbers or two strings, but the value is {describeKind(value)} and it received {describeKind(
        otherValue
    )}.`
end

--[[
    Assert that our expectation value is greater than another value

    expect(5).to.be.greaterThan(3)
]]
function Expectation:greaterThan(otherValue)
    if not isOrderable(self.value, otherValue) then
        misuse("greaterThan", describeOrderingMisuse(self.value, otherValue))
    end

    return self:_finish(self.value > otherValue, function()
        return comparisonMessage(
            self,
            "Expected value to be greater than the bound.",
            `> {ValueInspector.format(otherValue)}`,
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value is greater than or equal to another value

    expect(5).to.be.greaterThanOrEqual(5)
]]
function Expectation:greaterThanOrEqual(otherValue)
    if not isOrderable(self.value, otherValue) then
        misuse("greaterThanOrEqual", describeOrderingMisuse(self.value, otherValue))
    end

    return self:_finish(self.value >= otherValue, function()
        return comparisonMessage(
            self,
            "Expected value to be greater than or equal to the bound.",
            `>= {ValueInspector.format(otherValue)}`,
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value is less than another value

    expect(3).to.be.lessThan(5)
]]
function Expectation:lessThan(otherValue)
    if not isOrderable(self.value, otherValue) then
        misuse("lessThan", describeOrderingMisuse(self.value, otherValue))
    end

    return self:_finish(self.value < otherValue, function()
        return comparisonMessage(
            self,
            "Expected value to be less than the bound.",
            `< {ValueInspector.format(otherValue)}`,
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value is less than or equal to another value

    expect(5).to.be.lessThanOrEqual(5)
]]
function Expectation:lessThanOrEqual(otherValue)
    if not isOrderable(self.value, otherValue) then
        misuse("lessThanOrEqual", describeOrderingMisuse(self.value, otherValue))
    end

    return self:_finish(self.value <= otherValue, function()
        return comparisonMessage(
            self,
            "Expected value to be less than or equal to the bound.",
            `<= {ValueInspector.format(otherValue)}`,
            ValueInspector.format(self.value)
        )
    end)
end

--[[
    Assert that our expectation value is equal to another value within some
    inclusive limit.
]]
function Expectation:near(otherValue, limit)
    if type(self.value) ~= "number" then
        misuse("near", `expects the value to be a number, but it is {describeKind(self.value)}.`)
    end

    if type(otherValue) ~= "number" then
        misuse("near", `expects a number to compare against, but received {describeKind(otherValue)}.`)
    end

    if limit ~= nil and type(limit) ~= "number" then
        misuse("near", `expects the limit to be a number or nil, but received {describeKind(limit)}.`)
    end

    limit = limit or 1e-7

    return self:_finish(math.abs(self.value - otherValue) <= limit, function()
        return formatMessage(
            self.successCondition,
            ("Expected value to be near %f (within %f) but got %f instead"):format(otherValue, limit, self.value),
            ("Expected value to not be near %f (within %f) but got %f instead"):format(otherValue, limit, self.value)
        )
    end)
end

--[[
    Assert that our functoid expectation value throws an error when called.
    An optional error message can be passed to assert that the error message
    contains the given value.
]]
function Expectation:throw(messageSubstring)
    if not isCallable(self.value) then
        misuse("throw", `expects the value to be a function, but it is {describeKind(self.value)}.`)
    end

    if messageSubstring ~= nil and type(messageSubstring) ~= "string" then
        misuse(
            "throw",
            `expects the message substring to be a string or nil, but received {describeKind(messageSubstring)}.`
        )
    end

    const ok, err = pcall(self.value)
    const errorText = if ok then nil else tostring(err)
    local threw = not ok

    if messageSubstring and not ok then
        threw = errorText:find(messageSubstring, 1, true) ~= nil
    end

    return self:_finish(threw, function()
        if messageSubstring then
            return formatMessage(
                self.successCondition,
                ("Expected function to throw an error containing %q, but it %s"):format(
                    messageSubstring,
                    if ok then "did not throw." else ("threw: %s"):format(errorText)
                ),
                ("Expected function to never throw an error containing %q, but it threw: %s"):format(
                    messageSubstring,
                    tostring(errorText)
                )
            )
        end

        return formatMessage(
            self.successCondition,
            "Expected function to throw an error, but it did not throw.",
            ("Expected function to succeed, but it threw an error: %s"):format(tostring(errorText))
        )
    end)
end

return Expectation
