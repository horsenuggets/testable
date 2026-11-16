--[[

NestedRunTest.spec

Pins that a test can start a run of its own without deadlocking. A test holds one of the
run's concurrency slots while it executes, so nested runs must not compete with the tests
that are waiting on them for the same slots. Runs in a subprocess with a watchdog, so a
regression fails this spec instead of hanging the whole suite.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const expect, it = Testable.expect, Testable.it

const CASES = {
    { MaxConcurrency = 1, Name = "one nesting test and one slot", Tests = 1 },
    { MaxConcurrency = 4, Name = "as many nesting tests as slots", Tests = 4 },
    { MaxConcurrency = 2, Name = "more nesting tests than slots", Tests = 5 },
}
const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")

    Testable.configure({ MaxConcurrency = %d, Parallel = true })

    task.delay(10, function()
        print("DEADLOCK")
        process.exit(2)
    end)

    local nestedRan = 0

    const function nestedRun()
        const _, nestedPassed = Testable.run({
            Nested = function()
                describe("nested", function()
                    it("yields and passes", function()
                        task.wait(0.01)
                        nestedRan += 1
                    end)

                    it("runs a run of its own", function()
                        const _, innermostPassed = Testable.run({
                            Innermost = function()
                                it("passes", function()
                                    nestedRan += 1
                                end)
                            end,
                        })
                        expect(innermostPassed).to.equal(true)
                    end)
                end)
            end,
        })
        expect(nestedPassed).to.equal(true)
    end

    const results, passed = Testable.run({
        Outer = function()
            describe("outer", function()
                for index = 1, %d do
                    it("starts nested run " .. index, nestedRun)
                end
            end)
        end,
    })

    print("PASSED:" .. tostring(passed))
    print("PASS_COUNT:" .. results.successCount)
    print("NESTED_RAN:" .. nestedRan)
    process.exit(if passed then 0 else 1)
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

return function()
    for _, case in CASES do
        it(`should finish with {case.Name}`, function()
            const ok, output = Subprocess.runScript(string.format(SCRIPT_TEMPLATE, case.MaxConcurrency, case.Tests))

            expect(contains(output, "DEADLOCK")).to.equal(false)
            expect(contains(output, "PASSED:true")).to.equal(true)
            expect(contains(output, `PASS_COUNT:{case.Tests}`)).to.equal(true)
            expect(contains(output, `NESTED_RAN:{case.Tests * 2}`)).to.equal(true)
            expect(ok).to.equal(true)
        end)
    end
end
