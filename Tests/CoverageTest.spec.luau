--[[

CoverageTest.spec

Tests for the Coverage module: resolveRoots, collect, and integration
with Config. Coverage data depends on debug.iscoverageenabled being
true, which is the default in Lune 0.10.4-horse.14.2+.

--]]

local Config = require("../Source/Testable/Config")
local Coverage = require("../Source/Testable/Coverage")
local Testable = require("../Source/Testable")

-- Simple modules to measure coverage against
local SampleModule = {
    add = function(a: number, b: number): number
        return a + b
    end,
    subtract = function(a: number, b: number): number
        return a - b
    end,
    unused = function()
        return "never called"
    end,
}

return function()
    describe("Coverage.resolveRoots", function()
        it("should resolve a dictionary of module tables", function()
            local roots = {
                Sample = SampleModule,
            }
            local resolved = Coverage.resolveRoots(roots)
            expect(#resolved).to.equal(1)
            expect(resolved[1].Name).to.equal("Sample")
            expect(resolved[1].Module).to.equal(SampleModule)
        end)

        it("should sort keys alphabetically", function()
            local moduleA = { fn = function() end }
            local moduleB = { fn = function() end }
            local roots = {
                Zebra = moduleA,
                Alpha = moduleB,
            }
            local resolved = Coverage.resolveRoots(roots)
            expect(resolved[1].Name).to.equal("Alpha")
            expect(resolved[2].Name).to.equal("Zebra")
        end)

        it("should deduplicate the same module table", function()
            local roots = {
                First = SampleModule,
                Second = SampleModule,
            }
            local resolved = Coverage.resolveRoots(roots)
            expect(#resolved).to.equal(1)
        end)

        it("should handle empty dictionary", function()
            local resolved = Coverage.resolveRoots({})
            expect(#resolved).to.equal(0)
        end)
    end)

    describe("Coverage.collect", function()
        it("should return a report with correct structure", function()
            SampleModule.add(1, 2)

            local report = Coverage.collect({
                Sample = SampleModule,
            })

            if report == nil then
                -- Coverage disabled, skip
                return
            end

            expect(report.Files).to.be.ok()
            expect(report.TotalExecutableLines).to.be.a("number")
            expect(report.TotalHitLines).to.be.a("number")
            expect(report.TotalPercentage).to.be.a("number")
        end)

        it("should report per-file coverage", function()
            SampleModule.add(1, 2)
            SampleModule.subtract(3, 1)

            local report = Coverage.collect({
                Sample = SampleModule,
            })

            if report == nil then
                return
            end

            expect(#report.Files).to.equal(1)
            expect(report.Files[1].Name).to.equal("Sample")
            expect(report.Files[1].ExecutableLines).to.be.a("number")
            expect(report.Files[1].HitLines).to.be.a("number")
            expect(report.Files[1].Percentage).to.be.a("number")
        end)

        it("should report per-function coverage", function()
            SampleModule.add(1, 2)

            local report = Coverage.collect({
                Sample = SampleModule,
            })

            if report == nil then
                return
            end

            local file = report.Files[1]
            expect(#file.Functions > 0).to.equal(true)

            -- Functions should be sorted alphabetically
            local names = {}
            for _, fn in file.Functions do
                table.insert(names, fn.Name)
            end
            for i = 1, #names - 1 do
                expect(names[i] < names[i + 1]).to.equal(true)
            end
        end)

        it("should return nil when coverage is disabled", function()
            -- This test only works when LUNE_COVERAGE=0
            -- When coverage is enabled (default), it returns a report
            local hasApi = type(debug.iscoverageenabled) == "function"
            if hasApi and debug.iscoverageenabled() then
                -- Coverage is enabled, just verify it returns non-nil
                local report = Coverage.collect({ Sample = SampleModule })
                expect(report).to.be.ok()
            end
            -- When disabled, Coverage.collect returns nil (tested in
            -- RobloxCloudTest)
        end)

        it("should calculate percentage correctly", function()
            SampleModule.add(1, 2)
            SampleModule.subtract(3, 1)

            local report = Coverage.collect({
                Sample = SampleModule,
            })

            if report == nil then
                return
            end

            expect(report.TotalPercentage >= 0).to.equal(true)
            expect(report.TotalPercentage <= 100).to.equal(true)

            if report.TotalExecutableLines > 0 then
                local expected = math.floor((report.TotalHitLines / report.TotalExecutableLines) * 100)
                expect(report.TotalPercentage).to.equal(expected)
            end
        end)
    end)

    describe("Config coverage options", function()
        afterEach(function()
            Config.reset()
        end)

        it("should default Coverage to false", function()
            expect(Config.Coverage).to.equal(false)
        end)

        it("should default CoverageRoots to nil", function()
            expect(Config.CoverageRoots).to.equal(nil)
        end)

        it("should default CoverageThreshold to 0", function()
            expect(Config.CoverageThreshold).to.equal(0)
        end)

        it("should set Coverage to true when coverage is available", function()
            local hasApi = type(debug.iscoverageenabled) == "function"
            if not hasApi then
                return
            end

            Config.set({ Coverage = true })
            expect(Config.Coverage).to.equal(true)
        end)

        it("should set CoverageRoots", function()
            local roots = { Foo = {} }
            Config.set({ CoverageRoots = roots })
            expect(Config.CoverageRoots).to.equal(roots)
        end)

        it("should set CoverageThreshold", function()
            Config.set({ CoverageThreshold = 80 })
            expect(Config.CoverageThreshold).to.equal(80)
        end)

        it("should error if CoverageThreshold is out of range", function()
            expect(function()
                Config.set({ CoverageThreshold = -1 })
            end).to.throw()
            expect(function()
                Config.set({ CoverageThreshold = 101 })
            end).to.throw()
        end)

        it("should error if Coverage is not a boolean", function()
            expect(function()
                Config.set({ Coverage = "yes" :: any })
            end).to.throw()
        end)

        it("should reset coverage options", function()
            local hasApi = type(debug.iscoverageenabled) == "function"
            if hasApi then
                Config.set({ Coverage = true })
            end
            Config.set({ CoverageThreshold = 90 })
            Config.set({ CoverageRoots = { Foo = {} } })
            Config.reset()
            expect(Config.Coverage).to.equal(false)
            expect(Config.CoverageRoots).to.equal(nil)
            expect(Config.CoverageThreshold).to.equal(0)
        end)
    end)

    describe("Testable.run with coverage", function()
        afterEach(function()
            Testable.resetConfig()
        end)

        it("should pass when coverage meets threshold", function()
            local hasApi = type(debug.iscoverageenabled) == "function"
            if not hasApi or not debug.iscoverageenabled() then
                return
            end

            Testable.configure({
                Coverage = true,
                CoverageThreshold = 0,
                CoverageRoots = { Sample = SampleModule },
            })

            local _, passed = Testable.run({
                MiniTest = function()
                    describe("Mini", function()
                        it("calls sample", function()
                            SampleModule.add(1, 2)
                        end)
                    end)
                end,
            })
            expect(passed).to.equal(true)
        end)

        it("should not run coverage when Coverage is false", function()
            Testable.configure({
                Coverage = false,
                CoverageRoots = { Sample = SampleModule },
            })

            local _, passed = Testable.run({
                MiniTest = function()
                    describe("Mini", function()
                        it("passes", function()
                            expect(true).to.be.ok()
                        end)
                    end)
                end,
            })
            expect(passed).to.equal(true)
        end)
    end)
end
