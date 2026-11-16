--[[

NestedRunTest.spec

Tests that plans run from inside running tests finish instead of waiting forever for
concurrency slots that their callers hold. Uses subprocess execution so a regression
shows up as a timed-out script instead of hanging the whole suite.

--]]

const Subprocess = require("./Helpers/Subprocess")
const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")

    Testable.configure({ MaxConcurrency = %d })

    task.delay(20, function()
        print("TIMED_OUT")
        process.exit(3)
    end)

    const function nestedRun()
        const results = Testable.TestRunner.runPlan(Testable.TestPlanner.createPlan({
            {
                method = function()
                    it("inner first", function()
                        task.wait()
                    end)
                    it("inner second", function() end)
                end,
                path = { "Inner" },
                pathStringForSorting = "inner",
            },
        }))
        assert(results.successCount == 2, "The nested run should pass both of its tests.")
    end

    const results, passed = Testable.run({
        {
            Name = "Outer",
            Func = function()
                for index = 1, %d do
                    it("outer " .. index, nestedRun)
                end
            end,
        },
    })
    print("PASSED:" .. tostring(passed))
    print("PASS_COUNT:" .. results.successCount)
    process.exit(if passed then 0 else 1)
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

return function()
    for _, case in
        { { Slots = 1, Tests = 1 }, { Slots = 1, Tests = 3 }, { Slots = 2, Tests = 6 }, { Slots = 4, Tests = 9 } }
    do
        const runs = if case.Tests == 1 then "1 nested run" else `{case.Tests} nested runs`
        const slots = if case.Slots == 1 then "1 concurrency slot" else `{case.Slots} concurrency slots`

        it(`should finish {runs} with {slots}`, function()
            const ok, output = Subprocess.runScript(string.format(SCRIPT_TEMPLATE, case.Slots, case.Tests))

            expect(contains(output, "TIMED_OUT")).to.equal(false)
            expect(ok).to.equal(true)
            expect(contains(output, "PASSED:true")).to.equal(true)
            expect(contains(output, `PASS_COUNT:{case.Tests}`)).to.equal(true)
        end)
    end
end
