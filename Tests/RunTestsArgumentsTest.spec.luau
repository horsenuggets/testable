--[[

RunTestsArgumentsTest.spec

Tests for parsing the command-line arguments of the RunTests script, and for the exit
codes the script uses when the arguments or the git ref are invalid.

--]]

const RunTestsArguments = require("../Scripts/Helpers/RunTestsArguments")
const Testable = require("../Source/Testable")
const process = require("@lune/process")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const EXIT_CODE_TOOL_ERROR = 2

const function runScript(arguments: { string }): process.ExecResult
    const allArguments = { "run", "Scripts/RunTests.exec.luau" }
    for _, argument in arguments do
        table.insert(allArguments, argument)
    end
    return process.exec("lune", allArguments, { cwd = process.cwd })
end

return function()
    describe("RunTestsArguments.parse()", function()
        it("should default to running everything", function()
            const parsed = RunTestsArguments.parse({}) :: RunTestsArguments.Arguments
            expect(parsed.Changed).to.equal(nil)
            expect(parsed.Watch).to.equal(false)
            expect(#parsed.Files).to.equal(0)
        end)

        it("should read the ref that follows the changed flag", function()
            const parsed = RunTestsArguments.parse({ "--changed", "origin/main" }) :: RunTestsArguments.Arguments
            expect(parsed.Changed).to.equal("origin/main")
            expect(#parsed.Files).to.equal(0)
        end)

        it("should read the watch flag", function()
            const parsed = RunTestsArguments.parse({ "--watch" }) :: RunTestsArguments.Arguments
            expect(parsed.Watch).to.equal(true)
        end)

        it("should collect spec files in order", function()
            const parsed = RunTestsArguments.parse({ "Tests/B.spec.luau", "--watch", "Tests/A.spec.luau" })
            expect(table.concat((parsed :: RunTestsArguments.Arguments).Files, ",")).to.equal(
                "Tests/B.spec.luau,Tests/A.spec.luau"
            )
        end)

        it("should reject a changed flag without a ref", function()
            for _, arguments in { { "--changed" }, { "--changed", "--watch" } } do
                const parsed, message = RunTestsArguments.parse(arguments)
                expect(parsed).to.equal(nil)
                expect(string.find(message :: string, "needs a git ref", 1, true)).to.be.ok()
            end
        end)

        it("should reject watching together with a changed ref in either order", function()
            for _, arguments in { { "--watch", "--changed", "HEAD" }, { "--changed", "HEAD", "--watch" } } do
                const parsed, message = RunTestsArguments.parse(arguments)
                expect(parsed).to.equal(nil)
                expect(string.find(message :: string, "can't be combined", 1, true)).to.be.ok()
            end
        end)

        it("should reject spec files together with a changed ref", function()
            const parsed, message = RunTestsArguments.parse({ "--changed", "HEAD", "Tests/A.spec.luau" })
            expect(parsed).to.equal(nil)
            expect(string.find(message :: string, "can't be combined with spec files", 1, true)).to.be.ok()
        end)

        it("should reject flags it does not know", function()
            const parsed, message = RunTestsArguments.parse({ "--unknown" })
            expect(parsed).to.equal(nil)
            expect(string.find(message :: string, '"--unknown" is not recognized', 1, true)).to.be.ok()
        end)
    end)

    describe("RunTestsArguments.without()", function()
        it("should keep the arguments that another parser consumed", function()
            const arguments = { "--reporter", "json", "--watch", "--output", "out.json", "Tests/A.spec.luau" }
            const kept = RunTestsArguments.without(arguments, { "--watch", "Tests/A.spec.luau" })
            expect(table.concat(kept, " ")).to.equal("--reporter json --output out.json")
        end)

        it("should only remove one occurrence for each removed argument", function()
            const kept = RunTestsArguments.without({ "a", "b", "a", "c" }, { "a" })
            expect(table.concat(kept, " ")).to.equal("b a c")
        end)

        it("should return everything when nothing is removed and nothing when all is", function()
            expect(table.concat(RunTestsArguments.without({ "a", "b" }, {}), " ")).to.equal("a b")
            expect(#RunTestsArguments.without({ "a", "b" }, { "a", "b" })).to.equal(0)
        end)
    end)

    describe("RunTests.exec", function()
        it("should exit with a tool error for an invalid reporter flag", function()
            const result = runScript({ "--reporter", "unknown" })
            expect(result.code).to.equal(EXIT_CODE_TOOL_ERROR)
            expect(string.find(result.stdout, '"--reporter" flag needs', 1, true)).to.be.ok()
        end)

        it("should accept reporter flags together with spec files", function()
            const result = runScript({ "--slowest", "1", "Tests/ExampleTest.spec.luau" })
            expect(result.code).to.equal(0)
            expect(string.find(result.stdout, "ExampleTest", 1, true)).to.be.ok()
        end)

        it("should print the usage and exit with a tool error for invalid arguments", function()
            const result = runScript({ "--watch", "--changed", "HEAD" })
            expect(result.code).to.equal(EXIT_CODE_TOOL_ERROR)
            expect(string.find(result.stdout, "[Usage] ./Scripts/RunTests.exec.luau", 1, true)).to.be.ok()
        end)

        it("should exit with a tool error for a git ref that does not exist", function()
            const result = runScript({ "--changed", "this-ref-does-not-exist" })
            expect(result.code).to.equal(EXIT_CODE_TOOL_ERROR)
            expect(string.find(result.stdout, '"this-ref-does-not-exist" is not a valid git ref', 1, true)).to.be.ok()
        end)

        it("should exit with a tool error for a spec file that does not exist", function()
            const result = runScript({ "Tests/DoesNotExist.spec.luau" })
            expect(result.code).to.equal(EXIT_CODE_TOOL_ERROR)
            expect(string.find(result.stdout, "is not a spec file matched by", 1, true)).to.be.ok()
        end)

        it("should run only the spec file it is given", function()
            const result = runScript({ "Tests/ExampleTest.spec.luau" })
            expect(result.code).to.equal(0)
            expect(string.find(result.stdout, "ExampleTest", 1, true)).to.be.ok()
            expect(string.find(result.stdout, "ConfigTest", 1, true)).to.equal(nil)
        end)
    end)
end
