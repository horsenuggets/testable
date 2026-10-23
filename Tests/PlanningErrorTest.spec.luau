--[[

PlanningErrorTest.spec

Tests that errors thrown while planning a test module fail the run. Uses subprocess
execution so each case gets its own Testable instance, then checks the exit code, the
reported failure count, and the summary line. Every case runs with both the parallel and
sequential describe paths.

--]]

local Subprocess = require("./Helpers/Subprocess")

local EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
local SCRIPT_TEMPLATE = [[
    local process = require("@lune/process")
    local Testable = require("./Source/Testable")

    Testable.configure({ Parallel = %s })

    local tests = {
        {
            Name = "PlanningModule",
            Func = function()
                %s
            end,
        },
    }

    local results, passed = Testable.run(tests)
    print("PASSED:" .. tostring(passed))
    print("PASS_COUNT:" .. results.successCount)
    print("FAIL_COUNT:" .. results.failureCount)
    process.exit(if passed then 0 else 1)
]]

--[[
    Builds a script that runs a single test module with the given body and prints its
    results in a parseable form.

    @param moduleBody - The Luau source of the test module function's body
    @param parallel - Whether to run the module with parallel execution enabled
    @return The full script source
]]
local function buildScript(moduleBody: string, parallel: boolean): string
    return string.format(SCRIPT_TEMPLATE, tostring(parallel), moduleBody)
end

local function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

return function()
    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            it("should fail the run when a root module errors during planning", function()
                local ok, output = Subprocess.runScript(buildScript(
                    [[
                        error("root planning failure")
                    ]],
                    mode.Parallel
                ))

                expect(ok).to.equal(false)
                expect(contains(output, "PASSED:false")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:1")).to.equal(true)
                expect(contains(output, "1 failed")).to.equal(true)
                expect(contains(output, "Error during planning")).to.equal(true)
                expect(contains(output, "root planning failure")).to.equal(true)
            end)

            it("should fail the run when a nested describe errors during planning", function()
                local ok, output = Subprocess.runScript(buildScript(
                    [[
                        describe("outer", function()
                            it("passes", function() end)

                            describe("inner", function()
                                error("nested planning failure")
                            end)
                        end)
                    ]],
                    mode.Parallel
                ))

                expect(ok).to.equal(false)
                expect(contains(output, "PASSED:false")).to.equal(true)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:1")).to.equal(true)
                expect(contains(output, "1 failed")).to.equal(true)
                expect(contains(output, "nested planning failure")).to.equal(true)
            end)

            it("should count a partially planned describe once alongside its tests", function()
                local ok, output = Subprocess.runScript(buildScript(
                    [[
                        describe("partial", function()
                            it("passes", function() end)
                            it("fails", function()
                                error("test failure")
                            end)
                            error("partial planning failure")
                        end)
                    ]],
                    mode.Parallel
                ))

                expect(ok).to.equal(false)
                expect(contains(output, "PASSED:false")).to.equal(true)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:2")).to.equal(true)
            end)

            it("should pass the run when a module plans without errors", function()
                local ok, output = Subprocess.runScript(buildScript(
                    [[
                        describe("healthy", function()
                            it("passes", function() end)

                            describe("nested", function()
                                it("also passes", function() end)
                            end)
                        end)
                    ]],
                    mode.Parallel
                ))

                expect(ok).to.equal(true)
                expect(contains(output, "PASSED:true")).to.equal(true)
                expect(contains(output, "PASS_COUNT:2")).to.equal(true)
                expect(contains(output, "FAIL_COUNT:0")).to.equal(true)
                expect(contains(output, "Error during planning")).to.equal(false)
            end)
        end)
    end
end
