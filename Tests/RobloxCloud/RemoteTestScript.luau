--!nocheck

--[[

RemoteTestScript

Test script that runs inside a real Roblox place via the Open Cloud
Luau Execution API. Exercises Testable's core features in a Roblox
server environment: describe/it/expect, dictionary syntax, array
syntax, matchers, lifecycle hooks, and coverage graceful degradation.

--]]

const ok, Testable = pcall(require, game.ReplicatedStorage.Testable)
if not ok then
    print("[FAIL] Module load - " .. tostring(Testable))
    return
end

const function test(name, fn)
    const success, err = pcall(fn)
    if success then
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. " - " .. tostring(err))
    end
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
