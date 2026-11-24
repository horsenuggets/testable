--[[

WorkerGatesTest.spec

Verifies file-boundary gates across every four-file exclusive mask and request
permutation, including reverse completion and shared workers. Invalid tokens must not
change decisions.

--]]

const Gates = require("../Source/Testable/Workers/Gates")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it
const ORDER = { "Z", "A", "Y", "B" }
const OWNERS = { Z = 1, A = 2, Y = 1, B = 2 }

const function rejects(callback: () -> ())
    const ok, message = pcall(callback)
    expect(ok).to.equal(false)
    expect(string.find(tostring(message), "Invalid worker gates.", 1, true) ~= nil).to.equal(true)
end

const function assertGrants(actual: { Gates.Grant }, expected: { Gates.Grant })
    local count = 0
    for key in pairs(actual) do
        expect(type(key)).to.equal("number")
        count += 1
    end
    expect(count).to.equal(#expected)
    for index, grant in ipairs(expected) do
        expect(actual[index] ~= nil).to.equal(true)
        expect(actual[index].JobId).to.equal(grant.JobId)
        expect(actual[index].Name).to.equal(grant.Name)
        expect(actual[index].RequestId).to.equal(grant.RequestId)
    end
end

const function token(jobId: number, requestId: number, name: string): Gates.Grant
    return { JobId = jobId, Name = name, RequestId = requestId }
end

const function permutations(values: { string }): { { string } }
    if #values == 0 then
        return { {} }
    end
    const result = {}
    for index, value in ipairs(values) do
        const remaining = table.clone(values)
        table.remove(remaining, index)
        for _, suffix in ipairs(permutations(remaining)) do
            table.insert(suffix, 1, value)
            table.insert(result, suffix)
        end
    end
    return result
end

-- Use predecessor constraints rather than reproducing the implementation's cursor.
const function exercise(exclusive: { [string]: boolean }, arrival: { string }, eager: boolean)
    const state = Gates.new(ORDER, exclusive, OWNERS)
    const requested: { [string]: Gates.Grant } = {}
    const granted: { [string]: boolean } = {}
    const released: { [string]: boolean } = {}
    const active: { Gates.Grant } = {}
    local started = 0
    local completed = 0

    const function verify(actual: { Gates.Grant })
        const expected = {}
        for index, name in ipairs(ORDER) do
            local eligible = requested[name] ~= nil and not granted[name]
            for before = 1, index - 1 do
                const prior = ORDER[before]
                if not granted[prior] or ((exclusive[name] or exclusive[prior]) and not released[prior]) then
                    eligible = false
                end
            end
            if eligible then
                table.insert(expected, requested[name])
                granted[name] = true
            end
        end
        assertGrants(actual, expected)
        for _, grant in ipairs(actual) do
            started += 1
            expect(grant.Name).to.equal(ORDER[started])
            for _, running in ipairs(active) do
                expect(exclusive[grant.Name] or exclusive[running.Name]).to.equal(false)
            end
            table.insert(active, grant)
        end
        expect(state.ActiveCount).to.equal(#active)
        expect(Gates.finished(state)).to.equal(completed == #ORDER)
    end

    const function completeLast()
        const grant = table.remove(active)
        released[grant.Name] = true
        completed += 1
        verify(Gates.release(state, grant.JobId, grant.RequestId, grant.Name))
    end

    verify({})
    for index, name in ipairs(arrival) do
        const grant = token(OWNERS[name], index, name)
        requested[name] = grant
        verify(Gates.request(state, grant.JobId, grant.RequestId, grant.Name))
        if eager and #active > 0 then
            completeLast()
        end
    end
    while #active > 0 do
        completeLast()
    end
    expect(started).to.equal(#ORDER)
    expect(completed).to.equal(#ORDER)
    expect(Gates.finished(state)).to.equal(true)
end

return function()
    describe("global file boundaries", function()
        for mask = 0, 15 do
            const exclusive = {}
            for index, name in ipairs(ORDER) do
                exclusive[name] = bit32.band(mask, bit32.lshift(1, index - 1)) ~= 0
            end
            for index, arrival in ipairs(permutations(ORDER)) do
                it(`should preserve boundaries for exclusive mask {mask} and arrival {index}`, function()
                    exercise(exclusive, arrival, false)
                    exercise(exclusive, arrival, true)
                end)
            end
        end

        it("should overlap ordinary files even when their workers also own Serial files", function()
            const state = Gates.new(
                { "A", "B", "Serial", "C", "D" },
                { A = false, B = false, Serial = true, C = false, D = false },
                { A = 7, B = 9, Serial = 7, C = 9, D = 7 }
            )
            assertGrants(Gates.request(state, 7, 10, "A"), { token(7, 10, "A") })
            assertGrants(Gates.request(state, 7, 20, "Serial"), {})
            assertGrants(Gates.request(state, 7, 30, "D"), {})
            assertGrants(Gates.request(state, 9, 10, "B"), { token(9, 10, "B") })
            expect(state.ActiveCount).to.equal(2)
            assertGrants(Gates.request(state, 9, 20, "C"), {})
            assertGrants(Gates.release(state, 9, 10, "B"), {})
            assertGrants(Gates.release(state, 7, 10, "A"), { token(7, 20, "Serial") })
            expect(state.ActiveCount).to.equal(1)
            assertGrants(Gates.release(state, 7, 20, "Serial"), { token(9, 20, "C"), token(7, 30, "D") })
            assertGrants(Gates.release(state, 7, 30, "D"), {})
            expect(Gates.finished(state)).to.equal(false)
            assertGrants(Gates.release(state, 9, 20, "C"), {})
            expect(Gates.finished(state)).to.equal(true)
        end)

        it("should wait at an unrequested ordinary file even when later files are ready", function()
            const state = Gates.new({ "A", "B", "C" }, { A = false, B = false, C = false }, { A = 1, B = 2, C = 1 })
            assertGrants(Gates.request(state, 1, 2, "C"), {})
            assertGrants(Gates.request(state, 1, 1, "A"), { token(1, 1, "A") })
            assertGrants(Gates.release(state, 1, 1, "A"), {})
            expect(Gates.finished(state)).to.equal(false)
            assertGrants(Gates.request(state, 2, 1, "B"), { token(2, 1, "B"), token(1, 2, "C") })
            assertGrants(Gates.release(state, 1, 2, "C"), {})
            assertGrants(Gates.release(state, 2, 1, "B"), {})
            expect(Gates.finished(state)).to.equal(true)
        end)

        it("should finish empty input immediately and reject unexpected map entries", function()
            expect(Gates.finished(Gates.new({}, {}, {}))).to.equal(true)
            rejects(function()
                Gates.new({}, { Extra = false }, {})
            end)
            rejects(function()
                Gates.new({}, {}, { Extra = 1 })
            end)
        end)
    end)

    describe("ownership", function()
        it("should accept frozen inputs without mutating them", function()
            const order = table.freeze({ "A", "B" })
            const exclusive = table.freeze({ A = false, B = true })
            const owners = table.freeze({ A = 1, B = 2 })
            const state = Gates.new(order, exclusive, owners)
            assertGrants(Gates.request(state, 2, 1, "B"), {})
            assertGrants(Gates.request(state, 1, 1, "A"), { token(1, 1, "A") })
            assertGrants(Gates.release(state, 1, 1, "A"), { token(2, 1, "B") })
            assertGrants(Gates.release(state, 2, 1, "B"), {})
            expect(order[1]).to.equal("A")
            expect(exclusive.B).to.equal(true)
            expect(owners.B).to.equal(2)
        end)

        it("should own constructor inputs, returned tokens, and independent state", function()
            const order = { "A", "B", "C" }
            const exclusive = { A = false, B = true, C = false }
            const owners = { A = 1, B = 2, C = 1 }
            const state = Gates.new(order, exclusive, owners)
            const other = Gates.new(order, exclusive, owners)
            order[1] = "Changed"
            table.clear(order)
            table.clear(exclusive)
            table.clear(owners)
            assertGrants(Gates.request(state, 1, 2, "C"), {})
            assertGrants(Gates.request(state, 2, 1, "B"), {})
            const grants = Gates.request(state, 1, 1, "A")
            assertGrants(grants, { token(1, 1, "A") })
            grants[1].JobId = 99
            grants[1].Name = "Changed"
            grants[1].RequestId = 99
            table.clear(grants)
            assertGrants(Gates.release(state, 1, 1, "A"), { token(2, 1, "B") })
            assertGrants(Gates.release(state, 2, 1, "B"), { token(1, 2, "C") })
            assertGrants(Gates.release(state, 1, 2, "C"), {})
            expect(Gates.finished(state)).to.equal(true)
            expect(Gates.finished(other)).to.equal(false)
            assertGrants(Gates.request(other, 1, 1, "A"), { token(1, 1, "A") })
        end)
    end)

    describe("token validation", function()
        it(
            "should reject unknown, wrong-owner, duplicate, queued, and mismatched tokens without changing state",
            function()
                const state = Gates.new({ "A", "B", "C" }, { A = false, B = true, C = false }, { A = 1, B = 1, C = 2 })
                rejects(function()
                    Gates.request(state, 1, 1, "Unknown")
                end)
                rejects(function()
                    Gates.request(state, 2, 1, "A")
                end)
                rejects(function()
                    Gates.release(state, 1, 1, "A")
                end)
                assertGrants(Gates.request(state, 1, 2, "B"), {})
                rejects(function()
                    Gates.release(state, 1, 2, "B")
                end)
                rejects(function()
                    Gates.request(state, 1, 3, "B")
                end)
                rejects(function()
                    Gates.request(state, 1, 2, "A")
                end)
                assertGrants(Gates.request(state, 1, 3, "A"), { token(1, 3, "A") })
                rejects(function()
                    Gates.request(state, 1, 4, "A")
                end)
                rejects(function()
                    Gates.release(state, 1, 2, "A")
                end)
                rejects(function()
                    Gates.release(state, 2, 3, "A")
                end)
                rejects(function()
                    Gates.release(state, 1, 3, "Unknown")
                end)
                assertGrants(Gates.release(state, 1, 3, "A"), { token(1, 2, "B") })
                rejects(function()
                    Gates.release(state, 1, 3, "A")
                end)
                rejects(function()
                    Gates.request(state, 1, 5, "A")
                end)
                assertGrants(Gates.release(state, 1, 2, "B"), {})
                assertGrants(Gates.request(state, 2, 3, "C"), { token(2, 3, "C") })
                assertGrants(Gates.release(state, 2, 3, "C"), {})
                expect(Gates.finished(state)).to.equal(true)
            end
        )

        it("should retain used request IDs after release but allow the same ID for another owner", function()
            const state = Gates.new({ "A", "B", "C" }, { A = false, B = false, C = false }, { A = 1, B = 1, C = 2 })
            assertGrants(Gates.request(state, 1, 7, "A"), { token(1, 7, "A") })
            assertGrants(Gates.release(state, 1, 7, "A"), {})
            rejects(function()
                Gates.request(state, 1, 7, "B")
            end)
            assertGrants(Gates.request(state, 2, 7, "C"), {})
            assertGrants(Gates.request(state, 1, 1, "B"), { token(1, 1, "B"), token(2, 7, "C") })
            assertGrants(Gates.release(state, 2, 7, "C"), {})
            assertGrants(Gates.release(state, 1, 1, "B"), {})
            expect(Gates.finished(state)).to.equal(true)
        end)

        const invalidIds: { any } = { 0, -1, 1.5, math.huge, -math.huge, 0 / 0, "1", false, {} }
        for index, value in ipairs(invalidIds) do
            it(`should reject malformed IDs {index} in constructors, requests, and releases`, function()
                rejects(function()
                    Gates.new({ "A" }, { A = false }, { A = value })
                end)
                const state = Gates.new({ "A" }, { A = false }, { A = 1 })
                rejects(function()
                    Gates.request(state, value, 1, "A")
                end)
                rejects(function()
                    Gates.request(state, 1, value, "A")
                end)
                assertGrants(Gates.request(state, 1, 1, "A"), { token(1, 1, "A") })
                rejects(function()
                    Gates.release(state, value, 1, "A")
                end)
                rejects(function()
                    Gates.release(state, 1, value, "A")
                end)
                assertGrants(Gates.release(state, 1, 1, "A"), {})
                expect(Gates.finished(state)).to.equal(true)
            end)
        end

        const invalidNames: { any } = { "", false, 1, {}, 0 / 0 }
        for index, value in ipairs(invalidNames) do
            it(`should reject malformed token names {index}`, function()
                const state = Gates.new({ "A" }, { A = false }, { A = 1 })
                rejects(function()
                    Gates.request(state, 1, 1, value :: any)
                end)
                assertGrants(Gates.request(state, 1, 1, "A"), { token(1, 1, "A") })
                rejects(function()
                    Gates.release(state, 1, 1, value :: any)
                end)
                assertGrants(Gates.release(state, 1, 1, "A"), {})
            end)
        end

        it("should reject nil IDs and names without consuming a request", function()
            const state = Gates.new({ "A" }, { A = false }, { A = 1 })
            rejects(function()
                Gates.request(state, nil :: any, 1, "A")
            end)
            rejects(function()
                Gates.request(state, 1, nil :: any, "A")
            end)
            rejects(function()
                Gates.request(state, 1, 1, nil :: any)
            end)
            assertGrants(Gates.request(state, 1, 1, "A"), { token(1, 1, "A") })
            rejects(function()
                Gates.release(state, nil :: any, 1, "A")
            end)
            rejects(function()
                Gates.release(state, 1, nil :: any, "A")
            end)
            rejects(function()
                Gates.release(state, 1, 1, nil :: any)
            end)
            assertGrants(Gates.release(state, 1, 1, "A"), {})
        end)
    end)

    describe("constructor validation", function()
        const invalidOrders: { any } = {
            false,
            "array",
            { [2] = "A" },
            { [1] = "A", [3] = "B" },
            { [2] = "A", [3] = "B", [4] = "C", [6] = "D" },
            { [0] = "A" },
            { [-1] = "A" },
            { [1.5] = "A" },
            { [math.huge] = "A" },
            { [-math.huge] = "A" },
            { Key = "A" },
            { "A", Key = "B" },
            { "" },
            { false },
            { 1 },
            { "A", "A" },
            setmetatable({}, { __index = { "A" } })
        }
        for index, value in ipairs(invalidOrders) do
            it(`should reject malformed order {index}`, function()
                const exclusive = {}
                const owners = {}
                if type(value) == "table" then
                    for _, name in pairs(value) do
                        if type(name) == "string" and name ~= "" then
                            exclusive[name] = false
                            owners[name] = 1
                        end
                    end
                end
                rejects(function()
                    Gates.new(value, exclusive, owners)
                end)
            end)
        end

        const invalidMaps: { any } = {
            false,
            "map",
            {},
            { Extra = true },
            { A = true, Extra = true },
            { ["A"] = true, [""] = true },
            { ["A"] = true, [1] = true },
            { ["A"] = true, [math.huge] = true },
            setmetatable({ A = true }, {}),
            setmetatable({}, { __index = { A = true } })
        }
        for index, value in ipairs(invalidMaps) do
            it(`should reject missing, extra, or malformed flags {index}`, function()
                rejects(function()
                    Gates.new({ "A" }, value, { A = 1 })
                end)
            end)
            it(`should reject missing, extra, or malformed owners {index}`, function()
                rejects(function()
                    Gates.new({ "A" }, { A = false }, value)
                end)
            end)
        end

        it("should require exact name sets even when every extra value has the correct type", function()
            rejects(function()
                Gates.new({ "A" }, { A = false, Extra = true }, { A = 1 })
            end)
            rejects(function()
                Gates.new({ "A" }, { A = false }, { A = 1, Extra = 2 })
            end)
            rejects(function()
                Gates.new({ "A", "B" }, { A = false }, { A = 1, B = 2 })
            end)
            rejects(function()
                Gates.new({ "A", "B" }, { A = false, B = true }, { A = 1 })
            end)
            rejects(function()
                Gates.new({ "A" }, { A = false }, { ["A"] = 1, [1] = 2 } :: any)
            end)
        end)

        const invalidFlags: { any } = { 0, 1, "true", {}, 0 / 0 }
        for index, value in ipairs(invalidFlags) do
            it(`should reject nonboolean flags {index}`, function()
                rejects(function()
                    Gates.new({ "A" }, { A = value } :: any, { A = 1 })
                end)
            end)
        end

        it("should reject nil constructor arguments", function()
            rejects(function()
                Gates.new(nil :: any, {}, {})
            end)
            rejects(function()
                Gates.new({}, nil :: any, {})
            end)
            rejects(function()
                Gates.new({}, {}, nil :: any)
            end)
        end)
    end)
end
