--[[

SpecApiTest.spec

Tests for the spec API that specs require from Testable instead of receiving as injected
globals. The in-process tests cover what the API exports and how it behaves outside of a
test. The subprocess tests run a real plan in every combination of spec style (required
functions with injection turned off, and injected globals) and execution mode, so both
styles are held to the same behavior.

--]]

const Expectation = require("../Source/Testable/Expectation")
const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const SPEC_API_PATH = "Source/Testable/SpecApi.luau"
const COLLECTION_HINT = "must be registered while the spec is being collected"
const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
-- Members of the Expectation table that are not matchers a spec can chain.
const EXPECTATION_INTERNALS = {
    __index = true,
    checkMatcherNameCollisions = true,
    extend = true,
    new = true,
}
-- Exports that exist only on the requirable API, not in the spec environment.
const RUN_TIME_EXPORTS = { "bindTest", "expect", "fail" }
const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")
    %s

    Testable.configure({ InjectGlobals = %s, Parallel = %s })

    const results, passed = Testable.run({
        Module = function()
            %s
        end,
    })

    results:visitAllNodes(function(node)
        if node.planNode.type == "It" and node.status == "Failure" then
            print("FAILED:" .. node.planNode.phrase)
        end
    end)
    print("PASS_COUNT:" .. results.successCount)
    print("FAIL_COUNT:" .. results.failureCount)
    print("SKIP_COUNT:" .. results.skippedCount)
    process.exit(if passed then 0 else 1)
]]
const SPEC_STYLES = {
    {
        InjectGlobals = false,
        Name = "required functions",
        Preamble = [[
            const afterEach, beforeAll, beforeEach = Testable.afterEach, Testable.beforeAll, Testable.beforeEach
            const describe, expect, fail, it = Testable.describe, Testable.expect, Testable.fail, Testable.it
            const fdescribe, fit, xdescribe, xit = Testable.fdescribe, Testable.fit, Testable.xdescribe, Testable.xit
        ]],
    },
    {
        InjectGlobals = true,
        Name = "injected globals",
        Preamble = "",
    },
}

type SpecStyle = typeof(SPEC_STYLES[1])

--[[
    Builds a script that runs one spec with the given body and prints its results in a
    parseable form, including the name of every failed test.

    @param style - Whether the spec requires its functions or uses injected globals
    @param parallel - Whether to run the spec with parallel execution enabled
    @param specBody - The Luau source of the spec function's body
    @return The full script source
]]
const function buildScript(style: SpecStyle, parallel: boolean, specBody: string): string
    return string.format(SCRIPT_TEMPLATE, style.Preamble, tostring(style.InjectGlobals), tostring(parallel), specBody)
end

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

--[[
    Runs the callback on a fresh coroutine, which Testable knows nothing about, and
    returns what the callback returned.
]]
const function onFreshCoroutine<Returns...>(callback: () -> Returns...): Returns...
    return coroutine.wrap(callback)()
end

--[[
    Plans a single spec function in this process, without running it.
]]
const function plan(spec: () -> ()): any
    return Testable.TestPlanner.createPlan({
        { method = spec, path = { "Planned" }, pathStringForSorting = "planned" },
    })
end

