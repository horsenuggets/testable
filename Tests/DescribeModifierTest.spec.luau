--[[

DescribeModifierTest.spec

Tests that focus and skip modifiers on describe blocks reach the tests inside them, on
their own and together with a filter. Uses subprocess execution so each case gets its own
Testable instance, and runs every case with both the parallel and sequential paths, since
parallel execution tracks each test's position in the tree separately.

--]]

const Subprocess = require("./Helpers/Subprocess")
const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
const SCRIPT_TEMPLATE = [[
    const Testable = require("./Source/Testable")

    Testable.configure({ Parallel = %s, Filter = %q })

    const results = Testable.run({
        {
            Name = "Suite",
            Func = function()
                %s
            end,
        },
    })
    print("PASS_COUNT:" .. results.successCount)
    print("SKIP_COUNT:" .. results.skippedCount)
    print("FILTERED_COUNT:" .. results.filteredCount)
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

return function()
    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            const function run(filter: string, moduleBody: string): string
                const _, output =
                    Subprocess.runScript(string.format(SCRIPT_TEMPLATE, tostring(mode.Parallel), filter, moduleBody))
                return output
            end

            it("should run only the tests inside a focused describe", function()
                const output = run(
                    "",
                    [[
                        fdescribe("focused", function()
                            it("first", function() print("RAN:focused first") end)

                            describe("nested", function()
                                it("second", function() print("RAN:nested second") end)
                            end)
                        end)

                        describe("plain", function()
                            it("third", function() print("RAN:plain third") end)
                        end)

                        it("fourth", function() print("RAN:fourth") end)
                    ]]
                )

                expect(contains(output, "RAN:focused first")).to.equal(true)
                expect(contains(output, "RAN:nested second")).to.equal(true)
                expect(contains(output, "RAN:plain third")).to.equal(false)
                expect(contains(output, "RAN:fourth")).to.equal(false)
                expect(contains(output, "PASS_COUNT:2")).to.equal(true)
                expect(contains(output, "SKIP_COUNT:2")).to.equal(true)
                expect(contains(output, "FILTERED_COUNT:0")).to.equal(true)
            end)

            it("should skip every test inside a skipped describe", function()
                const output = run(
                    "",
                    [[
                        xdescribe("skipped", function()
                            it("first", function() print("RAN:skipped first") end)

                            describe("nested", function()
                                it("second", function() print("RAN:nested second") end)
                                fit("third", function() print("RAN:nested third") end)
                            end)
                        end)

                        it("fourth", function() print("RAN:fourth") end)
                    ]]
                )

                expect(contains(output, "RAN:skipped first")).to.equal(false)
                expect(contains(output, "RAN:nested second")).to.equal(false)
                expect(contains(output, "RAN:nested third")).to.equal(true)
                expect(contains(output, "RAN:fourth")).to.equal(false)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "SKIP_COUNT:3")).to.equal(true)
            end)

            it("should skip a skipped describe when nothing is focused", function()
                const output = run(
                    "",
                    [[
                        xdescribe("skipped", function()
                            it("first", function() print("RAN:skipped first") end)
                        end)

                        it("second", function() print("RAN:second") end)
                    ]]
                )

                expect(contains(output, "RAN:skipped first")).to.equal(false)
                expect(contains(output, "RAN:second")).to.equal(true)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "SKIP_COUNT:1")).to.equal(true)
            end)

            it("should narrow by the filter before a focused describe applies", function()
                const output = run(
                    "keep",
                    [[
                        fdescribe("focused", function()
                            it("keep inside", function() print("RAN:keep inside") end)
                            it("drop inside", function() print("RAN:drop inside") end)
                        end)

                        it("keep outside", function() print("RAN:keep outside") end)
                    ]]
                )

                expect(contains(output, "RAN:keep inside")).to.equal(true)
                expect(contains(output, "RAN:drop inside")).to.equal(false)
                expect(contains(output, "RAN:keep outside")).to.equal(false)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "SKIP_COUNT:2")).to.equal(true)
                expect(contains(output, "FILTERED_COUNT:1")).to.equal(true)
            end)

            it("should ignore a focused describe whose tests were all filtered out", function()
                const output = run(
                    "keep",
                    [[
                        fdescribe("focused", function()
                            it("drop inside", function() print("RAN:drop inside") end)
                        end)

                        it("keep outside", function() print("RAN:keep outside") end)
                    ]]
                )

                expect(contains(output, "RAN:drop inside")).to.equal(false)
                expect(contains(output, "RAN:keep outside")).to.equal(true)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "FILTERED_COUNT:1")).to.equal(true)
            end)

            it("should only run the hooks of describes that the filter left tests in", function()
                const output = run(
                    "keep",
                    [[
                        describe("selected", function()
                            beforeAll(function() print("HOOK:selected beforeAll") end)
                            afterAll(function() print("HOOK:selected afterAll") end)
                            beforeEach(function() print("HOOK:selected beforeEach") end)

                            describe("nested", function()
                                beforeAll(function() print("HOOK:nested beforeAll") end)
                                it("keep inside", function() end)
                            end)

                            describe("emptied", function()
                                beforeAll(function() print("HOOK:emptied beforeAll") end)
                                afterAll(function() print("HOOK:emptied afterAll") end)
                                it("drop nested", function() end)
                            end)
                        end)

                        describe("unselected", function()
                            beforeAll(function() print("HOOK:unselected beforeAll") end)
                            afterAll(function() print("HOOK:unselected afterAll") end)
                            beforeEach(function() print("HOOK:unselected beforeEach") end)
                            it("drop inside", function() end)
                        end)
                    ]]
                )

                expect(contains(output, "HOOK:selected beforeAll")).to.equal(true)
                expect(contains(output, "HOOK:selected afterAll")).to.equal(true)
                expect(contains(output, "HOOK:selected beforeEach")).to.equal(true)
                expect(contains(output, "HOOK:nested beforeAll")).to.equal(true)
                expect(contains(output, "HOOK:emptied")).to.equal(false)
                expect(contains(output, "HOOK:unselected")).to.equal(false)
                expect(contains(output, "PASS_COUNT:1")).to.equal(true)
                expect(contains(output, "FILTERED_COUNT:2")).to.equal(true)
            end)

            it("should keep running the hooks of every describe when there is no filter", function()
                const output = run(
                    "",
                    [[
                        describe("skipped", function()
                            beforeAll(function() print("HOOK:skipped beforeAll") end)
                            afterAll(function() print("HOOK:skipped afterAll") end)
                            xit("waits", function() end)
                        end)

                        describe("plain", function()
                            beforeAll(function() print("HOOK:plain beforeAll") end)
                            it("runs", function() end)
                        end)
                    ]]
                )

                expect(contains(output, "HOOK:skipped beforeAll")).to.equal(true)
                expect(contains(output, "HOOK:skipped afterAll")).to.equal(true)
                expect(contains(output, "HOOK:plain beforeAll")).to.equal(true)
            end)
        end)
    end
end
