--[[

ParallelHooksTest.spec

Pins that lifecycle hooks stay with their own module when several modules run at once.
Each module's beforeAll yields for a different time so the modules interleave, and every
afterAll checks that it sees only its own setup. Runs in a subprocess so each case gets
its own Testable instance, in both the parallel and sequential describe paths.

--]]

const Subprocess = require("./Helpers/Subprocess")

const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")

    Testable.configure({ Parallel = %s })

    const order = {}

    const function module(name: string, delay: number)
        return function()
            local setup = nil
            local eachCount = 0

            beforeAll(function()
                task.wait(delay)
                setup = name
            end)

            beforeEach(function()
                eachCount += 1
            end)

            afterAll(function()
                table.insert(order, name)
                expect(setup).to.equal(name)
                expect(eachCount).to.equal(2)
            end)

            it("sees its own setup", function()
                task.wait(delay / 2)
                expect(setup).to.equal(name)
            end)

            it("still sees its own setup", function()
                expect(setup).to.equal(name)
            end)
        end
    end

    const tests = {
        { Name = "Slow", Func = module("Slow", 0.15) },
        { Name = "Medium", Func = module("Medium", 0.08) },
        { Name = "Fast", Func = module("Fast", 0.01) },
    }

    const results, passed = Testable.run(tests)
    print("PASSED:" .. tostring(passed))
    print("FAIL_COUNT:" .. results.failureCount)
    print("AFTER_ALL:" .. table.concat(order, ","))
    process.exit(if passed then 0 else 1)
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

return function()
    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            it("runs each module's hooks with its own state after its tests finish", function()
                const ok, output = Subprocess.runScript(string.format(SCRIPT_TEMPLATE, tostring(mode.Parallel)))

                expect(contains(output, "FAIL_COUNT:0")).to.equal(true)
                expect(contains(output, "PASSED:true")).to.equal(true)
                expect(ok).to.equal(true)
                const afterAll = string.match(output, "AFTER_ALL:([%w,]+)") :: string
                expect(afterAll).never.to.equal(nil)
                const ran = string.split(afterAll, ",")
                table.sort(ran)
                expect(table.concat(ran, ",")).to.equal("Fast,Medium,Slow")
            end)
        end)
    end
end
