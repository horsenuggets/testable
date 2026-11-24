--[[

MatcherTest.spec

Tests for the richer expectation matchers (deep equality, containment, length, pattern
matching, ordering, truthiness, and nil checks), the typeof-aware type matcher, matcher
misuse errors, and the "Expected" and "Received" failure messages.

--]]

const Expectation = require("../Source/Testable/Expectation")
const ExpectationContext = require("../Source/Testable/ExpectationContext")
const Testable = require("../Source/Testable")
-- The Lune type definitions don't declare the Roblox datatype constructors.
const roblox = require("@lune/roblox") :: any
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const NAN = 0 / 0
const NEW_MATCHERS = {
    "contain",
    "deepEqual",
    "falsy",
    "greaterThan",
    "greaterThanOrEqual",
    "length",
    "lessThan",
    "lessThanOrEqual",
    "match",
    "none",
    "truthy"
}

--[[
    Runs a callback that is expected to fail and returns the failure message.
]]
const function failureMessage(callback: () -> ()): string
    const ok, message = pcall(callback)

    if ok then
        error("Expected the callback to fail, but it passed.", 2)
    end

    return tostring(message)
end

return function()
    describe("expect().to.deepEqual()", function()
        it("should pass for tables with the same contents", function()
            expect({ 1, 2, 3 }).to.deepEqual({ 1, 2, 3 })
            expect({ Name = "a", Tags = { "x", "y" } }).to.deepEqual({ Name = "a", Tags = { "x", "y" } })
            expect({}).to.deepEqual({})
        end)

        it("should pass for equal primitives", function()
            expect(5).to.deepEqual(5)
            expect("a").to.deepEqual("a")
            expect(nil).to.deepEqual(nil)
        end)

        it("should treat NaN as equal to NaN", function()
            expect(NAN).to.deepEqual(NAN)
            expect({ Value = NAN }).to.deepEqual({ Value = NAN })
        end)

        it("should handle cyclic tables", function()
            const left = {}
            left.Self = left
            const right = {}
            right.Self = right

            expect(left).to.deepEqual(right)
        end)

        it("should fail for tables with different contents", function()
            expect(function()
                expect({ 1, 2, 3 }).to.deepEqual({ 1, 2, 4 })
            end).to.throw("Expected values to be deeply equal.")
            expect(function()
                expect({ A = 1 }).to.deepEqual({ A = 1, B = 2 })
            end).to.throw()
            expect(function()
                expect({}).to.deepEqual(nil)
            end).to.throw()
        end)

        it("should support negation", function()
            expect({ 1 }).never.to.deepEqual({ 2 })
            expect(function()
                expect({ 1 }).never.to.deepEqual({ 1 })
            end).to.throw("Expected: never { 1 }")
        end)
    end)

    describe("expect().to.contain()", function()
        it("should find plain substrings", function()
            expect("hello world").to.contain("world")
            expect("hello").to.contain("")
        end)

        it("should not treat the substring as a pattern", function()
            expect("a.b").to.contain(".")
            expect("abc").never.to.contain(".")
            expect("100%").to.contain("%")
            expect("a+b").to.contain("a+")
        end)

        it("should find array elements by deep equality", function()
            expect({ 1, 2, 3 }).to.contain(2)
            expect({ { Id = 1 }, { Id = 2 } }).to.contain({ Id = 2 })
            expect({ NAN }).to.contain(NAN)
        end)

        it("should fail when the item is missing", function()
            expect(function()
                expect("hello").to.contain("world")
            end).to.throw("Expected string to contain the substring.")
            expect(function()
                expect({ 1, 2, 3 }).to.contain(4)
            end).to.throw("Expected array to contain the element.")
            expect(function()
                expect({}).to.contain(nil)
            end).to.throw()
        end)

        it("should support negation", function()
            expect("hello").never.to.contain("world")
            expect({ 1, 2 }).never.to.contain(3)
            expect(function()
                expect({ 1, 2 }).never.to.contain(2)
            end).to.throw("Expected: never 2")
        end)
    end)

    describe("expect().to.have.length()", function()
        it("should check string and table lengths", function()
            expect("abc").to.have.length(3)
            expect("").to.have.length(0)
            expect({ 1, 2, 3 }).to.have.length(3)
            expect({}).to.have.length(0)
        end)

        it("should fail for the wrong length", function()
            const message = failureMessage(function()
                expect({ 1, 2 }).to.have.length(3)
            end)

            expect(message).to.contain("Expected: length 3")
            expect(message).to.contain("Received: length 2")
            expect(message).to.contain("Value: { 1, 2 }")
        end)

        it("should support negation", function()
            expect("abc").never.to.have.length(2)
            expect(function()
                expect("abc").never.to.have.length(3)
            end).to.throw("Expected: never length 3")
        end)
    end)

    describe("expect().to.match()", function()
        it("should match Luau string patterns", function()
            expect("abc123").to.match("%a+%d+")
            expect("hello").to.match("^hel")
            expect("hello").to.match("")
        end)

        it("should fail when the pattern does not match", function()
            expect(function()
                expect("hello").to.match("^%d+$")
            end).to.throw('Expected: pattern "^%d+$"')
        end)

        it("should support negation", function()
            expect("hello").never.to.match("%d")
            expect(function()
                expect("hello1").never.to.match("%d")
            end).to.throw("Expected string to match the pattern.")
        end)
    end)

    describe("ordering matchers", function()
        it("should compare numbers", function()
            expect(5).to.be.greaterThan(3)
            expect(5).to.be.greaterThanOrEqual(5)
            expect(5).to.be.greaterThanOrEqual(4)
            expect(3).to.be.lessThan(5)
            expect(5).to.be.lessThanOrEqual(5)
            expect(4).to.be.lessThanOrEqual(5)
        end)

        it("should compare strings", function()
            expect("b").to.be.greaterThan("a")
            expect("a").to.be.greaterThanOrEqual("a")
            expect("a").to.be.lessThan("b")
            expect("a").to.be.lessThanOrEqual("a")
        end)

        it("should fail at and beyond the boundary", function()
            expect(function()
                expect(5).to.be.greaterThan(5)
            end).to.throw("Expected: > 5")
            expect(function()
                expect(4).to.be.greaterThanOrEqual(5)
            end).to.throw("Expected: >= 5")
            expect(function()
                expect(5).to.be.lessThan(5)
            end).to.throw("Expected: < 5")
            expect(function()
                expect(6).to.be.lessThanOrEqual(5)
            end).to.throw("Expected: <= 5")
        end)

        it("should support negation", function()
            expect(5).never.to.be.greaterThan(5)
            expect(4).never.to.be.greaterThanOrEqual(5)
            expect(5).never.to.be.lessThan(5)
            expect(6).never.to.be.lessThanOrEqual(5)
            expect(function()
                expect(6).never.to.be.greaterThan(5)
            end).to.throw("Expected: never > 5")
        end)

        it("should agree with the operators for every pair of sample numbers", function()
            const samples = { -1, 0, 0.5, 1, math.huge }

            for _, left in samples do
                for _, right in samples do
                    const outcomes = {
                        greaterThan = left > right,
                        greaterThanOrEqual = left >= right,
                        lessThan = left < right,
                        lessThanOrEqual = left <= right
                    }

                    for name, expected in outcomes do
                        const passed = pcall(function()
                            expect(left).to.be[name](right)
                        end)
                        const negatedPassed = pcall(function()
                            expect(left).never.to.be[name](right)
                        end)

                        expect(passed).to.equal(expected)
                        expect(negatedPassed).to.equal(not expected)
                    end
                end
            end
        end)
    end)

    describe("truthiness and nil matchers", function()
        it("should agree on every kind of value", function()
            const cases = {
                { Value = nil, Truthy = false, None = true },
                { Value = false, Truthy = false, None = false },
                { Value = true, Truthy = true, None = false },
                { Value = 0, Truthy = true, None = false },
                { Value = "", Truthy = true, None = false },
                { Value = {}, Truthy = true, None = false }
            }

            for _, case in cases do
                const outcomes = {
                    falsy = not case.Truthy,
                    none = case.None,
                    truthy = case.Truthy
                }

                for name, expected in outcomes do
                    const passed = pcall(function()
                        expect(case.Value).to.be[name]()
                    end)
                    const negatedPassed = pcall(function()
                        expect(case.Value).never.to.be[name]()
                    end)

                    expect(passed).to.equal(expected)
                    expect(negatedPassed).to.equal(not expected)
                end
            end
        end)

        it("should explain failures", function()
            expect(function()
                expect(false).to.be.truthy()
            end).to.throw("Expected value to be truthy.")
            expect(function()
                expect(0).to.be.falsy()
            end).to.throw("Received: 0")
            expect(function()
                expect(false).to.be.none()
            end).to.throw("Received: false")
            expect(function()
                expect(nil).never.to.be.none()
            end).to.throw("Expected: never nil")
        end)
    end)

    describe("expect().to.be.a() with typeof names", function()
        it("should accept the typeof name of a Roblox datatype", function()
            expect(roblox.Vector3.new(1, 2, 3)).to.be.a("Vector3")
            expect(roblox.Color3.new(1, 0, 0)).to.be.a("Color3")
        end)

        it("should still accept the type name of a Roblox datatype", function()
            expect(roblox.Vector3.new(1, 2, 3)).to.be.a("userdata")
        end)

        it("should fail for the wrong datatype", function()
            const message = failureMessage(function()
                expect(roblox.Vector3.new(1, 2, 3)).to.be.a("CFrame")
            end)

            expect(message).to.contain('Expected value of type "CFrame"')
            expect(message).to.contain("of type Vector3")
        end)

        it("should support negation", function()
            expect(roblox.Vector3.new(1, 2, 3)).never.to.be.a("CFrame")
            expect(function()
                expect(roblox.Vector3.new(1, 2, 3)).never.to.be.a("Vector3")
            end).to.throw()
            expect(function()
                expect(roblox.Vector3.new(1, 2, 3)).never.to.be.a("userdata")
            end).to.throw()
        end)
    end)

    describe("matcher misuse", function()
        const function expectMisuse(matcherName: string, callback: () -> ())
            const message = failureMessage(callback)

            expect(message).to.contain(`Matcher "{matcherName}"`)
            expect(message).never.to.contain("attempt to")
        end

        it("should reject a non-string type name", function()
            expectMisuse("a", function()
                expect(5).to.be.a(5)
            end)
        end)

        it("should reject containment checks on unsupported values", function()
            expectMisuse("contain", function()
                expect(5).to.contain(5)
            end)
            expectMisuse("contain", function()
                expect("abc").to.contain(1)
            end)
            expectMisuse("contain", function()
                expect(nil).to.contain("a")
            end)
        end)

        it("should reject length checks on unsupported values", function()
            expectMisuse("length", function()
                expect(5).to.have.length(1)
            end)
            expectMisuse("length", function()
                expect("abc").to.have.length("3")
            end)
        end)

        it("should reject pattern matching on unsupported values", function()
            expectMisuse("match", function()
                expect(5).to.match("%d")
            end)
            expectMisuse("match", function()
                expect("abc").to.match(5)
            end)
            expectMisuse("match", function()
                expect("abc").to.match("[a")
            end)
        end)

        it("should reject malformed patterns even when the malformed part is never reached", function()
            const malformed = { "z[", "z%", "z(", "z)", "z%b", "z%b(", "z%f", "z%fa", "z[^", "z[%", "z[]", "(z))" }

            for _, pattern in malformed do
                expectMisuse("match", function()
                    expect("a").to.match(pattern)
                end)
                expectMisuse("match", function()
                    expect("a").never.to.match(pattern)
                end)
            end
        end)

        it("should accept well-formed patterns that use unusual syntax", function()
            expect("]").to.match("[]]")
            expect("a").to.match("[^]]")
            expect("]").to.match("[%]]")
            expect("(").to.match("[(]")
            expect("(").to.match("%(")
            expect(")").to.match("%)")
            expect("%").to.match("%%")
            expect("(x)").to.match("%b()")
            expect("THE (quick) fox").to.match("%f[%a]%a+")
            expect("ab").to.match("(a)(b)")
            expect("ab").to.match("()ab()")
            expect("aa").to.match("(a)%1")
            expect("a").never.to.match("[%a]%d")
        end)

        it("should reject ordering anything but two numbers or two strings", function()
            const names = { "greaterThan", "greaterThanOrEqual", "lessThan", "lessThanOrEqual" }
            const invalidPairs = {
                { 1, "1" },
                { "1", 1 },
                { 1, nil },
                { nil, 1 },
                { {}, {} },
                { true, false }
            }

            for _, name in names do
                for _, pair in invalidPairs do
                    expectMisuse(name, function()
                        expect(pair[1]).to.be[name](pair[2])
                    end)
                end
            end
        end)

        it("should reject near with non-numbers", function()
            expectMisuse("near", function()
                expect("1").to.be.near(1)
            end)
            expectMisuse("near", function()
                expect(1).to.be.near("1")
            end)
            expectMisuse("near", function()
                expect(1).to.be.near(1, "tight")
            end)
        end)

        it("should reject throw on a non-function", function()
            expectMisuse("throw", function()
                expect(5).to.throw()
            end)
            expectMisuse("throw", function()
                expect(nil).to.throw()
            end)
            expectMisuse("throw", function()
                expect(function() end).to.throw(5)
            end)
        end)

        it("should fail on misuse even when negated", function()
            expectMisuse("greaterThan", function()
                expect("a").never.to.be.greaterThan(1)
            end)
            expectMisuse("contain", function()
                expect(5).never.to.contain(5)
            end)
            expectMisuse("throw", function()
                expect(5).never.to.throw()
            end)
            expectMisuse("match", function()
                expect(5).never.to.match("a")
            end)
        end)
    end)

    describe("expect().to.throw() robustness", function()
        it("should accept callable tables", function()
            const callable = setmetatable({}, {
                __call = function()
                    error("from callable")
                end
            })

            expect(callable).to.throw("from callable")
        end)

        it("should accept callable tables with a protected metatable", function()
            const callable = setmetatable({}, {
                __call = function()
                    error("from protected callable")
                end,
                __metatable = "locked"
            })

            expect(callable).to.throw("from protected callable")
        end)

        it("should reject tables that are not callable", function()
            const message = failureMessage(function()
                expect(setmetatable({}, {})).to.throw()
            end)

            expect(message).to.contain('Matcher "throw"')
        end)

        it("should handle errors that are not strings", function()
            expect(function()
                error({ Code = 1 })
            end).to.throw()
            expect(function()
                error({ Code = 1 })
            end).never.to.throw("some message")
        end)
    end)

    describe("failure messages", function()
        it("should render expected and received lines for equal", function()
            const message = failureMessage(function()
                expect("a").to.equal(1)
            end)

            expect(message).to.contain("Expected: 1 (number)")
            expect(message).to.contain('Received: "a" (string)')
        end)

        it("should hint at deepEqual when equal sees matching tables", function()
            const message = failureMessage(function()
                expect({ 1 }).to.equal({ 1 })
            end)

            expect(message).to.contain('use "deepEqual"')

            const differentMessage = failureMessage(function()
                expect({ 1 }).to.equal({ 2 })
            end)

            expect(differentMessage).never.to.contain("deepEqual")
        end)

        it("should mark the expected line when negated", function()
            const message = failureMessage(function()
                expect(5).never.to.equal(5)
            end)

            expect(message).to.contain("Expected: never 5 (number)")
        end)

        it("should pretty-print tables with sorted keys", function()
            const message = failureMessage(function()
                expect({ Zebra = 1, Apple = 2 }).to.deepEqual({ Mango = 3, Banana = 4 })
            end)

            expect(message).to.contain("Expected: { Banana = 4, Mango = 3 }")
            expect(message).to.contain("Received: { Apple = 2, Zebra = 1 }")
        end)

        it("should truncate deep values in the message only", function()
            const deep = { { { { { "left" } } } } }
            const message = failureMessage(function()
                expect(deep).to.deepEqual({ { { { { "right" } } } } })
            end)

            expect(message).to.contain("Received: { { { { {...} } } } }")
            expect(message).never.to.contain("left")
            expect(deep).to.deepEqual({ { { { { "left" } } } } })
        end)

        it("should point at the test rather than the framework", function()
            const message = failureMessage(function()
                expect(1).to.be.greaterThan(2)
            end)

            expect(message).to.contain("MatcherTest.spec")

            const misuseMessage = failureMessage(function()
                expect(1).to.be.greaterThan("2")
            end)

            expect(misuseMessage).to.contain("MatcherTest.spec")
        end)
    end)

    describe("calling conventions and chaining", function()
        it("should allow every new matcher to be called with a colon", function()
            expect({ 1 }):deepEqual({ 1 })
            expect("abc"):contain("b")
            expect("abc"):length(3)
            expect("abc"):match("b")
            expect(2):greaterThan(1)
            expect(2):greaterThanOrEqual(2)
            expect(1):lessThan(2)
            expect(2):lessThanOrEqual(2)
            expect(1):truthy()
            expect(nil):falsy()
            expect(nil):none()
        end)

        it("should allow colon calls on a negated expectation", function()
            expect({ 1 }).never:deepEqual({ 2 })
            expect(function()
                expect({ 1 }).never:deepEqual({ 1 })
            end).to.throw()
        end)

        it("should reset negation after each new matcher", function()
            expect({ 1 }).never.to.deepEqual({ 2 }).to.deepEqual({ 1 })
            expect("abc").never.to.contain("z").to.contain("a")
            expect("abc").never.to.have.length(2).to.have.length(3)
            expect("abc").never.to.match("%d").to.match("%a")
            expect(2).never.to.be.greaterThan(2).to.be.greaterThan(1)
            expect(2).never.to.be.greaterThanOrEqual(3).to.be.greaterThanOrEqual(2)
            expect(2).never.to.be.lessThan(2).to.be.lessThan(3)
            expect(2).never.to.be.lessThanOrEqual(1).to.be.lessThanOrEqual(2)
            expect(1).never.to.be.falsy().to.be.truthy()
            expect(nil).never.to.be.truthy().to.be.falsy()
            expect(1).never.to.be.none().to.be.truthy()
        end)

        it("should chain new matchers with the existing ones", function()
            expect("abc").to.be.a("string").to.have.length(3).to.contain("b").to.match("^a").to.be.truthy().to.be.ok()
        end)
    end)

    describe("custom matchers", function()
        it("should reserve every built-in matcher name", function()
            for _, name in NEW_MATCHERS do
                expect(Expectation.checkMatcherNameCollisions(name)).to.equal(false)

                const context = ExpectationContext.new()

                expect(function()
                    context:extend({
                        [name] = function()
                            return { pass = true, message = "" }
                        end
                    })
                end).to.throw("Cannot overwrite matcher")
            end
        end)

        it("should keep custom matchers working alongside the new ones", function()
            const context = ExpectationContext.new()

            context:extend({
                even = function(value)
                    return { pass = value % 2 == 0, message = "Expected an even number." }
                end
            })

            context:startExpectationChain(4).to.be.even().to.be.greaterThan(3).never.to.be.lessThan(4)
            context:startExpectationChain(4).to.be.greaterThan(3).to.be.even()
            context:startExpectationChain(3).never.to.be.even().to.be.lessThan(4)

            expect(function()
                context:startExpectationChain(3).to.be.greaterThan(2).to.be.even()
            end).to.throw("Expected an even number.")
        end)
    end)
end
