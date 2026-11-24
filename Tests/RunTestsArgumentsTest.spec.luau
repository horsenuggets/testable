--[[

RunTestsArgumentsTest.spec

Tests for parsing the command-line arguments of the RunTests script, and for the exit
codes the script uses when the arguments or the git ref are invalid.

--]]

const FilterArguments = require("../Scripts/Helpers/FilterArguments")
const ReporterArguments = require("../Scripts/Helpers/ReporterArguments")
const RunTestsArguments = require("../Scripts/Helpers/RunTestsArguments")
const SnapshotArguments = require("../Scripts/Helpers/SnapshotArguments")
const TempDirectory = require("./Helpers/TempDirectory")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const luau = require("@lune/luau")
const process = require("@lune/process")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const EXIT_CODE_TOOL_ERROR = 2
const SETUP_MODULE = [[
    const fs = require("@lune/fs")
    return function(Testable, context)
        assert(type(Testable.configure) == "function")
        assert(type(context.Root) == "string")
        assert(context.JobId == 1)
        assert(#context.Files == 1)
        fs.writeFile(`{context.Root}/Prepared.txt`, "ready")
    end
]]
const SETUP_SPEC = [[
    const fs = require("@lune/fs")
    const prepared = fs.readFile("Prepared.txt")
    return function()
        it("runs after setup", function()
            expect(prepared).to.equal("ready")
        end)
    end
]]

const function runScript(arguments: { string }, root: string?): process.ExecResult
    const scriptPath = if root == nil
        then "Scripts/RunTests.exec.luau"
        else Testable.Discovery.PathUtil.join(process.cwd, "Scripts/RunTests.exec.luau")
    const allArguments = { "run", scriptPath }
    for _, argument in arguments do
        table.insert(allArguments, argument)
    end
    return process.exec("lune", allArguments, { cwd = root or process.cwd })
end

return function()
    describe("RunTestsArguments.parse()", function()
        it("should default to running everything", function()
            const parsed = RunTestsArguments.parse({}) :: RunTestsArguments.Arguments
            expect(parsed.Changed).to.equal(nil)
            expect(parsed.Watch).to.equal(false)
            expect(parsed.WorkerSetup).to.equal(nil)
            expect(parsed.Workers).to.equal(nil)
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

        it("should combine worker flags with files, watch mode, or a changed ref", function()
            for _, mode in { {}, { "--watch" }, { "--changed", "HEAD" }, { "Tests/A.spec.luau" } } do
                for _, workers in { 1, 2, 8 } do
                    const arguments = { "--worker-setup", "Tests/Setup.luau" }
                    for _, argument in mode do
                        table.insert(arguments, argument)
                    end
                    table.insert(arguments, "--workers")
                    table.insert(arguments, tostring(workers))
                    const parsed = RunTestsArguments.parse(arguments) :: RunTestsArguments.Arguments
                    expect(parsed.WorkerSetup).to.equal("Tests/Setup.luau")
                    expect(parsed.Workers).to.equal(workers)
                    expect(parsed.Watch).to.equal(mode[1] == "--watch")
                    expect(parsed.Changed).to.equal(if mode[1] == "--changed" then "HEAD" else nil)
                    expect(parsed.Files).to.deepEqual(if mode[1] == "Tests/A.spec.luau" then mode else {})
                end
            end
        end)

        it("should reject invalid, missing, or colliding worker counts", function()
            for _, arguments in
                {
                    { "--workers" },
                    { "--workers", "--watch" },
                    { "--workers", "--worker-setup", "Setup.luau" },
                    { "--workers", "" },
                    { "--workers", " " },
                    { "--workers", "two" },
                    { "--workers", "0" },
                    { "--workers", "-1" },
                    { "--workers", "1.5" },
                    { "--workers", "nan" },
                    { "--workers", "inf" },
                    { "--workers", "1e999" },
                }
            do
                const parsed, message = RunTestsArguments.parse(arguments)
                expect(parsed).to.equal(nil)
                expect(message).to.contain('"--workers" flag needs a finite positive integer')
            end
        end)

        it("should reject missing, blank, or colliding worker setup paths", function()
            for _, arguments in
                {
                    { "--worker-setup" },
                    { "--worker-setup", "" },
                    { "--worker-setup", " \t\n" },
                    { "--worker-setup", "--workers", "2" },
                    { "--worker-setup", "--changed", "HEAD" },
                    { "--worker-setup", "--watch" },
                    { "--worker-setup", "--filter", "text" },
                    { "--worker-setup", "--reporter", "json" },
                    { "--worker-setup", "--update-snapshots" },
                }
            do
                const parsed, message = RunTestsArguments.parse(arguments)
                expect(parsed).to.equal(nil)
                expect(message).to.contain('"--worker-setup" flag needs a nonblank module path')
            end
        end)

        it("should reject repeated worker flags instead of silently overriding them", function()
            for _, arguments in
                {
                    { "--workers", "1", "--workers", "2" },
                    { "--worker-setup", "A.luau", "--worker-setup", "B.luau" },
                }
            do
                const parsed, message = RunTestsArguments.parse(arguments)
                expect(parsed).to.equal(nil)
                expect(message).to.contain("can only be given once")
            end
        end)

        it("should retain watch and changed collision errors with worker flags", function()
            for _, mode in
                {
                    { "--watch", "--changed", "HEAD" },
                    { "--changed", "HEAD", "Tests/A.spec.luau" },
                }
            do
                const arguments = { "--workers", "2", "--worker-setup", "Setup.luau" }
                for _, argument in mode do
                    table.insert(arguments, argument)
                end
                const parsed, message = RunTestsArguments.parse(arguments)
                expect(parsed).to.equal(nil)
                expect(message).to.contain("can't be combined")
            end
        end)

        it("should reject flags it does not know", function()
            const parsed, message = RunTestsArguments.parse({ "--unknown" })
            expect(parsed).to.equal(nil)
            expect(string.find(message :: string, '"--unknown" is not recognized', 1, true)).to.be.ok()
        end)
    end)

    describe("RunTestsArguments.extractWorkers()", function()
        it("should preserve flags and operands owned by other parsers", function()
            const raw = {
                "--reporter",
                "json",
                "--output",
                "--workers",
                "--filter=--worker-setup",
                "--workers",
                "3",
                "Tests/A.spec.luau",
            }
            const workers, unparsed = RunTestsArguments.extractWorkers(raw)
            expect((workers :: RunTestsArguments.WorkerOptions).Workers).to.equal(3)
            const reporters, afterReporters = ReporterArguments.parse(unparsed)
            const filters, afterFilter = FilterArguments.parse(afterReporters)
            const _, remaining = SnapshotArguments.parse(afterFilter)
            const parsed = RunTestsArguments.parse(remaining) :: RunTestsArguments.Arguments
            expect(reporters.ReporterOutputs.Json).to.equal("--workers")
            expect(filters.Filter).to.equal("--worker-setup")
            expect(parsed.Files).to.deepEqual({ "Tests/A.spec.luau" })
        end)

        it("should forward worker, reporter, filter, and snapshot flags to watch children", function()
            const raw = {
                "--workers",
                "2",
                "--watch",
                "--reporter",
                "json",
                "--output",
                "out.json",
                "--worker-setup",
                "Setup.luau",
                "--filter",
                "example",
                "-u",
                "Tests/A.spec.luau",
            }
            const _, unparsed = RunTestsArguments.extractWorkers(raw)
            const _, afterReporters = ReporterArguments.parse(unparsed)
            const _, afterFilter = FilterArguments.parse(afterReporters)
            const _, remaining = SnapshotArguments.parse(afterFilter)
            expect(RunTestsArguments.without(raw, remaining)).to.deepEqual({
                "--workers",
                "2",
                "--reporter",
                "json",
                "--output",
                "out.json",
                "--worker-setup",
                "Setup.luau",
                "--filter",
                "example",
                "-u",
            })
            const parsed = RunTestsArguments.parse(remaining) :: RunTestsArguments.Arguments
            expect(parsed.Watch).to.equal(true)
            expect(parsed.Files).to.deepEqual({ "Tests/A.spec.luau" })
        end)

        it("should not strip a worker flag out of a changed flag's missing value", function()
            const parsed, message = RunTestsArguments.parse({ "--changed", "--workers", "2" })
            expect(parsed).to.equal(nil)
            expect(message).to.contain("needs a git ref")
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
        it("should give the watch graph parsed setup options before configuring a run", function()
            const source = string.gsub(fs.readFile("Scripts/RunTests.exec.luau"), "^#![^\n]*\n", "")
            for _, setup in { "Setup.luau", "./Setup", "Bootstrap/init.luau" } do
                local watchOptions: any = nil
                local childOptions: any = nil
                const dependencies: { [string]: any } = {
                    ["./Helpers/FilterArguments"] = FilterArguments,
                    ["./Helpers/ReporterArguments"] = ReporterArguments,
                    ["./Helpers/RunTestsArguments"] = RunTestsArguments,
                    ["./Helpers/SnapshotArguments"] = SnapshotArguments,
                    ["../Source/Testable"] = {
                        Discovery = {
                            runInChild = function(options)
                                childOptions = options
                            end,
                            watch = function(options)
                                watchOptions = options
                                options.Run({ "Tests/A.spec.luau" })
                            end,
                        },
                        configure = function()
                            error("Watch must receive setup before configuring the run.")
                        end,
                    },
                    ["@lune/process"] = {
                        args = { "--watch", "--workers", "2", "--worker-setup", setup, "Tests/A.spec.luau" },
                    },
                }
                const chunk = luau.load(source, {
                    environment = {
                        require = function(path: string)
                            assert(dependencies[path] ~= nil, `Unexpected CLI dependency "{path}".`)
                            return dependencies[path]
                        end,
                    },
                })
                chunk()
                expect(watchOptions.WorkerSetup).to.equal(setup)
                expect(watchOptions.Include).to.deepEqual({ "Tests/A.spec.luau" })
                expect(childOptions.Arguments).to.deepEqual({ "--workers", "2", "--worker-setup", setup })
                expect(childOptions.Files).to.deepEqual({ "Tests/A.spec.luau" })
            end
        end)

        it("should exit with a tool error for an invalid reporter flag", function()
            const result = runScript({ "--reporter", "unknown" })
            expect(result.code).to.equal(EXIT_CODE_TOOL_ERROR)
            expect(string.find(result.stdout, '"--reporter" flag needs', 1, true)).to.be.ok()
        end)

        it("should reject worker flag collisions before other parsers consume them", function()
            for _, arguments in
                {
                    { "--workers", "--reporter", "json", "Tests/ExampleTest.spec.luau" },
                    { "--worker-setup", "--filter", "example", "Tests/ExampleTest.spec.luau" },
                    { "--worker-setup", "--reporter", "json", "Tests/ExampleTest.spec.luau" },
                    { "--worker-setup", "--update-snapshots", "Tests/ExampleTest.spec.luau" },
                    { "--workers" },
                    { "--worker-setup" },
                }
            do
                const result = runScript(arguments)
                expect(result.code).to.equal(EXIT_CODE_TOOL_ERROR)
                expect(result.stdout).to.contain("[Usage]")
                expect(result.stdout).to.contain("flag needs a")
            end
        end)

        it("should accept worker counts through the file-oriented CLI", function()
            for _, workers in { "1", "2" } do
                const result = runScript({ "--workers", workers, "Tests/ExampleTest.spec.luau" })
                expect(result.code).to.equal(0)
                expect(result.stdout).to.contain("ExampleTest")
                expect(result.stdout).never.to.contain("ConfigTest")
            end
        end)

        it("should run setup before spec requires in both local and actor modes", function()
            const root = TempDirectory.create("cli_worker_setup")
            const ok, problem = pcall(function()
                TempDirectory.write(root, "rokit.toml", fs.readFile("rokit.toml"))
                TempDirectory.write(root, "Setup.luau", SETUP_MODULE)
                TempDirectory.write(root, "Tests/Prepared.spec.luau", SETUP_SPEC)
                for _, workers in { "1", "2" } do
                    const result = runScript({
                        "--workers",
                        workers,
                        "--worker-setup",
                        "./Setup.luau",
                        "Tests/Prepared.spec.luau",
                    }, root)
                    assert(result.ok, `The CLI failed with {workers} workers. {result.stdout}\n{result.stderr}`)
                    expect(result.code).to.equal(0)
                    expect(result.stdout).to.contain("runs after setup")
                    expect(fs.readFile(`{root}/Prepared.txt`)).to.equal("ready")
                    fs.removeFile(`{root}/Prepared.txt`)
                end
            end)
            TempDirectory.remove(root)
            if not ok then
                error(problem, 0)
            end
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
