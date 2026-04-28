--!nocheck

--[[

RemoteTestScript

Test script that runs inside a real Roblox place via the Open Cloud Luau Execution API.
Exercises Testable's core features in a Roblox server environment and returns structured
results via the wire format (Base64-encoded JSON).

--]]

local ok, Testable = pcall(require, game.ReplicatedStorage.Testable)
if not ok then
    print("[FAIL] Module load - " .. tostring(Testable))
    return
end

local ResultSerializer = require(game.ReplicatedStorage.Testable.ResultSerializer)

-- Run the test suites
local results = Testable.run({
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

    DictSyntax = function()
        describe("Dictionary syntax", function()
            it("should run from dict", function()
                local ran = false
                ran = true
                expect(ran).to.be.ok()
            end)
        end)
    end,

    Matchers = function()
        describe("Matchers", function()
            it("should check equal", function()
                expect(42).to.equal(42)
            end)

            it("should check ok", function()
                expect("value").to.be.ok()
            end)

            it("should check type", function()
                expect(true).to.be.a("boolean")
                expect(123).to.be.a("number")
                expect("hi").to.be.a("string")
            end)

            it("should check never", function()
                expect(1).never.to.equal(2)
                expect(nil).never.to.be.ok()
            end)

            it("should check throw", function()
                expect(function()
                    error("boom")
                end).to.throw()
            end)

            it("should check near", function()
                expect(3.14159).to.be.near(3.14159, 0.001)
            end)
        end)
    end,

    CoverageGraceful = function()
        describe("Coverage in Roblox", function()
            it("should return nil from Coverage.collect", function()
                local Coverage = Testable.Coverage
                local report = Coverage.collect({ game.ReplicatedStorage })
                expect(report).to.equal(nil)
            end)

            it("should error when enabling Coverage config", function()
                Testable.resetConfig()
                expect(function()
                    Testable.configure({ Coverage = true })
                end).to.throw()
            end)
        end)
    end,

    Lifecycle = function()
        describe("Lifecycle hooks", function()
            local hookOrder = {}

            beforeAll(function()
                table.insert(hookOrder, "beforeAll")
            end)

            beforeEach(function()
                table.insert(hookOrder, "beforeEach")
            end)

            afterEach(function()
                table.insert(hookOrder, "afterEach")
            end)

            it("should run first test", function()
                table.insert(hookOrder, "test1")
            end)

            it("should run second test", function()
                table.insert(hookOrder, "test2")
                expect(#hookOrder >= 5).to.equal(true)
            end)
        end)
    end,
})

-- Encode and print structured results via wire format
print(ResultSerializer.encode(results))
