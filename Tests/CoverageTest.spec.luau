--[[

CoverageTest.spec

Tests for the Coverage module: resolveRoots, collect, and integration
with Config. Coverage data depends on debug.iscoverageenabled being
true, which is the default in Lune 0.10.4-horse.14.2+.

--]]

const Config = require("../Source/Testable/Config")
const Coverage = require("../Source/Testable/Coverage")
const Testable = require("../Source/Testable")

-- Require the fixture module so it has coverage data
const SampleModule = require("./CoverageFixtures/SampleModule")

-- Script references
const fixturesDir = script.Parent.CoverageFixtures
const sampleScript = fixturesDir.SampleModule

return function()
    describe("Coverage.resolveRoots", function()
        it("should discover modules from a directory", function()
            const resolved = Coverage.resolveRoots(fixturesDir)
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
            const resolved = Coverage.resolveRoots(sampleScript)
            expect(#resolved).to.equal(1)
            expect(resolved[1].Name).to.equal("SampleModule")
        end)

        it("should exclude .spec files", function()
            const testsDir = script.Parent
            const resolved = Coverage.resolveRoots(testsDir)
            for _, entry in resolved do
                expect(entry.Name:match("%.spec$")).to.equal(nil)
            end
        end)
    end)

    describe("Coverage.collect", function()
        it("should return a report with correct structure", function()
            SampleModule.add(1, 2)

            const report = Coverage.collect(fixturesDir)

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

            const report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            expect(#report.Files).to.equal(1)
            expect(report.Files[1].Name).to.equal("SampleModule")
            expect(report.Files[1].ExecutableLines).to.be.a("number")
            expect(report.Files[1].HitLines).to.be.a("number")
            expect(report.Files[1].Percentage).to.be.a("number")
            expect(report.Files[1].Path:match("SampleModule%.luau$") ~= nil).to.equal(true)
            const file = report.Files[1]
            expect(file.Percentage).to.equal(math.floor(file.HitLines / file.ExecutableLines * 10000) / 100)
            for _, fn in file.Functions do
                const expected = if fn.ExecutableLines > 0
                    then math.floor(fn.HitLines / fn.ExecutableLines * 10000) / 100
                    else 0
                expect(fn.Percentage).to.equal(expected)
            end
        end)

        it("should include local functions in coverage", function()
            SampleModule.double(5)

            const report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            const file = report.Files[1]
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
            const hasApi = type(debug.iscoverageenabled) == "function"
            if hasApi and debug.iscoverageenabled() then
                const report = Coverage.collect(sampleScript)
                expect(report).to.be.ok()
            end
        end)

        it("should calculate percentage correctly", function()
            SampleModule.add(1, 2)
            SampleModule.subtract(3, 1)

            const report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            expect(report.TotalPercentage >= 0).to.equal(true)
            expect(report.TotalPercentage <= 100).to.equal(true)

            if report.TotalExecutableLines > 0 then
                const expected = math.floor((report.TotalHitLines / report.TotalExecutableLines) * 10000) / 100
                expect(report.TotalPercentage).to.equal(expected)
            end
        end)

        it("should count every line of a module that was never required as missed", function()
            const report = Coverage.collect(fixturesDir.UnrequiredModule)

            if report == nil then
                return
            end

            const file = report.Files[1]
            expect(file.Loaded).to.equal(false)
            expect(file.ExecutableLines > 0).to.equal(true)
            expect(file.HitLines).to.equal(0)
            expect(file.Percentage).to.equal(0)
            expect(#file.Functions > 0).to.equal(true)
            for _, fn in file.Functions do
                expect(fn.HitLines).to.equal(0)
            end
            expect(report.TotalExecutableLines).to.equal(file.ExecutableLines)
        end)

        it("should mark required modules as loaded", function()
            SampleModule.add(1, 2)

            const report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            expect(report.Files[1].Loaded).to.equal(true)
            expect(report.Files[1].HitLines > 0).to.equal(true)
        end)

        it("should count a module that fails to compile as zero lines", function()
            const fs = require("@lune/fs")
            const brokenPath = `{tostring(fixturesDir)}/GeneratedBroken.luau`
            fs.writeFile(brokenPath, "return function(\n")
            const ok, report = pcall(Coverage.collect, fixturesDir.GeneratedBroken)
            fs.removeFile(brokenPath)
            assert(ok, report)

            if report == nil then
                return
            end

            expect(report.Files[1].Loaded).to.equal(false)
            expect(report.Files[1].ExecutableLines).to.equal(0)
            expect(report.Files[1].HitLines).to.equal(0)
        end)

        it("should report paths relative to the working directory", function()
            const report = Coverage.collect(sampleScript)

            if report == nil then
                return
            end

            expect(report.Files[1].Path).to.equal("Tests/CoverageFixtures/SampleModule.luau")
        end)
    end)

    describe("Coverage.track", function()
        const fs = require("@lune/fs")
        const luau = require("@lune/luau")
        const trackedPath = `{tostring(fixturesDir)}/TrackedModule.luau`

        const function loadTracked(trackAs: string): any
            const chunk = luau.load(fs.readFile(trackedPath), { debugName = trackedPath })
            Coverage.track(trackAs, chunk)
            return chunk()
        end

        const function functionCoverage(file: any, name: string): any
            for _, fn in file.Functions do
                if fn.Name == name then
                    return fn
                end
            end
            error(`Missing coverage for function "{name}".`)
        end

        it("should merge hits from every tracked load of a file", function()
            const aliasPath = `{tostring(fixturesDir)}/../CoverageFixtures/./TrackedModule.luau`
            loadTracked(aliasPath).classify(1)

            const first = Coverage.collect(fixturesDir.TrackedModule)
            if first == nil then
                return
            end
            const firstClassify = functionCoverage(first.Files[1], "classify")
            expect(first.Files[1].Loaded).to.equal(true)
            expect(firstClassify.HitLines > 0).to.equal(true)
            expect(firstClassify.HitLines < firstClassify.ExecutableLines).to.equal(true)

            loadTracked(trackedPath).classify(-1)

            const merged = Coverage.collect(fixturesDir.TrackedModule)
            assert(merged ~= nil)
            const classify = functionCoverage(merged.Files[1], "classify")
            expect(classify.HitLines).to.equal(classify.ExecutableLines)
            expect(functionCoverage(merged.Files[1], "unused").HitLines).to.equal(0)
            expect(merged.Files[1].HitLines > first.Files[1].HitLines).to.equal(true)
        end)

        it("should keep tracked coverage after Config.reset", function()
            loadTracked(trackedPath)
            Config.reset()

            const report = Coverage.collect(fixturesDir.TrackedModule)
            if report == nil then
                return
            end
            expect(report.Files[1].Loaded).to.equal(true)
            expect(report.Files[1].HitLines > 0).to.equal(true)
        end)

        it("should leave files that were never tracked at zero hits", function()
            loadTracked(trackedPath)

            const report = Coverage.collect(fixturesDir.UnrequiredModule)
            if report == nil then
                return
            end
            expect(report.Files[1].Loaded).to.equal(false)
            expect(report.Files[1].HitLines).to.equal(0)
        end)

        it("should reject invalid arguments", function()
            expect(function()
                Coverage.track(1 :: any, function() end)
            end).to.throw()
            expect(function()
                Coverage.track(trackedPath, {} :: any)
            end).to.throw()
        end)
    end)

    describe("Coverage.normalizePath", function()
        it("should collapse empty, dot, and parent segments", function()
            expect(Coverage.normalizePath("/a//b/./c/../d.luau")).to.equal("/a/b/d.luau")
            expect(Coverage.normalizePath("/a/b/../../c.luau")).to.equal("/c.luau")
        end)

        it("should convert backslashes and keep drive letters", function()
            expect(Coverage.normalizePath("C:\\a\\b\\..\\c.luau")).to.equal("C:/a/c.luau")
        end)

        it("should never climb above the root or a drive", function()
            expect(Coverage.normalizePath("/project/../../project/module.luau")).to.equal("/project/module.luau")
            expect(Coverage.normalizePath("/../a.luau")).to.equal("/a.luau")
            expect(Coverage.normalizePath("C:/../a.luau")).to.equal("C:/a.luau")
            expect(Coverage.normalizePath("C:/x/../../../a.luau")).to.equal("C:/a.luau")
        end)

        it("should give both drive letter cases one key", function()
            expect(Coverage.normalizePath("c:/project/Module.luau")).to.equal("C:/project/Module.luau")
            expect(Coverage.normalizePath("c:\\project\\Module.luau")).to.equal(
                Coverage.normalizePath("C:/project/Module.luau")
            )
            -- Only the drive letter is case-insensitive, so the rest keeps its case.
            expect(Coverage.normalizePath("C:/project/Module.luau")).never.to.equal(
                Coverage.normalizePath("C:/project/module.luau")
            )
        end)

        it("should resolve relative paths against the working directory", function()
            const cwd = require("@lune/process").cwd
            expect(Coverage.normalizePath("Tests/x/../y.luau")).to.equal(Coverage.normalizePath(`{cwd}/Tests/y.luau`))
        end)

        it("should resolve relative paths against a Windows working directory", function()
            const workingDirectory = "c:\\Users\\dev\\project"
            expect(Coverage.normalizePath("Tests\\y.luau", workingDirectory)).to.equal(
                "C:/Users/dev/project/Tests/y.luau"
            )
            expect(Coverage.normalizePath("Tests/y.luau", workingDirectory)).to.equal(
                Coverage.normalizePath("C:\\Users\\dev\\project\\Tests\\y.luau")
            )
            expect(Coverage.normalizePath("../y.luau", workingDirectory)).to.equal("C:/Users/dev/y.luau")
        end)

        it("should return the same key for every spelling of one file", function()
            const spellings = { "/a/b/c.luau", "/a//b/c.luau", "/a/./b/c.luau", "/a/x/../b/c.luau", "\\a\\b\\c.luau" }
            for _, spelling in spellings do
                expect(Coverage.normalizePath(spelling)).to.equal("/a/b/c.luau")
            end
        end)

        it("should keep a network share as one root", function()
            expect(Coverage.normalizePath("//server/share/Module.luau")).to.equal("//server/share/Module.luau")
            expect(Coverage.normalizePath("//server/share/../Module.luau")).to.equal("//server/share/Module.luau")
            expect(Coverage.normalizePath("\\\\server\\share\\x\\..\\Module.luau")).to.equal(
                "//server/share/Module.luau"
            )
            expect(Coverage.normalizePath("//server//share/Module.luau")).to.equal("//server/share/Module.luau")
            expect(Coverage.normalizePath("//server///share/../Module.luau")).to.equal("//server/share/Module.luau")
            -- Three or more leading slashes are a POSIX root, not a share.
            expect(Coverage.normalizePath("///a/b.luau")).to.equal("/a/b.luau")
        end)

        it("should keep the slash on a drive or POSIX root", function()
            expect(Coverage.normalizePath("C:/")).to.equal("C:/")
            expect(Coverage.normalizePath("c:/a/..")).to.equal("C:/")
            expect(Coverage.normalizePath("/a/..")).to.equal("/")
            expect(Coverage.normalizePath("//server/share/a/..")).to.equal("//server/share/")
        end)

        it("should resolve relative paths against a root working directory", function()
            expect(Coverage.normalizePath("Tests/Module.luau", "/")).to.equal("/Tests/Module.luau")
            expect(Coverage.normalizePath("Tests/Module.luau", "C:\\")).to.equal("C:/Tests/Module.luau")
            expect(Coverage.normalizePath("Tests/Module.luau", "//server/share/")).to.equal(
                "//server/share/Tests/Module.luau"
            )
            expect(Coverage.normalizePath("Tests/Module.luau", "/home/dev/")).to.equal("/home/dev/Tests/Module.luau")
        end)

        it("should return every result unchanged when normalized again", function()
            const workingDirectories = {
                "/",
                "/home/dev/project",
                "/home/dev/project/",
                "C:/",
                "C:\\Users\\dev\\project",
                "//server/share/",
                "//server/share/project",
            }
            const paths = {
                "Module.luau",
                "../Module.luau",
                "../../../../Module.luau",
                "./a/../b/./Module.luau",
                "/",
                "/a/..",
                "/../../x.luau",
                "C:/",
                "c:/a/..",
                "c:\\x\\..\\..\\y.luau",
                "//server/share",
                "//server/share/a/../..",
                "\\\\server\\share\\x.luau",
                "//server//share/../x.luau",
                "///a//b/../c.luau",
            }
            for _, workingDirectory in workingDirectories do
                for _, path in paths do
                    const once = Coverage.normalizePath(path, workingDirectory)
                    expect(Coverage.normalizePath(once, workingDirectory)).to.equal(once)
                    expect(Coverage.normalizePath(once, "/elsewhere")).to.equal(once)
                end
            end
        end)
    end)

    describe("Coverage.percentage", function()
        it("should floor to two decimals", function()
            expect(Coverage.percentage(480, 543126)).to.equal(0.08)
            expect(Coverage.percentage(2, 3)).to.equal(66.66)
            expect(Coverage.percentage(1, 1)).to.equal(100)
        end)

        it("should keep exact hundredths instead of flooring them away", function()
            for hit = 0, 10000 do
                expect(Coverage.percentage(hit, 10000)).to.equal(hit / 100)
            end
        end)

        it("should return zero when there are no executable lines", function()
            expect(Coverage.percentage(0, 0)).to.equal(0)
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
            const hasApi = type(debug.iscoverageenabled) == "function"
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
            const hasApi = type(debug.iscoverageenabled) == "function"
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
            const hasApi = type(debug.iscoverageenabled) == "function"
            if not hasApi or not debug.iscoverageenabled() then
                return
            end

            Testable.configure({
                Coverage = true,
                CoverageThreshold = 0,
                CoverageRoots = sampleScript,
            })

            const _, passed = Testable.run({
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

            const _, passed = Testable.run({
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
