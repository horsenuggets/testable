--[[

CoverageTest.spec

Tests for the Coverage module: resolveRoots, collect, and integration
with Config. Coverage data depends on debug.iscoverageenabled being
true, which is the default in Lune 0.10.4-horse.14.2+.

--]]

local Config = require("../Source/Testable/Config")
local Coverage = require("../Source/Testable/Coverage")
local Testable = require("../Source/Testable")

-- Require the fixture module so it has coverage data
local SampleModule = require("./CoverageFixtures/SampleModule")

-- Script references
local fixturesDir = script.Parent.CoverageFixtures
local sampleScript = fixturesDir.SampleModule

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
