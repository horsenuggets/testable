--[[

FailTest.spec

Tests for the fail() function in the Testable framework. Uses subprocess execution to
verify that fail() actually causes tests to fail with the expected exit codes.

--]]

const Subprocess = require("./Helpers/Subprocess")

const runTestScript = Subprocess.runScript

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
                const scriptContent = [[
                    const Testable = require("./Source/Testable")

                    const tests = {
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

                    const _, passed = Testable.run(tests)
                    const process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                const success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "fail() was called", 1, true)).to.be.ok()
            end

            -- Test 2: fail with custom message
            do
                const scriptContent = [[
                    const Testable = require("./Source/Testable")

                    const tests = {
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

                    const _, passed = Testable.run(tests)
                    const process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                const success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "custom failure message", 1, true)).to.be.ok()
            end

            -- Test 3: fail should not affect other passing tests
            do
                const scriptContent = [[
                    const Testable = require("./Source/Testable")

                    const tests = {
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

                    const results, passed = Testable.run(tests)
                    print("PASS_COUNT:" .. results.successCount)
                    print("FAIL_COUNT:" .. results.failureCount)
                    const process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                const success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "PASS_COUNT:2", 1, true)).to.be.ok()
                expect(string.find(output, "FAIL_COUNT:1", 1, true)).to.be.ok()
            end

            -- Test 4: fail should work when called conditionally
            do
                const scriptContent = [[
                    const Testable = require("./Source/Testable")

                    const tests = {
                        {
                            Name = "ConditionalFailTest",
                            Func = function()
                                describe("conditional fail", function()
                                    it("should fail when condition is met", function()
                                        const shouldFail = true
                                        if shouldFail then
                                            fail("condition was met")
                                        end
                                    end)
                                end)
                            end,
                        },
                    }

                    const _, passed = Testable.run(tests)
                    const process = require("@lune/process")
                    process.exit(if passed then 0 else 1)
                ]]
                const success, output = runTestScript(scriptContent)
                expect(success).to.equal(false)
                expect(string.find(output, "condition was met", 1, true)).to.be.ok()
            end
        end)
    end)
end
