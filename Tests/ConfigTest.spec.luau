--[[

ConfigTest.spec

Tests for the Testable configuration system including setting and resetting options.

--]]

const Testable = require("../Source/Testable")
const Config = Testable.Config
const afterEach, describe, expect, it = Testable.afterEach, Testable.describe, Testable.expect, Testable.it

return function()
    describe("Testable.configure()", function()
        afterEach(function()
            Config.reset()
        end)

        it("should set AlphabeticalSort", function()
            expect(Config.AlphabeticalSort).to.equal(false)
            Testable.configure({ AlphabeticalSort = true })
            expect(Config.AlphabeticalSort).to.equal(true)
        end)

        it("should set CoverageRows and CoverageSort in every combination", function()
            expect(Config.CoverageRows).to.equal(20)
            expect(Config.CoverageSort).to.equal("Percentage")
            for _, rows in { 1, 20, 100 } do
                for _, sort in { "HitLines", "Percentage" } :: { any } do
                    Testable.configure({ CoverageRows = rows, CoverageSort = sort })
                    expect(Config.CoverageRows).to.equal(rows)
                    expect(Config.CoverageSort).to.equal(sort)
                end
            end
        end)

        it("should set ForbidFocus and reset it to off", function()
            -- The outer run may have the guard on, so start from the default.
            Config.reset()
            expect(Config.ForbidFocus).to.equal(false)
            Testable.configure({ ForbidFocus = true })
            expect(Config.ForbidFocus).to.equal(true)
            Testable.configure({ Parallel = false })
            expect(Config.ForbidFocus).to.equal(true)
            Testable.resetConfig()
            expect(Config.ForbidFocus).to.equal(false)
        end)

        it("should set Indent", function()
            expect(Config.Indent).to.equal("   ")
            Testable.configure({ Indent = "\t" })
            expect(Config.Indent).to.equal("\t")
        end)

        it("should set MaxConcurrency", function()
            expect(Config.MaxConcurrency).to.equal(4)
            Testable.configure({ MaxConcurrency = 8 })
            expect(Config.MaxConcurrency).to.equal(8)
        end)

        it("should set Parallel", function()
            expect(Config.Parallel).to.equal(true)
            Testable.configure({ Parallel = false })
            expect(Config.Parallel).to.equal(false)
        end)

        it("should set InjectGlobals", function()
            expect(Config.InjectGlobals).to.equal(true)
            Testable.configure({ InjectGlobals = false })
            expect(Config.InjectGlobals).to.equal(false)

            -- Other specs in this run rely on injection, so restore it before yielding.
            Testable.resetConfig()
            expect(Config.InjectGlobals).to.equal(true)
        end)

        it("should set PrintSkipped", function()
            expect(Config.PrintSkipped).to.equal(false)
            Testable.configure({ PrintSkipped = true })
            expect(Config.PrintSkipped).to.equal(true)
        end)

        it("copies suite preferences and resets them to a fresh empty list", function()
            Config.reset()
            const preferred = { "Heavy", "Other" }
            Testable.configure({ SuiteOrder = preferred })
            preferred[1] = "Changed"
            expect(table.concat(Config.SuiteOrder, ",")).to.equal("Heavy,Other")
            Testable.configure({ Parallel = false })
            expect(table.concat(Config.SuiteOrder, ",")).to.equal("Heavy,Other")
            const previous = Config.SuiteOrder
            Testable.resetConfig()
            expect(#Config.SuiteOrder).to.equal(0)
            expect(Config.SuiteOrder == previous).to.equal(false)
            table.insert(previous, "Retained")
            expect(#Config.SuiteOrder).to.equal(0)
            Testable.configure({ SuiteOrder = { "Heavy" } })
            Testable.configure({ SuiteOrder = {} })
            expect(#Config.SuiteOrder).to.equal(0)
        end)

        it("should set Verbose", function()
            expect(Config.Verbose).to.equal(false)
            Testable.configure({ Verbose = true })
            expect(Config.Verbose).to.equal(true)
        end)

        it("should set multiple options at once", function()
            Testable.configure({
                AlphabeticalSort = true,
                Indent = "  ",
                MaxConcurrency = 2,
                Parallel = false,
                PrintSkipped = true,
                Verbose = true,
            })

            expect(Config.AlphabeticalSort).to.equal(true)
            expect(Config.Indent).to.equal("  ")
            expect(Config.MaxConcurrency).to.equal(2)
            expect(Config.Parallel).to.equal(false)
            expect(Config.PrintSkipped).to.equal(true)
            expect(Config.Verbose).to.equal(true)
        end)

        it("should only update provided options", function()
            Testable.configure({ Parallel = false })

            expect(Config.Parallel).to.equal(false)
            expect(Config.AlphabeticalSort).to.equal(false)
            expect(Config.Indent).to.equal("   ")
            expect(Config.MaxConcurrency).to.equal(4)
        end)
    end, { Serial = true })

    describe("Testable.resetConfig()", function()
        it("should reset all options to defaults", function()
            Testable.configure({
                AlphabeticalSort = true,
                CoverageRows = 100,
                CoverageSort = "HitLines",
                Indent = "\t\t",
                MaxConcurrency = 16,
                Parallel = false,
                PrintSkipped = true,
                Verbose = true,
            })

            Testable.resetConfig()

            expect(Config.AlphabeticalSort).to.equal(false)
            expect(Config.CoverageRows).to.equal(20)
            expect(Config.CoverageSort).to.equal("Percentage")
            expect(Config.Indent).to.equal("   ")
            expect(Config.MaxConcurrency).to.equal(4)
            expect(Config.Parallel).to.equal(true)
            expect(Config.PrintSkipped).to.equal(false)
            expect(Config.Verbose).to.equal(false)
        end)
    end, { Serial = true })

    describe("Config validation", function()
        afterEach(function()
            Config.reset()
        end)

        it("should error if options is not a table", function()
            expect(function()
                Testable.configure("invalid" :: any)
            end).to.throw("options must be a table")
        end)

        it("should error if InjectGlobals is not a boolean", function()
            expect(function()
                Testable.configure({ InjectGlobals = "no" } :: any)
            end).to.throw("InjectGlobals must be a boolean")
        end)

        it("should error if AlphabeticalSort is not a boolean", function()
            expect(function()
                Testable.configure({ AlphabeticalSort = "yes" })
            end).to.throw("AlphabeticalSort must be a boolean")
        end)

        it("should error if ForbidFocus is not a boolean", function()
            for _, value in { "true", 1, {} } :: { any } do
                expect(function()
                    Testable.configure({ ForbidFocus = value })
                end).to.throw("ForbidFocus must be a boolean")
            end
        end)

        it("should error if Indent is not a string", function()
            expect(function()
                Testable.configure({ Indent = 4 })
            end).to.throw("Indent must be a string")
        end)

        it("should error if MaxConcurrency is not a number", function()
            expect(function()
                Testable.configure({ MaxConcurrency = "four" })
            end).to.throw("MaxConcurrency must be a number")
        end)

        it("should error if MaxConcurrency is less than 1", function()
            expect(function()
                Testable.configure({ MaxConcurrency = 0 })
            end).to.throw("MaxConcurrency must be at least 1")
        end)

        it("should error if Parallel is not a boolean", function()
            expect(function()
                Testable.configure({ Parallel = 1 })
            end).to.throw("Parallel must be a boolean")
        end)

        it("should error if PrintSkipped is not a boolean", function()
            expect(function()
                Testable.configure({ PrintSkipped = "true" })
            end).to.throw("PrintSkipped must be a boolean")
        end)

        it("should reject invalid CoverageRows", function()
            for _, value in { 0, -1, 1.5, 0 / 0, math.huge } do
                expect(function()
                    Testable.configure({ CoverageRows = value })
                end).to.throw("CoverageRows must be a positive integer")
            end
            expect(function()
                Testable.configure({ CoverageRows = "20" } :: any)
            end).to.throw("CoverageRows must be a number")
            expect(Config.CoverageRows).to.equal(20)
        end)

        it("should reject invalid CoverageSort", function()
            for _, value in { "Name", "hitlines", 1, true } :: { any } do
                expect(function()
                    Testable.configure({ CoverageSort = value })
                end).to.throw('CoverageSort must be "HitLines" or "Percentage"')
            end
            expect(Config.CoverageSort).to.equal("Percentage")
        end)

        it("rejects malformed suite preference lists without applying other options", function()
            for _, invalid in
                {
                    "Suite",
                    { "" },
                    { "   " },
                    { 1 },
                    { "Repeated", "Repeated" },
                    { [1] = "First", [3] = "Third" },
                    { Named = "Suite" },
                    { [1.5] = "Suite" },
                } :: { any }
            do
                Testable.configure({ SuiteOrder = { "Original" } })
                const ok, problem = pcall(Testable.configure, { Indent = ">", SuiteOrder = invalid } :: any)
                expect(ok).to.equal(false)
                expect(Testable.ToolError.is(problem)).to.equal(true)
                expect(problem.Kind).to.equal(Testable.ToolError.Kind.InvalidConfiguration)
                expect(table.concat(Config.SuiteOrder, ",")).to.equal("Original")
                expect(Config.Indent).to.equal("   ")
            end
        end)

        it("should error if Verbose is not a boolean", function()
            expect(function()
                Testable.configure({ Verbose = {} } :: any)
            end).to.throw("Verbose must be a boolean")
        end)
    end, { Serial = true })

    describe("invalid configuration as a tool error", function()
        -- None of these calls changes the configuration, since every one is rejected.
        const invalidCases: { { Options: any, Problem: string } } = {
            { Options = "invalid", Problem = "options must be a table" },
            { Options = { AlphabeticalSort = "yes" }, Problem = "AlphabeticalSort must be a boolean" },
            { Options = { Coverage = "yes" }, Problem = "Coverage must be a boolean" },
            { Options = { CoverageRows = 0 }, Problem = "CoverageRows must be a positive integer" },
            { Options = { CoverageSort = "Name" }, Problem = 'CoverageSort must be "HitLines" or "Percentage"' },
            { Options = { CoverageThreshold = 101 }, Problem = "CoverageThreshold must be between 0 and 100" },
            { Options = { Filter = 5 }, Problem = "Filter must be a string" },
            { Options = { ForbidFocus = 1 }, Problem = "ForbidFocus must be a boolean" },
            { Options = { Indent = 4 }, Problem = "Indent must be a string" },
            { Options = { InjectGlobals = "no" }, Problem = "InjectGlobals must be a boolean" },
            { Options = { MaxConcurrency = 0 }, Problem = "MaxConcurrency must be at least 1" },
            { Options = { Parallel = 1 }, Problem = "Parallel must be a boolean" },
            { Options = { PrintSkipped = "true" }, Problem = "PrintSkipped must be a boolean" },
            {
                Options = { ReporterOutputs = { Text = "report.txt" } },
                Problem = 'ReporterOutputs keys must be "JUnit", "Json", or "Lcov"',
            },
            {
                Options = { Reporters = { "Xml" } },
                Problem = 'Reporters must only contain "JUnit", "Json", "Lcov", or "Text"',
            },
            { Options = { SlowestTests = -1 }, Problem = "SlowestTests must be a non-negative integer" },
            {
                Options = { SnapshotStore = {} },
                Problem = "SnapshotStore must be a table with read and write functions",
            },
            { Options = { Timeout = 0 }, Problem = "Timeout must be a positive number of seconds" },
            { Options = { UpdateSnapshots = "yes" }, Problem = "UpdateSnapshots must be a boolean" },
            { Options = { Verbose = {} }, Problem = "Verbose must be a boolean" },
        }

        it("should throw an identifiable tool error for every invalid option", function()
            for _, case in invalidCases do
                const ok, problem = pcall(Testable.configure, case.Options)

                expect(ok).to.equal(false)
                expect(Testable.ToolError.is(problem)).to.equal(true)
                expect(problem.Kind).to.equal(Testable.ToolError.Kind.InvalidConfiguration)
                expect(problem.Message).to.equal(`The configuration is not valid. {case.Problem}.`)
                expect(tostring(problem)).to.equal(problem.Message)
            end
        end)

        it("should keep the tool error apart from the other kinds", function()
            const _, problem = pcall(Testable.configure, { Parallel = 1 })
            for name, kind in Testable.ToolError.Kind :: { [string]: string } do
                expect(problem.Kind == kind).to.equal(name == "InvalidConfiguration")
            end
        end)

        it("should explain how to turn coverage on when it is not available", function()
            -- Coverage can only be refused where the runtime has it turned off, so this
            -- case covers the runtimes that do have it by doing nothing.
            if type(debug.iscoverageenabled) == "function" and debug.iscoverageenabled() then
                return
            end

            const ok, problem = pcall(Testable.configure, { Coverage = true })
            expect(ok).to.equal(false)
            expect(Testable.ToolError.is(problem)).to.equal(true)
            expect(problem.Kind).to.equal(Testable.ToolError.Kind.InvalidConfiguration)
            expect(string.find(problem.Message, "Cannot enable coverage because", 1, true) ~= nil).to.equal(true)
        end)

        it("should not throw for valid options", function()
            const ok = pcall(Testable.configure, { Indent = Config.Indent })
            expect(ok).to.equal(true)
        end)

        it("should apply none of the options when one of them is not valid", function()
            const before = table.clone(Config)

            -- The valid options come before the invalid one in the order they are
            -- checked, and they include one that is unset by default and one that an
            -- empty string would clear.
            const rejected = pcall(Testable.configure, {
                AlphabeticalSort = not before.AlphabeticalSort,
                CoverageRoots = {},
                Filter = if before.Filter == nil then "anything" else "",
                Indent = `{before.Indent}>`,
                Verbose = "yes",
            })

            expect(rejected).to.equal(false)
            for key, value in before do
                expect((Config :: any)[key]).to.equal(value)
            end
            for key in Config :: any do
                expect(before[key] ~= nil).to.equal(true)
            end
        end)
    end, { Serial = true })
end
