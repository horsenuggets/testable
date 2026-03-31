--!nocheck

--[[

RemoteTestScript

Test script that runs inside a real Roblox place via the Open Cloud
Luau Execution API. Exercises Testable's core features in a Roblox
server environment: describe/it/expect, dictionary syntax, array
syntax, matchers, lifecycle hooks, and coverage graceful degradation.

--]]

local ok, Testable = pcall(require, game.ReplicatedStorage.Testable)
if not ok then
    print("[FAIL] Module load - " .. tostring(Testable))
    return
end

local function test(name, fn)
    local success, err = pcall(fn)
    if success then
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. " - " .. tostring(err))
    end
end

-- Test 1: Basic describe/it/expect
test("Basic describe/it/expect", function()
    local _, passed = Testable.run({
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
    local _, passed = Testable.run({
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
    local _, passed = Testable.run({
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
    local _, passed = Testable.run({
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
    local Coverage = Testable.Coverage
    local report = Coverage.collect({ game.ReplicatedStorage })
    assert(report == nil, "Coverage.collect should return nil in Roblox")
end)

-- Test 6: Coverage config errors gracefully in Roblox
test("Coverage config errors in Roblox", function()
    Testable.resetConfig()
    local configOk, configErr = pcall(function()
        Testable.configure({ Coverage = true })
    end)
    assert(not configOk, "Coverage = true should error in Roblox")
    assert(string.find(tostring(configErr), "iscoverageenabled"), "Error should mention iscoverageenabled")
end)

-- Test 7: Lifecycle hooks
test("Lifecycle hooks", function()
    Testable.resetConfig()
    local hookOrder = {}
    local _, passed = Testable.run({
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
