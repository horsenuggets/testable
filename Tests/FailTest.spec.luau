--[[

FailTest.spec

Tests for the fail() function in the Testable framework. Uses subprocess execution to
verify that fail() actually causes tests to fail with the expected exit codes.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local testCounter = 0

local function createTempScript(): string
    testCounter += 1
    local timestamp = os.time()
    local random = math.random(100000, 999999)
    local scriptName = `_temp_fail_test_{timestamp}_{testCounter}_{random}.luau`
    return scriptName
end

local function runTestScript(scriptContent: string): (boolean, string)
    local scriptName = createTempScript()
    local projectRoot = process.cwd

    -- Write the test script to the project root (where lune is available)
    fs.writeFile(`{projectRoot}/{scriptName}`, scriptContent)

    -- Run the test script with lune from the project root
    local result = process.exec("lune", { "run", scriptName }, {
        cwd = projectRoot,
    })

    local output = (result.stdout or "") .. (result.stderr or "")

    -- Clean up the temp script
    fs.removeFile(`{projectRoot}/{scriptName}`)

    return result.ok, output
end

return function()
    describe("fail() function", function()
        it("should be available in test environment", function()
            expect(fail).to.be.a("function")
        end)

        -- All subprocess tests are combined into a single test to avoid parallel execution issues.
        -- Each subprocess creates its own isolated Testable instance.
        it("should cause tests to fail correctly (subprocess tests)", function()
            -- Test 1: fail without message
            do
                local scriptContent = [[
                    local Testable = require("./Source/Testable")

                    local tests = {
                        {
                            Name = "FailingTest",
                            Func = function()
                                describe("fail test", function()
                                    it("should fail", function()
                                        fail()
                                    end)
                                end)
                            end,
                        },
                    }

                    local _, passed = Testable.run(tests)
                    local process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                local success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "fail() was called", 1, true)).to.be.ok()
            end

            -- Test 2: fail with custom message
            do
                local scriptContent = [[
                    local Testable = require("./Source/Testable")

                    local tests = {
                        {
                            Name = "FailingTest",
                            Func = function()
                                describe("fail test", function()
                                    it("should fail with message", function()
                                        fail("custom failure message")
                                    end)
                                end)
                            end,
                        },
                    }

                    local _, passed = Testable.run(tests)
                    local process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                local success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "custom failure message", 1, true)).to.be.ok()
            end

            -- Test 3: fail should not affect other passing tests
            do
                local scriptContent = [[
                    local Testable = require("./Source/Testable")

                    local tests = {
                        {
                            Name = "MixedTest",
                            Func = function()
                                describe("mixed tests", function()
                                    it("should pass first", function()
                                        expect(true).to.equal(true)
                                    end)

                                    it("should fail", function()
                                        fail("intentional failure")
                                    end)

                                    it("should pass after failure", function()
                                        expect(true).to.equal(true)
                                    end)
                                end)
                            end,
                        },
                    }

                    local results, passed = Testable.run(tests)
                    print("PASS_COUNT:" .. results.successCount)
                    print("FAIL_COUNT:" .. results.failureCount)
                    local process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                local success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "PASS_COUNT:2", 1, true)).to.be.ok()
                expect(string.find(output, "FAIL_COUNT:1", 1, true)).to.be.ok()
            end

            -- Test 4: fail should work when called conditionally
            do
                local scriptContent = [[
                    local Testable = require("./Source/Testable")

                    local tests = {
                        {
                            Name = "ConditionalFailTest",
                            Func = function()
                                describe("conditional fail", function()
                                    it("should fail when condition is met", function()
                                        local shouldFail = true
                                        if shouldFail then
                                            fail("condition was met")
                                        end
                                    end)
                                end)
                            end,
                        },
                    }

                    local _, passed = Testable.run(tests)
                    local process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                local success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "condition was met", 1, true)).to.be.ok()
            end
        end)
    end)
end