return function()
    describe("exports", function()
        it("should export every function of the spec environment", function()
            local count = 0

            for key, value in Testable.TestPlan.newEnvironment({}) do
                if type(value) == "function" then
                    count += 1
                    expect((Testable :: any)[key]).to.be.a("function")
                end
            end

            -- Guards against the loop passing because the environment came back empty.
            expect(count >= 10).to.equal(true)
        end)

        it("should export the run-time functions", function()
            expect(Testable.bindTest).to.be.a("function")
            expect(Testable.fail).to.be.a("function")
            expect(Testable.expect).to.be.a("table")
            expect(Testable.expect.extend).to.be.a("function")
        end)

        it("should keep the hand-written Api type in step with the exports", function()
            const source = fs.readFile(SPEC_API_PATH)
            const keys = table.clone(RUN_TIME_EXPORTS)

            for key in Testable.TestPlan.newEnvironment({}) do
                if not table.find(keys, key) then
                    table.insert(keys, key)
                end
            end

            for _, key in keys do
                if string.find(source, `\n    {key}: `, 1, true) == nil then
                    error(`"{key}" is exported to specs but missing from the Api type in "{SPEC_API_PATH}".`)
                end
            end
        end)

        it("should keep the hand-written Expectation type in step with the matchers", function()
            const source = fs.readFile(SPEC_API_PATH)

            for name, value in Expectation :: { [string]: any } do
                const isMatcher = type(value) == "function"
                    and not EXPECTATION_INTERNALS[name]
                    and string.sub(name, 1, 1) ~= "_"

                if isMatcher and string.find(source, `\n    {name}: MatcherMethod<`, 1, true) == nil then
                    error(
                        `The matcher "{name}" is missing from the Expectation type in "{SPEC_API_PATH}". `
                            .. "Add it there, or to EXPECTATION_INTERNALS in this spec if it is not a matcher."
                    )
                end
            end
        end)
    end)

    describe("collection", function()
        it("should register under the describe block being collected", function()
            const collected = plan(function()
                Testable.describe("outer", function()
                    Testable.beforeEach(function() end)
                    Testable.it("first", function() end)

                    Testable.describe("inner", function()
                        Testable.it("second", function() end)
                    end)

                    Testable.it("third", function() end)
                end)
            end)

            const names = {}
            collected:visitAllNodes(function(node)
                if node.type == "It" then
                    table.insert(names, node:getFullName())
                end
            end)

            expect(table.concat(names, ", ")).to.equal(
                "Planned outer first, Planned outer inner second, Planned outer third"
            )
            expect(collected.children[1].loadError).to.equal(nil)
        end)

        it("should apply the focus and skip variants", function()
            const collected = plan(function()
                Testable.fit("focused", function() end)
                Testable.xit("skipped", function() end)
                Testable.describeSKIP("skipped block", function() end)
                Testable.it("plain", function() end)
            end)

            const modifiers = {}
            collected:visitAllNodes(function(node)
                modifiers[node.phrase] = node.modifier
            end)

            expect(modifiers.focused).to.equal("Focus")
            expect(modifiers.skipped).to.equal("Skip")
            expect(modifiers["skipped block"]).to.equal("Skip")
            expect(modifiers.plain).to.equal("None")
        end)

        it("should let SKIP mark the block that calls it", function()
            const collected = plan(function()
                Testable.describe("marked", function()
                    Testable.SKIP()
                end)
                Testable.describe("unmarked", function() end)
            end)

            const modifiers = {}
            collected:visitAllNodes(function(node)
                modifiers[node.phrase] = node.modifier
            end)

            expect(modifiers.marked).to.equal("Skip")
            expect(modifiers.unmarked).to.equal("None")
        end)

        it("should allow the built-in matchers in a describe body but not expect.extend", function()
            const collected = plan(function()
                Testable.expect(1).to.equal(1)
                Testable.expect.extend({})
            end)

            const loadError = collected.children[1].loadError
            expect(loadError).to.be.a("string")
            expect(contains(loadError, 'Cannot call "expect.extend" from within a "describe" node.')).to.equal(true)
        end)

        it("should report a planning error for fail in a describe body", function()
            const collected = plan(function()
                Testable.fail("too early")
            end)

            expect(contains(collected.children[1].loadError, 'Cannot call "fail" outside of a running test')).to.equal(
                true
            )
        end)
    end)

    describe("outside of a spec", function()
        it("should reject registering", function()
            for _, key in { "afterAll", "beforeEach", "describe", "it", "itSKIP", "SKIP" } do
                const ok, message = onFreshCoroutine(function()
                    return pcall((Testable :: any)[key], "phrase", function() end)
                end)

                expect(ok).to.equal(false)
                expect(contains(tostring(message), `Cannot call "{key}" outside of a spec.`)).to.equal(true)
                expect(contains(tostring(message), COLLECTION_HINT)).to.equal(true)
            end
        end)

        it("should reject fail, expect.extend, and bindTest", function()
            const failOk, failMessage = onFreshCoroutine(function()
                return pcall(Testable.fail, "nobody to fail")
            end)
            const extendOk, extendMessage = onFreshCoroutine(function()
                return pcall(Testable.expect.extend, {})
            end)
            const bindOk, bindMessage = onFreshCoroutine(function()
                return pcall(Testable.bindTest, function() end)
            end)

            expect(failOk).to.equal(false)
            expect(contains(tostring(failMessage), 'Cannot call "fail" outside of a running test or hook.')).to.equal(
                true
            )
            expect(contains(tostring(failMessage), "Testable.bindTest")).to.equal(true)
            expect(extendOk).to.equal(false)
            expect(contains(tostring(extendMessage), 'Cannot call "expect.extend" outside of a running test')).to.equal(
                true
            )
            expect(bindOk).to.equal(false)
            expect(contains(tostring(bindMessage), 'Cannot call "bindTest" outside of a running test')).to.equal(true)
        end)

        it("should still offer the built-in matchers", function()
            const passOk = onFreshCoroutine(function()
                return pcall(function()
                    Testable.expect(1).to.equal(1)
                end)
            end)
            const failOk = onFreshCoroutine(function()
                return pcall(function()
                    Testable.expect(1).to.equal(2)
                end)
            end)

            expect(passOk).to.equal(true)
            expect(failOk).to.equal(false)
        end)
    end)

    describe("bindTest", function()
        it("should pass arguments and results through, including nils", function()
            const bound = Testable.bindTest(function(first: number, second: number)
                return first + second, nil, "last"
            end)

            const results = onFreshCoroutine(function()
                return table.pack(bound(1, 2))
            end)

            expect(results.n).to.equal(3)
            expect(results[1]).to.equal(3)
            expect(results[2]).to.equal(nil)
            expect(results[3]).to.equal("last")
        end)

        it("should make custom matchers of the test visible on other coroutines", function()
            const typedExpect: Testable.Expect<{ beBound: () -> any }> = expect :: any

            typedExpect.extend({
                beBound = function(value)
                    return { message = "not bound", pass = value == "bound" }
                end,
            })

            const unboundMatcher = onFreshCoroutine(function()
                return (expect("bound") :: any).beBound
            end)
            const boundOk = onFreshCoroutine(Testable.bindTest(function()
                return pcall(function()
                    typedExpect("bound").to.beBound()
                end)
            end))

            expect(unboundMatcher).to.equal(nil)
            expect(boundOk).to.equal(true)
        end)

        it("should rethrow errors and leave the coroutine unbound afterward", function()
            const bound = Testable.bindTest(function()
                error("bound failure")
            end)

            const ok, message, scopedAfterward = onFreshCoroutine(function()
                const callOk, callMessage = pcall(bound)
                return callOk, callMessage, (pcall(Testable.expect.extend, {}))
            end)

            expect(ok).to.equal(false)
            expect(contains(tostring(message), "bound failure")).to.equal(true)
            expect(scopedAfterward).to.equal(false)
        end)
    end)

    for _, style in SPEC_STYLES do
        for _, mode in EXECUTION_MODES do
            describe(`{style.Name} with {mode.Name} execution`, function()
                it("should run tests, hooks, and the focus and skip variants", function()
                    const ok, output = Subprocess.runScript(buildScript(
                        style,
                        mode.Parallel,
                        [[
                            print("GLOBAL_DESCRIBE:" .. tostring(getfenv(1).describe ~= nil))

                            local setup = 0

                            describe("block", function()
                                beforeAll(function()
                                    setup += 10
                                end)

                                beforeEach(function()
                                    setup += 1
                                end)

                                afterEach(function(context)
                                    expect(context.Seen).to.equal(true)
                                end)

                                it("sees its hooks", function(context)
                                    context.Seen = true
                                    expect(setup >= 11).to.equal(true)
                                end)

                                it("passes after yielding", function(context)
                                    context.Seen = true
                                    task.wait(0.01)
                                    expect("value").to.be.a("string")
                                end)

                                xit("is skipped", function()
                                    error("a skipped test ran")
                                end)

                                xdescribe("skipped block", function()
                                    it("is skipped too", function()
                                        error("a skipped test ran")
                                    end)
                                end)
                            end)
                        ]]
                    ))

                    expect(contains(output, "PASS_COUNT:2")).to.equal(true)
                    expect(contains(output, "FAIL_COUNT:0")).to.equal(true)
                    expect(contains(output, "SKIP_COUNT:2")).to.equal(true)
                    expect(contains(output, `GLOBAL_DESCRIBE:{style.InjectGlobals}`)).to.equal(true)
                    expect(ok).to.equal(true)
                end)

                it("should run only focused tests", function()
                    const ok, output = Subprocess.runScript(buildScript(
                        style,
                        mode.Parallel,
                        [[
                            fdescribe("focused block", function()
                                it("runs", function() end)
                            end)

                            describe("other block", function()
                                fit("runs too", function() end)
                                it("is left out", function()
                                    error("an unfocused test ran")
                                end)
                            end)
                        ]]
                    ))

                    expect(contains(output, "PASS_COUNT:2")).to.equal(true)
                    expect(contains(output, "SKIP_COUNT:1")).to.equal(true)
                    expect(ok).to.equal(true)
                end)

                it("should fail the test that called fail, even while others are running", function()
                    const ok, output = Subprocess.runScript(buildScript(
                        style,
                        mode.Parallel,
                        [[
                            describe("block", function()
                                it("fails late", function()
                                    task.wait(0.05)
                                    fail("late failure")
                                end)

                                it("passes meanwhile", function()
                                    task.wait(0.01)
                                    expect(1).to.equal(1)
                                    task.wait(0.08)
                                end)

                                it("fails in a hook-free sibling", function()
                                    task.wait(0.03)
                                    fail()
                                end)
                            end)
                        ]]
                    ))

                    expect(ok).to.equal(false)
                    expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                    expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
                    expect(contains(output, "FAILED:fails late")).to.equal(true)
                    expect(contains(output, "FAILED:fails in a hook-free sibling")).to.equal(true)
                    expect(contains(output, "FAILED:passes meanwhile")).to.equal(false)
                    expect(contains(output, "late failure")).to.equal(true)
                    expect(contains(output, "fail() was called.")).to.equal(true)
                end)

                it("should scope expect.extend to the test or block that called it", function()
                    const ok, output = Subprocess.runScript(buildScript(
                        style,
                        mode.Parallel,
                        [[
                            const function matcher(expected)
                                return function(value)
                                    return { pass = value == expected, message = "Expected " .. expected }
                                end
                            end

                            describe("block", function()
                                beforeAll(function()
                                    expect.extend({ beShared = matcher("shared") })
                                end)

                                -- Runs once per test, so it would collide if tests shared matchers.
                                beforeEach(function()
                                    expect.extend({ bePerTest = matcher("per test") })
                                end)

                                it("extends its own matcher", function()
                                    expect.extend({ beMine = matcher("mine") })
                                    task.wait(0.05)
                                    expect("mine").to.beMine()
                                    expect("shared").to.beShared()
                                    expect("per test").to.bePerTest()
                                end)

                                it("does not see the matcher of a sibling", function()
                                    task.wait(0.02)
                                    expect(expect("mine").beMine).to.equal(nil)
                                    expect("shared").to.beShared()
                                    expect("per test").to.bePerTest()
                                end)

                                it("fails through a custom matcher", function()
                                    expect("other").to.beShared()
                                end)
                            end)

                            describe("other block", function()
                                it("does not see the matchers of the first block", function()
                                    task.wait(0.02)
                                    expect(expect("shared").beShared).to.equal(nil)
                                end)
                            end)
                        ]]
                    ))

                    expect(ok).to.equal(false)
                    expect(contains(output, "PASS_COUNT:3")).to.equal(true)
                    expect(contains(output, "FAIL_COUNT:1")).to.equal(true)
                    expect(contains(output, "FAILED:fails through a custom matcher")).to.equal(true)
                    expect(contains(output, "Expected shared")).to.equal(true)
                    expect(contains(output, "Cannot reassign")).to.equal(false)
                end)

                it("should reject registering once the run has started", function()
                    const ok, output = Subprocess.runScript(buildScript(
                        style,
                        mode.Parallel,
                        [[
                            describe("block", function()
                                beforeEach(function() end)

                                it("registers a test too late", function()
                                    it("never runs", function() end)
                                end)

                                it("registers a block too late", function()
                                    describe("never collected", function() end)
                                end)

                                it("registers a hook too late", function()
                                    beforeEach(function() end)
                                end)

                                it("is unaffected", function() end)
                            end)
                        ]]
                    ))

                    expect(ok).to.equal(false)
                    expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                    expect(contains(output, "FAIL_COUNT:3")).to.equal(true)
                    expect(contains(output, "FAILED:registers a test too late")).to.equal(true)
                    expect(contains(output, "FAILED:registers a block too late")).to.equal(true)
                    expect(contains(output, "FAILED:registers a hook too late")).to.equal(true)
                    expect(contains(output, COLLECTION_HINT)).to.equal(true)
                end)

                it("should fail the right test from another thread through bindTest", function()
                    const ok, output = Subprocess.runScript(buildScript(
                        style,
                        mode.Parallel,
                        [[
                            describe("block", function()
                                it("fails from a bound thread", function()
                                    task.spawn(Testable.bindTest(function()
                                        task.wait(0.02)
                                        fail("bound thread failure")
                                    end))
                                    task.wait(0.06)
                                end)

                                it("passes meanwhile", function()
                                    task.wait(0.04)
                                end)

                                it("is told when a bound thread outlives it", function()
                                    local lateOk, lateMessage = nil, nil

                                    task.spawn(Testable.bindTest(function()
                                        task.wait(0.02)
                                        lateOk, lateMessage = pcall(fail, "too late")
                                        print("LATE_OK:" .. tostring(lateOk))
                                        print("LATE_MESSAGE:" .. tostring(lateMessage))
                                    end))
                                end)
                            end)

                            describe("slow block", function()
                                it("keeps the run alive", function()
                                    task.wait(0.1)
                                end)
                            end)
                        ]]
                    ))

                    expect(ok).to.equal(false)
                    expect(contains(output, "PASS_COUNT:3")).to.equal(true)
                    expect(contains(output, "FAIL_COUNT:1")).to.equal(true)
                    expect(contains(output, "FAILED:fails from a bound thread")).to.equal(true)
                    expect(contains(output, "bound thread failure")).to.equal(true)
                    expect(contains(output, "LATE_OK:false")).to.equal(true)
                    expect(contains(output, 'Cannot call "fail" after its test or hook has finished running.')).to.equal(
                        true
                    )
                end)
            end)
        end
    end

    for _, mode in EXECUTION_MODES do
        describe(`threads Testable did not start with {mode.Name} execution`, function()
            it("should reject fail from required functions and name the fix", function()
                const ok, output = Subprocess.runScript(buildScript(
                    SPEC_STYLES[1],
                    mode.Parallel,
                    [[
                        describe("block", function()
                            it("spawns a thread", function()
                                task.spawn(function()
                                    const failOk, failMessage = pcall(fail, "from nowhere")
                                    print("THREAD_OK:" .. tostring(failOk))
                                    print("THREAD_MESSAGE:" .. tostring(failMessage))
                                    print("THREAD_EXPECT:" .. tostring(pcall(function()
                                        expect(1).to.equal(1)
                                    end)))
                                end)
                            end)
                        end)
                    ]]
                ))

                expect(ok).to.equal(true)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "THREAD_OK:false")).to.equal(true)
                expect(contains(output, 'Cannot call "fail" outside of a running test or hook.')).to.equal(true)
                expect(contains(output, "Testable.bindTest")).to.equal(true)
                expect(contains(output, "THREAD_EXPECT:true")).to.equal(true)
            end)

            it("should keep failing the declaring test from injected globals", function()
                const ok, output = Subprocess.runScript(buildScript(
                    SPEC_STYLES[2],
                    mode.Parallel,
                    [[
                        describe("block", function()
                            it("spawns a thread", function()
                                task.spawn(function()
                                    fail("from a spawned thread")
                                end)
                            end)
                        end)
                    ]]
                ))

                expect(ok).to.equal(false)
                expect(contains(output, "FAILED:spawns a thread")).to.equal(true)
                expect(contains(output, "from a spawned thread")).to.equal(true)
            end)
        end)
    end
end
