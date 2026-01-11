--[[

ConfigTest.spec

Tests for the Testable configuration system including setting and resetting options.

--]]

local Testable = require("../Source/Testable")
local Config = Testable.Config

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

        it("should set PrintSkipped", function()
            expect(Config.PrintSkipped).to.equal(false)
            Testable.configure({ PrintSkipped = true })
            expect(Config.PrintSkipped).to.equal(true)
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
    end)

    describe("Testable.resetConfig()", function()
        it("should reset all options to defaults", function()
            Testable.configure({
                AlphabeticalSort = true,
                Indent = "\t\t",
                MaxConcurrency = 16,
                Parallel = false,
                PrintSkipped = true,
                Verbose = true,
            })

            Testable.resetConfig()

            expect(Config.AlphabeticalSort).to.equal(false)
            expect(Config.Indent).to.equal("   ")
            expect(Config.MaxConcurrency).to.equal(4)
            expect(Config.Parallel).to.equal(true)
            expect(Config.PrintSkipped).to.equal(false)
            expect(Config.Verbose).to.equal(false)
        end)
    end)

    describe("Config validation", function()
        afterEach(function()
            Config.reset()
        end)

        it("should error if options is not a table", function()
            expect(function()
                Testable.configure("invalid" :: any)
            end).to.throw("options must be a table")
        end)

        it("should error if AlphabeticalSort is not a boolean", function()
            expect(function()
                Testable.configure({ AlphabeticalSort = "yes" })
            end).to.throw("AlphabeticalSort must be a boolean")
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

        it("should error if Verbose is not a boolean", function()
            expect(function()
                Testable.configure({ Verbose = {} } :: any)
            end).to.throw("Verbose must be a boolean")
        end)
    end)
end
