--[[

SlowestTestsTest.spec

Tests for the durations recorded on result nodes and for the "slowest tests" block that
the text reporter builds from them.

--]]

const Ansi = require("../Source/Testable/Ansi")
const ResultFixture = require("./Helpers/ResultFixture")
const ResultTree = require("../Source/Testable/Reporters/ResultTree")
const Subprocess = require("./Helpers/Subprocess")
const TestEnum = require("../Source/Testable/TestEnum")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")
const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
const FAILURE = TestEnum.TestStatus.Failure
const SKIPPED = TestEnum.TestStatus.Skipped
const SUCCESS = TestEnum.TestStatus.Success
const RUN_TEMPLATE = [[
    const process = require("@lune/process")
    const task = require("@lune/task")
    const Testable = require("./Source/Testable")

    Testable.configure({ Parallel = %s, SlowestTests = %d })

    const results = Testable.run({
        {
            Name = "TimingSpec",
            Func = function()
                describe("group", function()
                    it("slow", function()
                        task.wait(0.15)
                    end)
                    it("fast", function() end)
                    it("slow failure", function()
                        task.wait(0.05)
                        error("deliberate failure")
                    end)
                    xit("skipped", function() end)
                end)
            end,
        },
    })

    const function show(node, depth)
        print(`NODE|{depth}|{node.planNode.phrase}|{tostring(node.status)}|{tostring(node.duration)}`)
        for _, child in node.children do
            show(child, depth + 1)
        end
    end
    print(`ROOT|{tostring(results.duration)}`)
    for _, child in results.children do
        show(child, 0)
    end
    process.exit(0)
]]

const function timed(durations: { number }): any
    const tests = {}
    for index, duration in durations do
        table.insert(tests, ResultFixture.it(`test {index}`, SUCCESS, { Duration = duration }))
    end
    return ResultFixture.results({ ResultFixture.describe("Spec", SUCCESS, tests) })
end

--[[
    Reads the durations a subprocess run printed, keyed by phrase. Skipped nodes print
    "nil" and come back as false.
]]
const function readDurations(output: string): ({ [string]: number | boolean }, number?)
    const durations: { [string]: number | boolean } = {}
    for phrase, duration in output:gmatch("NODE|%d+|([^|]*)|[^|]*|([^\n]*)") do
        durations[phrase] = tonumber(duration) or false
    end
    return durations, tonumber(output:match("ROOT|([^\n]*)"))
end

