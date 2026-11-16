--!nocheck

--[[

RemoteTestScript

Test script that runs inside a real Roblox place via the Open Cloud Luau Execution API.
Exercises Testable in a Roblox server environment, covering describe/it/expect, dictionary
and array syntax, matchers (including typeof names of Roblox datatypes), lifecycle hooks,
coverage degrading gracefully, the requirable spec API under parallel execution, per-test
timeouts, snapshots through a memory store, skip reasons, the name filter, the JSON
reporter, and Discovery being absent.

Every check prints one "[PASS] name" or "[FAIL] name - error" line, and the script ends
with a "[DONE] count" line. Tests/Helpers/RemoteResults.luau parses those lines, so a
script that stops early is reported instead of passing with fewer checks.

--]]

const HttpService = game:GetService("HttpService")

const ok, Testable = pcall(require, game.ReplicatedStorage.Testable)
if not ok then
    print("[FAIL] Module load - " .. tostring(Testable))
    return
end

local checkCount = 0

const function test(name, fn)
    checkCount += 1
    const success, err = pcall(fn)
    -- A check that fails partway through must not leave its settings on for the next one.
    Testable.resetConfig()
    if success then
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. " - " .. tostring(err))
    end
end

-- Returns the result nodes of every test in a run, keyed by the test's phrase.
const function collectTests(results)
    const tests = {}
    results:visitAllNodes(function(node)
        if node.planNode.type == "It" then
            tests[node.planNode.phrase] = node
        end
    end)
    return tests
end

-- Returns the errors of a result node as one string.
const function errorsOf(node)
    return table.concat(node.errors, "\n")
end

const function contains(text, substring)
    return string.find(text, substring, 1, true) ~= nil
end

-- Test 1: Basic describe/it/expect
test("Basic describe/it/expect", function()
    const _, passed = Testable.run({
        BasicTest = function()
            describe("Basic math", function()
                it("should add numbers", function()
                    expect(1 + 1).to.equal(2)
                end)

                it("should subtract numbers", function()
                    expect(5 - 3).to.equal(2)
                end)
            end)
        end,
    })
    assert(passed, "Basic tests should pass")
end)

-- Test 2: Dictionary syntax for test roots
test("Dictionary syntax", function()
    local ran = false
    const _, passed = Testable.run({
        DictTest = function()
            describe("Dict syntax", function()
                it("runs from dict", function()
                    ran = true
                    expect(true).to.be.ok()
                end)
            end)
        end,
    })
    assert(passed, "Dict syntax tests should pass")
    assert(ran, "Test should have actually run")
end)

-- Test 3: Array syntax (backwards compat)
test("Array syntax (backwards compat)", function()
    Testable.resetConfig()
    const _, passed = Testable.run({
        {
            Name = "ArrayTest",
            Func = function()
                describe("Array syntax", function()
                    it("works", function()
                        expect("hello").to.be.a("string")
                    end)
                end)
            end,
        },
    })
    assert(passed, "Array syntax tests should pass")
end)

-- Test 4: Expect matchers
test("Expect matchers", function()
    Testable.resetConfig()
    const _, passed = Testable.run({
        MatcherTest = function()
            describe("Matchers", function()
                it("equal", function()
                    expect(42).to.equal(42)
                end)

                it("ok", function()
                    expect("value").to.be.ok()
                end)

                it("type check", function()
                    expect(true).to.be.a("boolean")
                    expect(123).to.be.a("number")
                    expect("hi").to.be.a("string")
                end)

                it("never", function()
                    expect(1).never.to.equal(2)
                    expect(nil).never.to.be.ok()
                end)

                it("throw", function()
                    expect(function()
                        error("boom")
                    end).to.throw()
                end)

                it("near", function()
                    expect(3.14159).to.be.near(3.14159, 0.001)
                end)
            end)
        end,
    })
    assert(passed, "Matcher tests should pass")
end)

-- Test 5: Coverage gracefully returns nil in Roblox
test("Coverage returns nil in Roblox", function()
    const Coverage = Testable.Coverage
    const report = Coverage.collect({ game.ReplicatedStorage })
    assert(report == nil, "Coverage.collect should return nil in Roblox")
end)

