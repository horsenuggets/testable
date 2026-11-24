--[[

LogTest.spec

Verifies native verbose delivery in isolated runs without replacing global print or
intercepting final reports. Async completion and config mutation exercise run snapshots.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const expect, it = Testable.expect, Testable.it
const PRELUDE = [[
    const Testable = require("./Source/Testable")
    const task = require("@lune/task")
    const messages = {}
    const originalPrint = print
    const function record(message)
        assert(type(message) == "string")
        table.insert(messages, message)
    end
    const function position(text)
        for index, message in ipairs(messages) do
            if string.find(message, text, 1, true) then return index end
        end
        error(`Missing message "{text}".`, 0)
    end
    Testable.configure({ Log = record, Reporters = {}, Verbose = true })
]]

const function run(source: string): (string, string)
    const ok, output, errors = Subprocess.runScriptStreams(PRELUDE .. source)
    assert(ok, output .. errors)
    return output, errors
end

return function()
    it("validates Log atomically, retains omitted values, and clears it on reset", function()
        run([[
            assert(Testable.Config.Log == record)
            Testable.configure({ Parallel = false, Log = nil })
            assert(Testable.Config.Log == record)
            for _, value in { false, true, 1, "sink", {}, setmetatable({}, { __call = record }) } do
                const ok, problem = pcall(Testable.configure, { Indent = ">", Log = value })
                assert(not ok and Testable.ToolError.is(problem) and problem.Kind == "InvalidConfiguration")
                assert(string.find(problem.Message, "Log must be a function", 1, true))
                assert(Testable.Config.Indent == "   " and Testable.Config.Log == record)
            end
            const ok = pcall(Testable.configure, { Log = function() end, Workers = 0 })
            assert(not ok and Testable.Config.Log == record)
            Testable.resetConfig()
            assert(Testable.Config.Log == nil and not Testable.Config.Verbose)
            assert(not pcall(Testable.configure, { Log = record, Workers = 0 }))
            assert(Testable.Config.Log == nil)
        ]])
    end)

    it("delivers parallel completion and failure details in execution order across config resets", function()
        const output, errors = run([[
            const results, passed = Testable.run({ { Name = "Async", Func = function()
                -- Registration must not change the captured flag or destination.
                Testable.resetConfig()
                Testable.configure({ Log = function() error("wrong sink") end })
                describe("nested", function()
                    it("slow", function() task.wait(0.05) end)
                    it("fast failure", function()
                        task.wait(0.01)
                        Testable.resetConfig()
                        error("verbose failure detail", 0)
                    end)
                end)
            end } })
            assert(not passed and results.successCount == 1 and results.failureCount == 1)
            assert(messages[1] == "[Testable] Starting test plan execution...")
            assert(messages[#messages] == "[Testable] Test plan execution complete.")
            assert(position("Starting: fast failure") < position("Failed: fast failure"))
            assert(position("Failed: fast failure") < position("    Error: "))
            assert(string.find(messages[position("    Error: ")], "verbose failure detail", 1, true))
            assert(position("    Error: ") < position("Passed: slow"))
            assert(position("Passed: slow") < position("Completed describe block: nested"))
            assert(position("Completed describe block: nested") < #messages)
            assert(print == originalPrint)
        ]])
        expect(output).to.equal("")
        expect(errors).to.equal("")
    end)

    it("delivers sequential focus, skip, and planning diagnostics through the same sink", function()
        run([[
            Testable.configure({ Parallel = false })
            const _, passed = Testable.run({ { Name = "Sequential", Func = function()
                describe("chosen", function()
                    itFOCUS("passes", function() Testable.resetConfig() end)
                    it("excluded", function() error("must not execute") end)
                end)
                describe("broken", function() error("planning problem") end)
            end } })
            assert(not passed)
            assert(position("Focus nodes detected") < position("Entering describe block: chosen"))
            assert(position("Running: passes") < position("Passed: passes"))
            assert(position("Passed: passes") < position("Skipped: excluded"))
            assert(position("Skipped: excluded") < position("Planning error in: broken"))
            assert(messages[#messages] == "[Testable] Test plan execution complete.")
        ]])
    end)

    it("does not deliver native messages when verbose is disabled even if specs enable it", function()
        const output, errors = run([[
            Testable.configure({ Verbose = false })
            const _, passed = Testable.run({ { Name = "Quiet", Func = function()
                Testable.configure({ Verbose = true })
                it("passes", function() end)
            end } })
            assert(passed and #messages == 0 and print == originalPrint)
        ]])
        expect(output).to.equal("")
        expect(errors).to.equal("")
    end)

    it("keeps default console formatting and resets the destination between runs", function()
        const output = run([[
            Testable.resetConfig()
            Testable.configure({ Reporters = {}, Verbose = true })
            const _, passed = Testable.run({ { Name = "Default", Func = function()
                it("fails", function() error("default detail", 0) end)
            end } })
            assert(not passed and #messages == 0 and print == originalPrint)
            Testable.configure({ Log = record })
            Testable.run({ { Name = "Next", Func = function() it("passes", function() end) end } })
            assert(messages[1] == "[Testable] Starting test plan execution...")
        ]])
        expect(output).to.contain("[Testable] Starting test plan execution...")
        expect(output).to.contain("    Error: default detail")
        expect(output).to.contain("[Testable] Test plan execution complete.")
    end)

    it("never intercepts text reports or test-owned output", function()
        const output = run([[
            Testable.configure({ Reporters = { "Text" } })
            const _, passed = Testable.run({ { Name = "ReportSpec", Func = function()
                print("planning output")
                it("report test", function() print("test output") end)
            end } })
            assert(passed and print == originalPrint)
            for _, message in ipairs(messages) do
                assert(string.sub(message, 1, 11) == "[Testable] ")
                assert(not string.find(message, "planning output", 1, true))
                assert(not string.find(message, "test output", 1, true))
            end
            assert(messages[#messages] == "[Testable] Test plan execution complete.")
        ]])
        expect(output).to.contain("planning output")
        expect(output).to.contain("test output")
        expect(output).to.contain("ReportSpec")
        expect(output).never.to.contain("[Testable]")
    end)

    it("leaves machine reports alone on stdout while a callback writes to stderr", function()
        const output, errors = run([[
            const serde = require("@lune/serde")
            const stdio = require("@lune/stdio")
            Testable.configure({ Log = function(message) record(message); stdio.ewrite(message .. "\n") end,
                Reporters = { "Json" } })
            const _, passed = Testable.run({ { Name = "JsonSpec", Func = function()
                it("passes", function() end)
            end } })
            assert(passed and #messages > 0 and print == originalPrint)
        ]])
        expect(pcall(function()
            require("@lune/serde").decode("json", output)
        end)).to.equal(true)
        expect(output).never.to.contain("[Testable]")
        expect(errors).to.contain("[Testable] Test plan execution complete.")
    end)

    it("finishes parallel tasks before propagating a callback error", function()
        run([[
            local finished = false
            Testable.configure({ Log = function(message)
                if string.find(message, "Starting: slow", 1, true) then error("sink failure", 0) end
            end })
            const ok, problem = pcall(Testable.run, { { Name = "SinkFailure", Func = function()
                it("slow", function() task.wait(0.01); finished = true end)
            end } })
            assert(not ok and string.find(tostring(problem), "sink failure", 1, true) and finished, tostring(problem))
            assert(print == originalPrint)
            Testable.resetConfig()
            Testable.configure({ Reporters = {} })
            const _, passed = Testable.run({ { Name = "Recovered", Func = function()
                it("passes", function() end)
            end } })
            assert(passed)
        ]])
    end)
end
