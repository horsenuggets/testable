--[[

ValueInspectorTest.spec

Tests for the ValueInspector module, covering deep structural equality (nested tables,
NaN, cycles) and deterministic value formatting (sorted keys, escaping, truncation).

--]]

const Testable = require("../Source/Testable")
const ValueInspector = require("../Source/Testable/ValueInspector")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const NAN = 0 / 0

return function()
    describe("deepEqual", function()
        it("should treat identical primitives as equal", function()
            expect(ValueInspector.deepEqual(1, 1)).to.equal(true)
            expect(ValueInspector.deepEqual("a", "a")).to.equal(true)
            expect(ValueInspector.deepEqual(true, true)).to.equal(true)
            expect(ValueInspector.deepEqual(nil, nil)).to.equal(true)
        end)

        it("should treat different primitives as unequal", function()
            expect(ValueInspector.deepEqual(1, 2)).to.equal(false)
            expect(ValueInspector.deepEqual(1, "1")).to.equal(false)
            expect(ValueInspector.deepEqual(false, nil)).to.equal(false)
            expect(ValueInspector.deepEqual({}, nil)).to.equal(false)
            expect(ValueInspector.deepEqual(nil, {})).to.equal(false)
        end)

        it("should compare tables by contents", function()
            expect(ValueInspector.deepEqual({}, {})).to.equal(true)
            expect(ValueInspector.deepEqual({ 1, 2, 3 }, { 1, 2, 3 })).to.equal(true)
            expect(ValueInspector.deepEqual({ A = { B = { C = 1 } } }, { A = { B = { C = 1 } } })).to.equal(true)
        end)

        it("should detect differing, missing, and extra keys", function()
            expect(ValueInspector.deepEqual({ 1, 2, 3 }, { 1, 2, 4 })).to.equal(false)
            expect(ValueInspector.deepEqual({ A = 1 }, { A = 1, B = 2 })).to.equal(false)
            expect(ValueInspector.deepEqual({ A = 1, B = 2 }, { A = 1 })).to.equal(false)
            expect(ValueInspector.deepEqual({ A = { B = 1 } }, { A = { B = 2 } })).to.equal(false)
        end)

        it("should tell a false value apart from a missing key", function()
            expect(ValueInspector.deepEqual({ A = false }, {})).to.equal(false)
            expect(ValueInspector.deepEqual({}, { A = false })).to.equal(false)
        end)

        it("should treat NaN as equal to NaN at any depth", function()
            expect(ValueInspector.deepEqual(NAN, NAN)).to.equal(true)
            expect(ValueInspector.deepEqual({ Value = NAN }, { Value = NAN })).to.equal(true)
            expect(ValueInspector.deepEqual(NAN, 1)).to.equal(false)
            expect(ValueInspector.deepEqual({ NAN }, { 1 })).to.equal(false)
        end)

        it("should handle cyclic tables", function()
            const left = { Name = "node" }
            left.Self = left
            const right = { Name = "node" }
            right.Self = right

            expect(ValueInspector.deepEqual(left, right)).to.equal(true)

            const different = { Name = "other" }
            different.Self = different

            expect(ValueInspector.deepEqual(left, different)).to.equal(false)
        end)

        it("should handle mutually cyclic tables", function()
            const leftA, leftB = {}, {}
            leftA.Other = leftB
            leftB.Other = leftA
            const rightA, rightB = {}, {}
            rightA.Other = rightB
            rightB.Other = rightA

            expect(ValueInspector.deepEqual(leftA, rightA)).to.equal(true)

            rightB.Extra = 1

            expect(ValueInspector.deepEqual(leftA, rightA)).to.equal(false)
        end)

        it("should compare functions by reference", function()
            const callback = function() end

            expect(ValueInspector.deepEqual({ callback }, { callback })).to.equal(true)
            expect(ValueInspector.deepEqual({ callback }, { function() end })).to.equal(false)
        end)

        it("should not invoke __index metamethods", function()
            const withDefault = setmetatable({}, {
                __index = function()
                    return 1
                end,
            })

            expect(ValueInspector.deepEqual(withDefault, { A = 1 })).to.equal(false)
            expect(ValueInspector.deepEqual({ A = 1 }, withDefault)).to.equal(false)
        end)

        it("should be symmetric", function()
            const samples = { 1, "1", NAN, {}, { 1 }, { A = 1 }, { A = { 1 } }, false }

            for _, left in samples do
                for _, right in samples do
                    expect(ValueInspector.deepEqual(left, right)).to.equal(ValueInspector.deepEqual(right, left))
                end
            end
        end)
    end)

    describe("format", function()
        it("should render primitives", function()
            expect(ValueInspector.format(nil)).to.equal("nil")
            expect(ValueInspector.format(true)).to.equal("true")
            expect(ValueInspector.format(5)).to.equal("5")
            expect(ValueInspector.format(1.5)).to.equal("1.5")
            expect(ValueInspector.format("hi")).to.equal('"hi"')
        end)

        it("should render special numbers consistently", function()
            expect(ValueInspector.format(NAN)).to.equal("nan")
            expect(ValueInspector.format(-NAN)).to.equal("nan")
            expect(ValueInspector.format(math.huge)).to.equal("inf")
            expect(ValueInspector.format(-math.huge)).to.equal("-inf")
        end)

        it("should escape quotes, backslashes, and control characters in strings", function()
            expect(ValueInspector.format('a"b')).to.equal('"a\\"b"')
            expect(ValueInspector.format("a\\b")).to.equal('"a\\\\b"')
            expect(ValueInspector.format("a\nb\tc")).to.equal('"a\\nb\\tc"')
            expect(ValueInspector.format("a\0b")).to.equal('"a\\000b"')
        end)

        it("should render functions and threads without addresses", function()
            expect(ValueInspector.format(function() end)).to.equal("<function>")
            expect(ValueInspector.format(coroutine.create(function() end))).to.equal("<thread>")
        end)

        it("should render empty tables and arrays inline", function()
            expect(ValueInspector.format({})).to.equal("{}")
            expect(ValueInspector.format({ 1, "two", true })).to.equal('{ 1, "two", true }')
        end)

        it("should sort dictionary keys", function()
            expect(ValueInspector.format({ Zebra = 1, Apple = 2, Mango = 3 })).to.equal(
                "{ Apple = 2, Mango = 3, Zebra = 1 }"
            )
        end)

        it("should put array items first, then numbers, strings, and booleans", function()
            const value: { [any]: any } = { "a", "b", Name = "x", [10] = "ten", [true] = "yes", [-1] = "neg" }

            expect(ValueInspector.format(value)).to.equal(
                '{ "a", "b", [-1] = "neg", [10] = "ten", Name = "x", [true] = "yes" }'
            )
        end)

        it("should bracket keys that are not identifiers", function()
            expect(ValueInspector.format({ ["two words"] = 1, ["1st"] = 2 })).to.equal(
                '{ ["1st"] = 2, ["two words"] = 1 }'
            )
            expect(ValueInspector.format({ [{}] = 1 })).to.equal("{ [<table>] = 1 }")
        end)

        it("should produce the same output regardless of insertion order", function()
            const forward = {}
            const backward = {}
            const names = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }

            for index = 1, #names do
                forward[names[index]] = index
            end

            for index = #names, 1, -1 do
                backward[names[index]] = index
            end

            expect(ValueInspector.format(forward)).to.equal(ValueInspector.format(backward))
            expect(ValueInspector.format(forward)).to.equal(ValueInspector.format(forward))
        end)

        it("should order reference keys that render identically by their values", function()
            for _ = 1, 20 do
                const value = {}

                for _, item in { "delta", "alpha", "charlie", "bravo" } do
                    value[{}] = item
                end

                expect(ValueInspector.format(value)).to.equal(table.concat({
                    "{",
                    '    [<table>] = "alpha",',
                    '    [<table>] = "bravo",',
                    '    [<table>] = "charlie",',
                    '    [<table>] = "delta",',
                    "}",
                }, "\n"))
            end
        end)

        it("should break long tables across indented lines", function()
            const value = {
                Description = "a fairly long string that pushes the table past the inline width",
                Nested = { Count = 1 },
            }

            expect(ValueInspector.format(value)).to.equal(table.concat({
                "{",
                '    Description = "a fairly long string that pushes the table past the inline width",',
                "    Nested = { Count = 1 },",
                "}",
            }, "\n"))
        end)

        it("should indent nested multi-line tables", function()
            const long = "a fairly long string that pushes the table past the inline width, twice over"
            const value = { Outer = { Inner = long, Other = long } }

            expect(ValueInspector.format(value)).to.equal(table.concat({
                "{",
                "    Outer = {",
                `        Inner = "{long}",`,
                `        Other = "{long}",`,
                "    },",
                "}",
            }, "\n"))
        end)

        it("should truncate tables nested deeper than the maximum depth", function()
            const value = { A = { B = { C = { D = 1 } } } }

            expect(ValueInspector.format(value, { MaxDepth = 2 })).to.equal("{ A = { B = {...} } }")
            expect(ValueInspector.format(value, { MaxDepth = 10 })).to.equal("{ A = { B = { C = { D = 1 } } } }")
        end)

        it("should truncate at the default depth without changing the value", function()
            const value = { { { { { "deep" } } } } }

            expect(ValueInspector.format(value)).to.equal("{ { { { {...} } } } }")
            expect(value[1][1][1][1][1]).to.equal("deep")
        end)

        it("should never truncate empty tables", function()
            expect(ValueInspector.format({ A = {} }, { MaxDepth = 1 })).to.equal("{ A = {} }")
        end)

        it("should summarize items past the maximum count", function()
            expect(ValueInspector.format({ 1, 2, 3, 4, 5 }, { MaxItems = 3 })).to.equal("{ 1, 2, 3, ... 2 more items }")
            expect(ValueInspector.format({ 1, 2, 3, 4 }, { MaxItems = 3 })).to.equal("{ 1, 2, 3, ... 1 more item }")
            expect(ValueInspector.format({ 1, 2, 3 }, { MaxItems = 3 })).to.equal("{ 1, 2, 3 }")
            expect(ValueInspector.format({ 1, A = 1, B = 2 }, { MaxItems = 2 })).to.equal(
                "{ 1, A = 1, ... 1 more item }"
            )
        end)

        it("should mark cycles instead of recursing forever", function()
            const value = { Name = "node" }
            value.Self = value

            expect(ValueInspector.format(value)).to.equal('{ Name = "node", Self = <cycle> }')
        end)

        it("should render a table that appears twice without a cycle", function()
            const shared = { 1 }

            expect(ValueInspector.format({ shared, shared })).to.equal("{ { 1 }, { 1 } }")
        end)

        it("should reject invalid options", function()
            expect(function()
                ValueInspector.format({}, { MaxDepth = "deep" })
            end).to.throw("MaxDepth must be a number")
            expect(function()
                ValueInspector.format({}, { MaxItems = "many" })
            end).to.throw("MaxItems must be a number")
        end)
    end)
end