return function()
    describe("TextReporter.formatSlowest", function()
        it("should list the slowest tests first with their full names", function()
            const lines = TextReporter.formatSlowest(timed({ 0.25, 1.5, 0.5 }), 2, false)
            expect(table.concat(lines, "\n")).to.equal(table.concat({
                "",
                "Slowest Tests",
                "",
                "1.500s  Spec > test 2",
                "0.500s  Spec > test 3",
            }, "\n"))
        end)

        it("should list every test when fewer ran than were asked for", function()
            const lines = TextReporter.formatSlowest(timed({ 0.25, 0.5 }), 10, false)
            expect(#lines).to.equal(5)
        end)

        it("should be empty at zero and when no test ran", function()
            expect(#TextReporter.formatSlowest(timed({ 0.25, 0.5 }), 0, false)).to.equal(0)
            expect(#TextReporter.formatSlowest(ResultFixture.results({}), 5, false)).to.equal(0)
            const skipped = ResultFixture.results({
                ResultFixture.describe("Spec", SKIPPED, { ResultFixture.it("waits", SKIPPED) }),
            })
            expect(#TextReporter.formatSlowest(skipped, 5, false)).to.equal(0)
        end)

        it("should include failed tests and leave skipped tests out", function()
            const text = table.concat(TextReporter.formatSlowest(ResultFixture.mixed(), 10, false), "\n")
            expect(text:find("MathTest > division > divides", 1, true) ~= nil).to.equal(true)
            expect(text:find("MathTest > adds", 1, true) ~= nil).to.equal(true)
            expect(text:find("rounds", 1, true)).to.equal(nil)
            expect(text:find("waits", 1, true)).to.equal(nil)
        end)

        it("should keep definition order between tests that took equally long", function()
            const lines = TextReporter.formatSlowest(timed({ 0.5, 0.5, 0.5, 1 }), 4, false)
            expect(lines[4]).to.equal("1.000s  Spec > test 4")
            expect(lines[5]).to.equal("0.500s  Spec > test 1")
            expect(lines[6]).to.equal("0.500s  Spec > test 2")
            expect(lines[7]).to.equal("0.500s  Spec > test 3")
        end)

        it("should right-align durations of different widths", function()
            const lines = TextReporter.formatSlowest(timed({ 12.5, 0.25 }), 2, false)
            expect(lines[4]).to.equal("12.500s  Spec > test 1")
            expect(lines[5]).to.equal(" 0.250s  Spec > test 2")
        end)

        it("should only add styling when color is on", function()
            const results = timed({ 0.25, 0.5 })
            const plain = TextReporter.formatSlowest(results, 2, false)
            const colored = TextReporter.formatSlowest(results, 2, true)
            expect(#colored).to.equal(#plain)
            expect(colored[2]).to.equal(Ansi.bold("Slowest Tests"))
            for index, line in colored do
                expect((line:gsub("\27%[[%d;]*m", ""))).to.equal(plain[index])
            end
            expect(table.concat(plain):find("\27", 1, true)).to.equal(nil)
        end)

        it("should reject counts that aren't whole numbers", function()
            for _, count in { -1, 1.5 } do
                expect(function()
                    TextReporter.formatSlowest(timed({ 1 }), count, false)
                end).to.throw()
            end
        end)
    end)

    describe("ResultTree", function()
        it("should flatten the tree into cases in definition order", function()
            const cases = ResultTree.collectCases(ResultFixture.mixed())
            const names = {}
            for _, case in cases do
                table.insert(names, `{case.FullName}={case.Status}`)
            end
            expect(table.concat(names, "\n")).to.equal(table.concat({
                `MathTest > adds={SUCCESS}`,
                `MathTest > division > divides={FAILURE}`,
                `MathTest > division > rounds={SKIPPED}`,
                `BrokenTest={FAILURE}`,
                `SkippedTest > waits={SKIPPED}`,
            }, "\n"))
            expect(table.concat(cases[2].Path, "/")).to.equal("MathTest/division")
        end)

        it("should not count a describe block as a case unless planning failed", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", FAILURE, {}, { Errors = { "hook failed" } }),
                ResultFixture.describe("Skipped", SKIPPED, {}, { LoadError = "boom" }),
            })
            expect(#ResultTree.collectCases(results)).to.equal(0)
        end)

        it("should take a missing status from descendants", function()
            const failing = ResultFixture.describe("Spec", nil, {
                ResultFixture.it("a", SUCCESS),
                ResultFixture.describe("inner", nil, { ResultFixture.it("b", FAILURE) }),
            })
            expect(ResultTree.status(failing)).to.equal(FAILURE)
            const passing = ResultFixture.describe("Spec", nil, {
                ResultFixture.it("a", SKIPPED),
                ResultFixture.it("b", SUCCESS),
            })
            expect(ResultTree.status(passing)).to.equal(SUCCESS)
            expect(ResultTree.status(ResultFixture.describe("Spec", nil, {}))).to.equal(nil)
        end)

        it("should format seconds as plain decimals", function()
            expect(ResultTree.formatSeconds(1.5)).to.equal("1.500000")
            expect(ResultTree.formatSeconds(0.0000004)).to.equal("0.000000")
            expect(ResultTree.formatSeconds(1e-5)).to.equal("0.000010")
            expect(ResultTree.formatSeconds(-3)).to.equal("0.000000")
            expect(ResultTree.formatSeconds(math.huge)).to.equal("0.000000")
        end)

        it("should leave clean text alone when sanitizing", function()
            expect(ResultTree.sanitize("plain ✓ text\n")).to.equal("plain ✓ text\n")
            expect(ResultTree.sanitize("")).to.equal("")
            expect(ResultTree.sanitize("\255")).to.equal("\u{FFFD}")
            expect(ResultTree.sanitize("a\255\254b")).to.equal("a\u{FFFD}\u{FFFD}b")
        end)
    end)

    for _, mode in EXECUTION_MODES do
        describe(`recorded durations with {mode.Name} execution`, function()
            it("should record how long each test and block took", function()
                const _, output = Subprocess.runScript(string.format(RUN_TEMPLATE, tostring(mode.Parallel), 0))
                const durations, total = readDurations(output)
                const slow = durations["slow"] :: number
                const fast = durations["fast"] :: number
                const slowFailure = durations["slow failure"] :: number
                const group = durations["group"] :: number
                const spec = durations["TimingSpec"] :: number

                expect(slow >= 0.15).to.equal(true)
                expect(slowFailure >= 0.05).to.equal(true)
                expect(fast >= 0 and fast < slow).to.equal(true)
                expect(durations["skipped"]).to.equal(false)
                expect(group >= slow).to.equal(true)
                expect(spec >= group).to.equal(true)
                expect((total :: number) >= spec).to.equal(true)
                expect(output:find("Slowest Tests", 1, true)).to.equal(nil)
            end)

            it("should print the slowest tests block when configured", function()
                const _, output = Subprocess.runScript(string.format(RUN_TEMPLATE, tostring(mode.Parallel), 2))
                const plain = output:gsub("\27%[[%d;]*m", "")
                const heading = plain:find("Slowest Tests", 1, true)
                const slow = plain:find("s  TimingSpec > group > slow\n", 1, true)
                const slowFailure = plain:find("s  TimingSpec > group > slow failure\n", 1, true)
                expect(heading ~= nil and slow ~= nil and slowFailure ~= nil).to.equal(true)
                expect((heading :: number) < (slow :: number)).to.equal(true)
                expect((slow :: number) < (slowFailure :: number)).to.equal(true)
                expect(plain:find("s  TimingSpec > group > fast\n", 1, true)).to.equal(nil)
            end)
        end)
    end
end