-- Test 6: Coverage config errors gracefully in Roblox
test("Coverage config errors in Roblox", function()
    Testable.resetConfig()
    const configOk, configErr = pcall(function()
        Testable.configure({ Coverage = true })
    end)
    assert(not configOk, "Coverage = true should error in Roblox")
    assert(string.find(tostring(configErr), "iscoverageenabled"), "Error should mention iscoverageenabled")
end)

-- Test 7: Lifecycle hooks
test("Lifecycle hooks", function()
    Testable.resetConfig()
    const hookOrder = {}
    const _, passed = Testable.run({
        LifecycleTest = function()
            describe("Lifecycle", function()
                beforeAll(function()
                    table.insert(hookOrder, "beforeAll")
                end)

                beforeEach(function()
                    table.insert(hookOrder, "beforeEach")
                end)

                afterEach(function()
                    table.insert(hookOrder, "afterEach")
                end)

                it("first test", function()
                    table.insert(hookOrder, "test1")
                end)

                it("second test", function()
                    table.insert(hookOrder, "test2")
                end)
            end)
        end,
    })
    assert(passed, "Lifecycle tests should pass")
    assert(#hookOrder >= 5, "Should have at least 5 hook events, got " .. #hookOrder)
end)

-- Test 8: Spec API required from Testable, with global injection turned off
test("Required spec API without injected globals", function()
    Testable.resetConfig()
    Testable.configure({ InjectGlobals = false })

    -- Shadow the globals so that a pass can only come from the required functions.
    const beforeEach, describe, expect, it = Testable.beforeEach, Testable.describe, Testable.expect, Testable.it
    local injected = true
    local setup = 0

    const runOk, results, passed = pcall(Testable.run, {
        RequiredTest = function()
            -- Not shadowed above, so this is only set when Testable injects it.
            injected = xit ~= nil

            describe("Required", function()
                beforeEach(function()
                    setup += 1
                    expect.extend({
                        beEven = function(value)
                            return { message = "Expected an even number", pass = value % 2 == 0 }
                        end,
                    })
                end)

                it("uses a matcher from its own hook after yielding", function()
                    task.wait(0.05)
                    expect(4).to.beEven()
                end)

                it("runs alongside it", function()
                    task.wait(0.02)
                    expect(setup).to.equal(2)
                    expect(2).to.beEven()
                end)
            end)
        end,
    })

    Testable.resetConfig()
    assert(runOk, tostring(results))
    assert(passed, "Required spec API tests should pass")
    assert(results.successCount == 2, "Should have run 2 tests, got " .. results.successCount)
    assert(not injected, "Globals should not be injected when InjectGlobals is false")
end)

-- Test 9: fail() and late registration are tied to the test that called them
test("Required spec API ties failures to the calling test", function()
    Testable.resetConfig()

    const describe, fail, it = Testable.describe, Testable.fail, Testable.it
    const failed = {}

    const results, passed = Testable.run({
        FailingTest = function()
            describe("Failing", function()
                it("fails late", function()
                    task.wait(0.05)
                    fail("late failure")
                end)

                it("passes meanwhile", function()
                    task.wait(0.1)
                end)

                it("registers too late", function()
                    it("never runs", function() end)
                end)
            end)
        end,
    })

    results:visitAllNodes(function(node)
        if node.planNode.type == "It" and node.status == "Failure" then
            failed[node.planNode.phrase] = table.concat(node.errors, "\n")
        end
    end)

    assert(not passed, "The run should fail")
    assert(results.failureCount == 2, "Should have 2 failures, got " .. results.failureCount)
    assert(results.successCount == 1, "Should have 1 success, got " .. results.successCount)
    assert(failed["fails late"] and string.find(failed["fails late"], "late failure", 1, true), "Wrong test failed")
    assert(
        failed["registers too late"]
            and string.find(failed["registers too late"], "while a test or hook is running", 1, true),
        "Late registration should be an error"
    )
end)

-- Test 10: Parallel tests each get their own expect, whichever started last
test("Required expect binds to the calling test in parallel mode", function()
    Testable.resetConfig()
    Testable.configure({ InjectGlobals = false, MaxConcurrency = 4, Parallel = true })

    const bindTest, describe, expect, it = Testable.bindTest, Testable.describe, Testable.expect, Testable.it
    const seesOther = {}
    local boundOk, boundError = nil, nil
    local maxRunning = 0
    local running = 0
    local unboundOk = nil

    -- Declares a test that adds a matcher of its own, yields while the other tests add
    -- theirs, and then checks that it still sees its own matcher and not another one.
    const function declare(name, ownMatcher, otherMatcher, delay)
        it(name, function()
            running += 1
            maxRunning = math.max(maxRunning, running)
            expect.extend({
                [ownMatcher] = function(value)
                    return { message = `Expected "{name}"`, pass = value == name }
                end,
            })
            task.wait(delay)
            seesOther[name] = pcall(function()
                expect(name).to[otherMatcher]()
            end)
            running -= 1
            expect(name).to[ownMatcher]()
        end)
    end

    const results, passed = Testable.run({
        ParallelTest = function()
            describe("Parallel", function()
                declare("alpha", "beAlpha", "beBeta", 0.15)
                declare("beta", "beBeta", "beAlpha", 0.05)

                it("fails with its own matcher", function()
                    expect.extend({
                        beGamma = function(value)
                            return { message = "Expected gamma", pass = value == "gamma" }
                        end,
                    })
                    task.wait(0.1)
                    expect("delta").to.beGamma()
                end)

                it("reaches other threads through bindTest", function()
                    expect.extend({
                        beBound = function()
                            return { message = "Expected bound", pass = true }
                        end,
                    })
                    const check = function()
                        expect("bound").to.beBound()
                    end
                    const boundCheck = bindTest(check)
                    local finished = false
                    task.spawn(function()
                        task.wait(0.05)
                        unboundOk = pcall(check)
                        boundOk, boundError = pcall(boundCheck)
                        finished = true
                    end)
                    while not finished do
                        task.wait()
                    end
                end)
            end)
        end,
    })

    const tests = collectTests(results)
    assert(not passed, "The run should fail because of the one failing test")
    assert(results.successCount == 3, "Should have 3 successes, got " .. results.successCount)
    assert(results.failureCount == 1, "Should have 1 failure, got " .. results.failureCount)
    assert(maxRunning >= 2, "Tests should have overlapped, but at most " .. maxRunning .. " ran at once")
    assert(seesOther.alpha == false, '"alpha" should not see the matcher of "beta"')
    assert(seesOther.beta == false, '"beta" should not see the matcher of "alpha"')
    assert(tests["fails with its own matcher"].status == "Failure", "The wrong test failed")
    assert(contains(errorsOf(tests["fails with its own matcher"]), "Expected gamma"), "The wrong matcher failed")
    assert(boundOk == true, "A bound function should see the matchers of its test, got " .. tostring(boundError))
    assert(unboundOk == false, "An unbound thread should only see the built-in matchers")
end)

-- Test 11: A test over its Config.Timeout budget is cancelled and the run carries on
test("Config.Timeout cancels a slow test and the run continues", function()
    Testable.resetConfig()
    Testable.configure({ Timeout = 0.3 })

    const afterEach, describe, it = Testable.afterEach, Testable.describe, Testable.it
    local cleanups = 0
    local resumed = false
    const startTime = os.clock()

    const results, passed = Testable.run({
        TimeoutTest = function()
            describe("Timeout", function()
                afterEach(function()
                    cleanups += 1
                end)

                it("runs out of time", function()
                    task.wait(1.5)
                    resumed = true
                end)

                it("finishes in time", function()
                    task.wait(0.05)
                end)

                it("has a longer budget of its own", function()
                    task.wait(0.6)
                end, { Timeout = 10 })
            end)
        end,
    })
    const elapsed = os.clock() - startTime

    const tests = collectTests(results)
    const message = errorsOf(tests["runs out of time"])
    assert(not passed, "The run should fail because of the timeout")
    assert(results.failureCount == 1, "Should have 1 failure, got " .. results.failureCount)
    assert(results.successCount == 2, "Should have 2 successes, got " .. results.successCount)
    assert(tests["runs out of time"].status == "Failure", "The slow test should fail")
    assert(contains(message, "timed out after exceeding its budget of 0.3 seconds"), "Wrong message, got " .. message)
    assert(contains(message, "the Timeout configuration option"), "Wrong budget source, got " .. message)
    assert(tests["finishes in time"].status == "Success", "The fast test should pass")
    assert(tests["has a longer budget of its own"].status == "Success", "The test's own Timeout should win")
    assert(cleanups == 3, "afterEach should run for all 3 tests, ran " .. cleanups .. " times")
    assert(elapsed < 1.4, "The run should not wait for the cancelled test, took " .. elapsed .. " seconds")

    -- Wait past the point where the slow test would have resumed if it were still alive.
    task.wait(1.5 - elapsed + 0.3)
    assert(not resumed, "The timed out test should have been cancelled")
end)

-- Test 12: A test that never times out keeps the budget out of its way
test("Config.Timeout leaves tests within budget alone", function()
    Testable.resetConfig()
    Testable.configure({ Timeout = 5 })

    const describe, expect, it = Testable.describe, Testable.expect, Testable.it
    const results, passed = Testable.run({
        BudgetTest = function()
            describe("Budget", function()
                it("yields and passes", function()
                    task.wait(0.05)
                    expect(1).to.equal(1)
                end)

                it("fails on its own", function()
                    task.wait(0.05)
                    expect(1).to.equal(2)
                end)
            end)
        end,
    })

    const tests = collectTests(results)
    assert(not passed, "The run should fail because of the failing expectation")
    assert(tests["yields and passes"].status == "Success", "The passing test should pass")
    assert(tests["fails on its own"].status == "Failure", "The failing test should fail")
    assert(not contains(errorsOf(tests["fails on its own"]), "timed out"), "The failure should not be a timeout")
end)

-- Test 13: Snapshots are written, matched, mismatched, and updated in a memory store
test("Snapshots round trip through MemorySnapshotStore", function()
    const describe, expect, it = Testable.describe, Testable.expect, Testable.it
    const store = Testable.Snapshots.MemorySnapshotStore.new()

    const function runWith(value, options)
        Testable.resetConfig()
        Testable.configure(options)
        const results, passed = Testable.run({
            SnapshotTest = function()
                describe("Snapshots", function()
                    it("matches the stored value", function()
                        task.wait(0.02)
                        expect(value).to.matchSnapshot()
                        expect("a label").to.matchSnapshot("labelled")
                    end)
                end)
            end,
        })
        Testable.resetConfig()
        return results, passed
    end

    const function readOnlyFile()
        local contents = nil
        local count = 0
        for _, fileContents in store.Files do
            contents = fileContents
            count += 1
        end
        assert(count == 1, "The store should hold exactly 1 snapshot file, got " .. count)
        return contents
    end

    const first = { Name = "first", Tags = { "a", "b" } }

    local results, passed = runWith(first, { SnapshotStore = store })
    assert(passed, "The first run should pass and write the snapshots")
    assert(results.snapshotSummary.Written == 2, "Should have written 2, got " .. results.snapshotSummary.Written)
    const written = readOnlyFile()
    assert(contains(written, '"first"'), "The snapshot file should hold the value, got " .. written)

    results, passed = runWith(table.clone(first), { SnapshotStore = store })
    assert(passed, "An equal value should match its snapshot")
    assert(results.snapshotSummary.Matched == 2, "Should have matched 2, got " .. results.snapshotSummary.Matched)
    assert(results.snapshotSummary.Written == 0, "A matching run should write nothing")
    assert(readOnlyFile() == written, "A matching run should leave the file alone")

    results, passed = runWith({ Name = "second", Tags = { "a", "b" } }, { SnapshotStore = store })
    const mismatch = errorsOf(collectTests(results)["matches the stored value"])
    assert(not passed, "A different value should fail")
    assert(results.snapshotSummary.Failed == 1, "Should have failed 1, got " .. results.snapshotSummary.Failed)
    assert(contains(mismatch, "did not match"), "Wrong mismatch message, got " .. mismatch)
    assert(contains(mismatch, '"second"'), "The diff should show the received value, got " .. mismatch)
    assert(readOnlyFile() == written, "A mismatch should leave the file alone")

    results, passed = runWith(
        { Name = "second", Tags = { "a", "b" } },
        { SnapshotStore = store, UpdateSnapshots = true }
    )
    assert(passed, "Update mode should accept the new value")
    assert(results.snapshotSummary.Updated == 1, "Should have updated 1, got " .. results.snapshotSummary.Updated)
    assert(contains(readOnlyFile(), '"second"'), "Update mode should rewrite the file")

    -- Roblox has no filesystem to fall back on, so a run without a store has to say so.
    results, passed = runWith(first, {})
    const noStore = errorsOf(collectTests(results)["matches the stored value"])
    assert(not passed, "A snapshot without a store should fail")
    assert(contains(noStore, "Snapshots need a store"), "Wrong message without a store, got " .. noStore)
end)

-- Snapshots compare Roblox datatypes by value instead of only by type
test("Snapshots tell Roblox datatypes apart", function()
    const describe, expect, it = Testable.describe, Testable.expect, Testable.it
    const store = Testable.Snapshots.MemorySnapshotStore.new()

    const function runWith(position)
        Testable.resetConfig()
        Testable.configure({ SnapshotStore = store })
        const results, passed = Testable.run({
            DatatypeSnapshotTest = function()
                describe("Datatype snapshots", function()
                    it("matches the stored datatypes", function()
                        expect({
                            Color = Color3.new(1, 0, 0),
                            Frame = CFrame.new(4, 5, 6),
                            Key = Enum.KeyCode.A,
                            Position = position,
                            Size = UDim2.fromScale(1, 0.5),
                        }).to.matchSnapshot()
                    end)
                end)
            end,
        })
        Testable.resetConfig()
        return results, passed
    end

    local results, passed = runWith(Vector3.new(1, 2, 3))
    assert(passed, "The first run should pass and write the snapshot")
    assert(results.snapshotSummary.Written == 1, "Should have written 1, got " .. results.snapshotSummary.Written)

    results, passed = runWith(Vector3.new(1, 2, 3))
    assert(passed, "Equal datatypes should match their snapshot")
    assert(results.snapshotSummary.Matched == 1, "Should have matched 1, got " .. results.snapshotSummary.Matched)

    results, passed = runWith(Vector3.new(3, 2, 1))
    assert(not passed, "A different Vector3 should not match the snapshot")
    const mismatch = errorsOf(collectTests(results)["matches the stored datatypes"])
    assert(contains(mismatch, "Vector3(3, 2, 1)"), "The diff should show the received Vector3, got " .. mismatch)
end)

-- Test 14: The newer matchers, including typeof names of real Roblox datatypes
test("Matchers accept Roblox datatypes", function()
    Testable.resetConfig()

    const describe, expect, it = Testable.describe, Testable.expect, Testable.it
    const part = Instance.new("Part")
    const results, passed = Testable.run({
        DatatypeTest = function()
            describe("Datatypes", function()
                it("names types the way typeof does", function()
                    expect(Vector3.new(1, 2, 3)).to.be.a("Vector3")
                    expect(CFrame.identity).to.be.a("CFrame")
                    expect(Color3.new(1, 0, 0)).to.be.a("Color3")
                    expect(UDim2.fromScale(1, 1)).to.be.a("UDim2")
                    expect(Enum.KeyCode.A).to.be.an("EnumItem")
                    expect(part).to.be.an("Instance")
                end)

                it("still names types the way type does", function()
                    expect(CFrame.identity).to.be.a("userdata")
                    expect(part).to.be.a("userdata")
                    expect(Vector3.zero).to.be.a(type(Vector3.zero))
                    expect({}).to.be.a("table")
                end)

                it("tells datatypes apart", function()
                    expect(Vector3.zero).never.to.be.a("CFrame")
                    expect(CFrame.identity).never.to.be.a("Vector3")
                    expect(part).never.to.be.a("Part")
                    expect(5).never.to.be.a("Vector3")
                end)

                it("compares datatypes by value", function()
                    expect(Vector3.new(1, 2, 3)).to.equal(Vector3.new(1, 2, 3))
                    expect(Vector3.new(1, 2, 3)).never.to.equal(Vector3.new(3, 2, 1))
                    expect({ Position = Vector3.new(1, 2, 3), Tags = { "a" } }).to.deepEqual({
                        Position = Vector3.new(1, 2, 3),
                        Tags = { "a" },
                    })
                    expect({ Position = Vector3.zero }).never.to.deepEqual({ Position = Vector3.one })
                    expect({ Vector3.zero, Vector3.one }).to.contain(Vector3.one)
                    expect({ Vector3.zero }).never.to.contain(Vector3.one)
                end)

                it("covers the other matchers", function()
                    expect("hello world").to.contain("world")
                    expect({ 1, 2, 3 }).to.have.length(3)
                    expect("abc123").to.match("^%a+%d+$")
                    expect(5).to.be.greaterThan(4)
                    expect(5).to.be.greaterThanOrEqual(5)
                    expect(4).to.be.lessThan(5)
                    expect(5).to.be.lessThanOrEqual(5)
                    expect(0).to.be.truthy()
                    expect(false).to.be.falsy()
                    expect(nil).to.be.none()
                    expect(function()
                        part.Parent = 5
                    end).to.throw()
                    expect(function()
                        error("a specific problem")
                    end).to.throw("specific")
                end)
            end)
        end,
    })

    assert(passed, "Datatype matcher tests should pass")
    assert(results.successCount == 5, "Should have run 5 tests, got " .. results.successCount)
end)

-- Test 15: The same matchers fail, with readable messages, when they should
test("Matchers reject mismatched Roblox datatypes", function()
    Testable.resetConfig()

    const describe, expect, it = Testable.describe, Testable.expect, Testable.it
    const results, passed = Testable.run({
        MismatchTest = function()
            describe("Mismatches", function()
                it("wrong typeof name", function()
                    expect(Vector3.new(1, 2, 3)).to.be.a("CFrame")
                end)

                it("negated typeof name", function()
                    expect(Vector3.zero).never.to.be.a("Vector3")
                end)

                it("unequal datatypes", function()
                    expect(Vector3.new(1, 2, 3)).to.equal(Vector3.new(3, 2, 1))
                end)

                it("unequal nested datatypes", function()
                    expect({ Position = Vector3.zero }).to.deepEqual({ Position = Vector3.one })
                end)

                it("misused matcher", function()
                    expect(Vector3.zero).to.have.length(3)
                end)
            end)
        end,
    })

    const tests = collectTests(results)
    assert(not passed, "The run should fail")
    assert(results.failureCount == 5, "Should have 5 failures, got " .. results.failureCount)
    assert(results.successCount == 0, "Should have no successes, got " .. results.successCount)

    const wrongType = errorsOf(tests["wrong typeof name"])
    assert(contains(wrongType, 'Expected value of type "CFrame"'), "Wrong message, got " .. wrongType)
    assert(contains(wrongType, "of type Vector3"), "The message should name the real type, got " .. wrongType)
    assert(contains(wrongType, "1, 2, 3"), "The message should show the value, got " .. wrongType)

    const negated = errorsOf(tests["negated typeof name"])
    assert(contains(negated, 'Expected value not of type "Vector3"'), "Wrong message, got " .. negated)

    const unequal = errorsOf(tests["unequal datatypes"])
    assert(contains(unequal, "3, 2, 1") and contains(unequal, "1, 2, 3"), "Wrong message, got " .. unequal)

    const misused = errorsOf(tests["misused matcher"])
    assert(contains(misused, 'Matcher "length" expects the value to be a string or a table'), "Got " .. misused)
    assert(contains(misused, "Vector3"), "The misuse message should name the real type, got " .. misused)
end)

-- Test 16: Skip variants report their reasons and never run their bodies
test("Skip reasons and itTODO", function()
    Testable.resetConfig()

    const describe, describeSKIP, it = Testable.describe, Testable.describeSKIP, Testable.it
    const itFIXME, itSKIP, itTODO, xit = Testable.itFIXME, Testable.itSKIP, Testable.itTODO, Testable.xit
    local ranSkipped = false
    const function mustNotRun()
        ranSkipped = true
    end

    const results, passed = Testable.run({
        SkipTest = function()
            describe("Skips", function()
                it("runs", function() end)
                itSKIP("skipped with a reason", mustNotRun, "needs a physics step")
                xit("skipped without a reason", mustNotRun)
                itFIXME("known to be broken", mustNotRun, "fails on servers")
                itTODO("still to be written")

                describeSKIP("Skipped block", function()
                    it("inherits the reason of its block", mustNotRun)
                    itSKIP("keeps a reason of its own", mustNotRun, "its own reason")
                end, "the whole block is off")
            end)
        end,
    })

    const tests = collectTests(results)
    const function reasonOf(phrase)
        assert(tests[phrase].status == "Skipped", `"{phrase}" should be skipped, got {tests[phrase].status}`)
        return tests[phrase].skipReason
    end

    assert(passed, "Skipped tests should not fail the run")
    assert(not ranSkipped, "The body of a skipped test should never run")
    assert(results.successCount == 1, "Should have 1 success, got " .. results.successCount)
    assert(results.skippedCount == 6, "Should have 6 skipped, got " .. results.skippedCount)
    assert(reasonOf("skipped with a reason") == "needs a physics step", "Wrong itSKIP reason")
    assert(reasonOf("skipped without a reason") == nil, "xit without a reason should have none")
    assert(reasonOf("known to be broken") == "fixme, fails on servers", "Wrong itFIXME reason")
    assert(reasonOf("still to be written") == "todo", "Wrong itTODO reason")
    assert(reasonOf("inherits the reason of its block") == "the whole block is off", "Wrong inherited reason")
    assert(reasonOf("keeps a reason of its own") == "its own reason", "A test's own reason should win")
end)

-- Test 17: Misused skip variants are planning errors instead of silent skips
test("Skip variants reject bad arguments", function()
    Testable.resetConfig()

    const describe, it, itSKIP, itTODO = Testable.describe, Testable.it, Testable.itSKIP, Testable.itTODO
    const results, passed = Testable.run({
        BadSkipTest = function()
            describe("A todo with a body", function()
                itTODO("has a body", function() end)
            end)

            describe("A reason that is not a string", function()
                itSKIP("has a bad reason", function() end, Vector3.zero)
            end)

            describe("Unaffected", function()
                it("still runs", function() end)
            end)
        end,
    })

    const planningErrors = table.concat(results.errors, "\n")
    assert(not passed, "Planning errors should fail the run")
    assert(results.failureCount == 2, "Should have 2 failures, got " .. results.failureCount)
    assert(results.successCount == 1, "Should have 1 success, got " .. results.successCount)
    assert(contains(planningErrors, '"itTODO" only takes a name'), "Missing itTODO error, got " .. planningErrors)
    assert(contains(planningErrors, "must be a string, got Vector3"), "Missing reason error, got " .. planningErrors)
end)

-- Test 18: The name filter narrows the run and skips everything else with a reason
test("Name filter", function()
    Testable.resetConfig()
    Testable.configure({ Filter = "Kept block" })

    const beforeAll, describe, it = Testable.beforeAll, Testable.describe, Testable.it
    const ran = {}
    local excludedHookRan = false

    const results, passed = Testable.run({
        FilterTest = function()
            describe("Kept block", function()
                it("first", function()
                    table.insert(ran, "first")
                end)

                it("second", function()
                    table.insert(ran, "second")
                end)
            end)

            describe("Dropped block", function()
                beforeAll(function()
                    excludedHookRan = true
                end)

                it("third", function()
                    table.insert(ran, "third")
                end)
            end)
        end,
    })

    const tests = collectTests(results)
    table.sort(ran)
    assert(passed, "The filtered run should pass")
    assert(table.concat(ran, ",") == "first,second", "Wrong tests ran, got " .. table.concat(ran, ","))
    assert(results.successCount == 2, "Should have 2 successes, got " .. results.successCount)
    assert(results.skippedCount == 1, "Should have 1 skipped, got " .. results.skippedCount)
    assert(results.filteredCount == 1, "Should have 1 filtered out, got " .. results.filteredCount)
    assert(tests.third.status == "Skipped", "The filtered-out test should be skipped")
    assert(tests.third.skipReason == "excluded by filter", "Wrong reason, got " .. tostring(tests.third.skipReason))
    assert(not excludedHookRan, "Hooks of a block with no selected tests should not run")
end)

-- Test 19: A filter that matches nothing is a tool error, not a passing run
test("Name filter that matches nothing", function()
    Testable.resetConfig()
    Testable.configure({ Filter = "no test has this name" })

    const describe, it = Testable.describe, Testable.it
    local ran = false
    const tests = {
        EmptyFilterTest = function()
            describe("Anything", function()
                it("runs", function()
                    ran = true
                end)
            end)
        end,
    }

    const runOk, problem = pcall(Testable.run, tests)
    assert(not runOk, "The run should throw")
    assert(Testable.ToolError.is(problem), "The error should be a tool error, got " .. tostring(problem))
    assert(problem.Kind == Testable.ToolError.Kind.EmptyFilter, "Wrong kind, got " .. tostring(problem.Kind))
    assert(not ran, "No test should have run")

    const exitCode = Testable.runToExitCode(tests)
    assert(exitCode == Testable.ExitCode.ToolError, "runToExitCode should return 2, got " .. tostring(exitCode))
end)

-- Test 20: The JSON reporter renders a document that Roblox itself can decode
test("JSON reporter produces a string", function()
    Testable.resetConfig()
    -- With no text reporter, the JSON document is what the run prints.
    Testable.configure({ Reporters = { "Json" } })

    const describe, expect, it, itSKIP = Testable.describe, Testable.expect, Testable.it, Testable.itSKIP
    const results, passed = Testable.run({
        JsonTest = function()
            describe("Json", function()
                it("passes", function() end)

                it('fails with "quotes"\tand a tab', function()
                    expect(Vector3.zero).to.equal(Vector3.one)
                end)

                itSKIP("is skipped", function() end, "not today")
            end)
        end,
    })
    assert(not passed, "The run should fail because of the one failing test")

    const document = Testable.Reporters.JsonReporter.format(results)
    assert(type(document) == "string", "The document should be a string, got " .. typeof(document))
    assert(document == Testable.Reporters.JsonReporter.format(results), "Formatting twice should give the same text")

    const decoded = HttpService:JSONDecode(document)
    assert(decoded.Version == 1, "Wrong version, got " .. tostring(decoded.Version))
    assert(decoded.Totals.Total == 3, "Wrong total, got " .. tostring(decoded.Totals.Total))
    assert(decoded.Totals.Passed == 1, "Wrong passed count, got " .. tostring(decoded.Totals.Passed))
    assert(decoded.Totals.Failed == 1, "Wrong failed count, got " .. tostring(decoded.Totals.Failed))
    assert(decoded.Totals.Skipped == 1, "Wrong skipped count, got " .. tostring(decoded.Totals.Skipped))

    const cases = decoded.Suites[1].Children[1].Children
    assert(decoded.Suites[1].Name == "JsonTest", "Wrong suite name, got " .. tostring(decoded.Suites[1].Name))
    assert(#cases == 3, "Should have 3 cases, got " .. #cases)
    assert(cases[1].Status == "Success", "The first case should pass")
    assert(cases[2].Name == 'fails with "quotes"\tand a tab', "Escaped names should survive, got " .. cases[2].Name)
    assert(cases[2].Status == "Failure", "The second case should fail")
    assert(type(cases[2].ErrorMessage) == "string", "A failed case should carry its error message")
    assert(cases[3].Status == "Skipped", "The third case should be skipped")
    assert(cases[3].SkipReason == "not today", "Wrong skip reason, got " .. tostring(cases[3].SkipReason))

    const junit = Testable.Reporters.JUnitReporter.format(results)
    assert(type(junit) == "string" and contains(junit, "<testsuites"), "The JUnit report should be XML text")
end)

-- Test 21: Reports can't be written to files without a filesystem
test("Reporter output paths error in Roblox", function()
    Testable.resetConfig()
    Testable.configure({ ReporterOutputs = { Json = "Build/results.json" }, Reporters = { "Json" } })

    const describe, it = Testable.describe, Testable.it
    const runOk, problem = pcall(Testable.run, {
        OutputTest = function()
            describe("Output", function()
                it("passes", function() end)
            end)
        end,
    })

    assert(not runOk, "Writing a report file should error in Roblox")
    assert(contains(tostring(problem), "can only write files in Lune"), "Wrong error, got " .. tostring(problem))
end)

-- Test 22: Discovery needs Lune, so it is left out without breaking the require
test("Discovery is nil in Roblox", function()
    assert(Testable.Discovery == nil, "Testable.Discovery should be nil in Roblox")
    assert(type(Testable.run) == "function", "The rest of the module should still load")
    assert(type(Testable.Snapshots.MemorySnapshotStore.new) == "function", "The memory snapshot store should load")
    assert(game.ReplicatedStorage.Testable:FindFirstChild("Discovery") ~= nil, "The Discovery module should be present")
end)

print("[DONE] " .. checkCount)
