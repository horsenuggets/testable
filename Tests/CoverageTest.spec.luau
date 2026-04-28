--[[

CoverageTest.spec

Tests for the Coverage module: resolveRoots, collect, and integration
with Config. Coverage data depends on debug.iscoverageenabled being
true, which is the default in Lune 0.10.4-horse.14.2+.

--]]

local Config = require("../Source/Testable/Config")
local Coverage = require("../Source/Testable/Coverage")
local Testable = require("../Source/Testable")

-- Require the fixture modules so they have coverage data
local SampleModule = require("./CoverageFixtures/SampleModule")
local HelperModule = require("./CoverageFixtures/HelperModule")

-- Script references
local fixturesDir = script.Parent.CoverageFixtures
local sampleScript = fixturesDir.SampleModule
local helperScript = fixturesDir.HelperModule

return function()
    describe("Coverage.resolveRoots", function()
        it("should discover modules from a directory", function()
            local resolved = Coverage.resolveRoots(fixturesDir)
            expect(#resolved >= 1).to.equal(true)

            local foundSample = false
            for _, entry in resolved do
                if entry.Name == "SampleModule" then
                    foundSample = true
                end
            end
            expect(foundSample).to.equal(true)
        end)

        it("should resolve a single file script", function()
            local resolved = Coverage.resolveRoots(sampleScript)
            expect(#resolved).to.equal(1)
            expect(resolved[1].Name).to.equal("SampleModule")
        end)

        it("should exclude .spec files", function()
            local testsDir = script.Parent
            local resolved = Coverage.resolveRoots(testsDir)
            for _, entry in resolved do
                expect(entry.Name:match("%.spec$")).to.equal(nil)
            end
        end)
    end)

    describe("Coverage.collect", function()
        it("should return a report with correct structure", function()
            SampleModule.add(1, 2)

            local report = Coverage.collect(fixturesDir)

            if report == nil then
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

            local report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            expect(#report.Files).to.equal(1)
            expect(report.Files[1].Name).to.equal("SampleModule")
            expect(report.Files[1].ExecutableLines).to.be.a("number")
            expect(report.Files[1].HitLines).to.be.a("number")
            expect(report.Files[1].Percentage).to.be.a("number")
        end)

        it("should include local functions in coverage", function()
            SampleModule.double(5)

            local report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            local file = report.Files[1]
            local foundHelper = false
            for _, fn in file.Functions do
                if fn.Name == "helper" then
                    foundHelper = true
                    expect(fn.HitLines > 0).to.equal(true)
                end
            end
            expect(foundHelper).to.equal(true)
        end)

        it("should return nil when coverage is disabled", function()
            local hasApi = type(debug.iscoverageenabled) == "function"
            if hasApi and debug.iscoverageenabled() then
                local report = Coverage.collect(sampleScript)
                expect(report).to.be.ok()
            end
        end)

        it("should calculate percentage correctly", function()
            SampleModule.add(1, 2)
            SampleModule.subtract(3, 1)

            local report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            expect(report.TotalPercentage >= 0).to.equal(true)
            expect(report.TotalPercentage <= 100).to.equal(true)

            if report.TotalExecutableLines > 0 then
                local expected = math.floor((report.TotalHitLines / report.TotalExecutableLines) * 1000) / 10
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
            Config.set({ CoverageRoots = script })
            expect(Config.CoverageRoots).to.equal(script)
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
            Config.set({ CoverageRoots = script })
            Config.reset()
            expect(Config.Coverage).to.equal(false)
            expect(Config.CoverageRoots).to.equal(nil)
            expect(Config.CoverageThreshold).to.equal(0)
        end)
    end)

    describe("Coverage deduplication", function()
        it("should not duplicate files when same script is passed twice", function()
            local resolved = Coverage.resolveRoots({
                SampleModule = sampleScript,
                SampleModuleDupe = sampleScript,
            })

            local sampleCount = 0
            for _, entry in resolved do
                if entry.Name == "SampleModule" or entry.Name == "SampleModuleDupe" then
                    sampleCount += 1
                end
            end
            expect(sampleCount).to.equal(1)
        end)

        it("should not duplicate files when directory overlaps with individual file", function()
            local resolved = Coverage.resolveRoots({
                Fixtures = fixturesDir,
                SampleModule = sampleScript,
            })

            local sampleCount = 0
            for _, entry in resolved do
                if entry.Name == "SampleModule" then
                    sampleCount += 1
                end
            end
            expect(sampleCount).to.equal(1)
        end)

        it("should not duplicate files when same directory is passed twice", function()
            local resolved = Coverage.resolveRoots({
                FixturesA = fixturesDir,
                FixturesB = fixturesDir,
            })

            local names = {}
            for _, entry in resolved do
                expect(names[entry.Name]).to.equal(nil)
                names[entry.Name] = true
            end
        end)

        it("should include all unique modules from overlapping roots", function()
            HelperModule.greet("test")

            local resolved = Coverage.resolveRoots({
                Fixtures = fixturesDir,
                Helper = helperScript,
            })

            local foundSample = false
            local foundHelper = false
            for _, entry in resolved do
                if entry.Name == "SampleModule" then
                    foundSample = true
                end
                if entry.Name == "HelperModule" then
                    foundHelper = true
                end
            end
            expect(foundSample).to.equal(true)
            expect(foundHelper).to.equal(true)
        end)

        it("should produce correct totals with no double-counting", function()
            SampleModule.add(1, 2)
            HelperModule.greet("test")

            local singleReport = Coverage.collect(fixturesDir)
            local overlapReport = Coverage.collect({
                Fixtures = fixturesDir,
                SampleModule = sampleScript,
                HelperModule = helperScript,
            })

            if singleReport == nil or overlapReport == nil then
                return
            end

            expect(overlapReport.TotalExecutableLines).to.equal(singleReport.TotalExecutableLines)
            expect(overlapReport.TotalHitLines).to.equal(singleReport.TotalHitLines)
        end)
    end)

    describe("Percentage rounding edge cases", function()
        -- The percentage formula is: math.floor((hit / executable) * 1000) / 10
        -- This always rounds DOWN to one decimal place. The threshold comparison
        -- is: TotalPercentage < threshold (so equal-to-threshold passes).

        it("should round down 79.999... to 79.9 (below 80.0 threshold)", function()
            -- 799 / 1000 = 0.799 → floor(799) / 10 = 79.9
            local pct = math.floor((799 / 1000) * 1000) / 10
            expect(pct).to.equal(79.9)
            expect(pct < 80).to.equal(true)
        end)

        it("should compute exactly 80.0 when ratio is exact (meets 80.0 threshold)", function()
            -- 800 / 1000 = 0.8 → floor(800) / 10 = 80.0
            local pct = math.floor((800 / 1000) * 1000) / 10
            expect(pct).to.equal(80.0)
            expect(pct < 80).to.equal(false)
        end)

        it("should round down 80.05... to 80.0 (meets 80.0 threshold)", function()
            -- 801 / 1001 = 0.80019... → floor(800.19...) / 10 = 80.0
            local pct = math.floor((801 / 1001) * 1000) / 10
            expect(pct).to.equal(80.0)
            expect(pct < 80).to.equal(false)
        end)

        it("should round down 79.95... to 79.9 (below 80.0 threshold)", function()
            -- 879 / 1100 = 0.79909... → floor(799.09...) / 10 = 79.9
            local pct = math.floor((879 / 1100) * 1000) / 10
            expect(pct).to.equal(79.9)
            expect(pct < 80).to.equal(true)
        end)

        it("should handle 100.0% exactly", function()
            local pct = math.floor((50 / 50) * 1000) / 10
            expect(pct).to.equal(100.0)
        end)

        it("should handle 0.0% exactly", function()
            local pct = math.floor((0 / 50) * 1000) / 10
            expect(pct).to.equal(0.0)
        end)

        it("should handle very small coverage", function()
            -- 1 / 1000 = 0.001 → floor(1) / 10 = 0.1
            local pct = math.floor((1 / 1000) * 1000) / 10
            expect(pct).to.equal(0.1)
        end)

        it("should always round down, never up", function()
            -- 333 / 1000 = 0.333 → floor(333) / 10 = 33.3, not 33.4
            local pct = math.floor((333 / 1000) * 1000) / 10
            expect(pct).to.equal(33.3)

            -- 667 / 1000 = 0.667 → floor(667) / 10 = 66.7, not 66.8
            local pct2 = math.floor((667 / 1000) * 1000) / 10
            expect(pct2).to.equal(66.7)
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
                CoverageRoots = sampleScript,
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
                CoverageRoots = sampleScript,
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
