--[[

CoverageTest.spec

Tests for the Coverage module: resolveRoots, collect, and integration
with Config. Coverage data depends on debug.iscoverageenabled being
true, which is the default in Lune 0.10.4-horse.14.2+.

--]]

const Config = require("../Source/Testable/Config")
const Coverage = require("../Source/Testable/Coverage")
const Testable = require("../Source/Testable")
const afterEach, describe, expect, it = Testable.afterEach, Testable.describe, Testable.expect, Testable.it

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

        it("should reconstruct filesystem path roots without requiring their sources", function()
            const expected = Coverage.resolveRoots(sampleScript)
            for _, path in { "Tests/CoverageFixtures/SampleModule", "Tests/CoverageFixtures/SampleModule.luau" } do
                const resolved = Coverage.resolveRoots(path)
                expect(#resolved).to.equal(1)
                expect(resolved[1].Name).to.equal("SampleModule")
                expect(resolved[1].Script:GetFullName()).to.equal(expected[1].Script:GetFullName())
                expect(Coverage.captureRaw(path)).to.deepEqual(Coverage.captureRaw(sampleScript))
            end
            const paths = Coverage.resolveRoots({ Alias = "Tests/CoverageFixtures/SampleModule.luau" })
            expect(paths[1].Name).to.equal("Alias")
            expect(paths[1].Script:GetFullName()).to.equal(expected[1].Script:GetFullName())
            expect(#Coverage.resolveRoots("Tests/CoverageFixtures")).to.equal(#Coverage.resolveRoots(fixturesDir))
        end)

        it("should preserve filesystem roots when reconstructing coverage references", function()
            const fs = require("@lune/fs")
            const luau = require("@lune/luau")
            const source = fs.readFile(tostring(script.Parent.Parent.Source.Testable.Coverage) .. ".luau")
            for _, case in
                {
                    { "//server/share/Source/Value.luau", "/work", "//server/share/Source/Value.luau" },
                    { "\\\\server\\share\\Source\\Value.luau", "/work", "//server/share/Source/Value.luau" },
                    { "Source/Value.luau", "//server/share/work", "//server/share/work/Source/Value.luau" },
                    { "../Value.luau", "\\\\server\\share\\work", "//server/share/Value.luau" },
                    { "C:\\Source\\Value.luau", "//server/share/work", "C:/Source/Value.luau" },
                    { "/Source/Value.luau", "//server/share/work", "/Source/Value.luau" },
                }
            do
                const path, cwd, expected = case[1], case[2], case[3]
                const dependencies = {
                    ["@lune/fs"] = {
                        isDir = function()
                            return false
                        end,
                        isFile = function(candidate)
                            return candidate == expected
                        end,
                    },
                    ["@lune/process"] = { cwd = cwd },
                }
                const isolated = luau.load(source, {
                    environment = {
                        require = function(name)
                            assert(dependencies[name] ~= nil, `Unexpected coverage dependency "{name}".`)
                            return dependencies[name]
                        end,
                        script = setmetatable({}, {
                            __index = function(_, candidate)
                                return setmetatable({ Name = "Value.luau" }, {
                                    __tostring = function()
                                        return candidate
                                    end,
                                })
                            end,
                        }),
                    },
                })()
                for _, roots in { path, { Alias = path } } do
                    const resolved = isolated.resolveRoots(roots)
                    expect(#resolved).to.equal(1)
                    expect(tostring(resolved[1].Script)).to.equal(expected)
                    expect(resolved[1].Name).to.equal(if type(roots) == "string" then "Value" else "Alias")
                end
            end
        end)

        it("should reject blank filesystem coverage paths", function()
            for _, path in { "", "   " } do
                expect(pcall(Coverage.resolveRoots, path)).to.equal(false)
                expect(pcall(Coverage.resolveRoots, { Source = path })).to.equal(false)
            end
        end)

        it("should exclude .spec files", function()
            const testsDir = script.Parent
            const resolved = Coverage.resolveRoots(testsDir)
            for _, entry in resolved do
                expect(entry.Name:match("%.spec$")).to.equal(nil)
            end
        end)
    end)

    -- These tests write and remove files in the shared fixtures directory, so no other
    -- test of the run may read that directory while they do.
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
    end, { Serial = true })

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

    describe("Raw coverage transport", function()
        const function snapshot(): any
            return {
                Files = {
                    {
                        Entries = {
                            { Depth = 0, Function = "", Hits = { [0] = -1, [2] = 3, [9] = 0 }, LineDefined = 1 },
                            { Depth = 1, Function = "same", Hits = { [2] = 0, [20] = 2, [21] = -1 }, LineDefined = 20 },
                            { Depth = 2, Function = "same", Hits = { [30] = 0, [31] = -2 }, LineDefined = 30 },
                        },
                        Loaded = true,
                        Name = "Module",
                        Path = "/coverage/Module.luau",
                    },
                },
                Version = 1,
            }
        end

        const function rejects(value: any, fragment: string)
            assert(type(fragment) == "string")
            const ok, problem = pcall(Coverage.mergeRaw, value)
            expect(ok).to.equal(false)
            expect(tostring(problem):find(fragment, 1, true) ~= nil).to.equal(true)
        end

        it("should preserve sparse numeric keys, negative markers, and ordered function identities", function()
            const original = snapshot()
            const merged = Coverage.mergeRaw({ original })
            expect(merged).to.deepEqual(original)
            expect(merged.Files[1].Entries[1].Hits[1]).to.equal(nil)
            expect(merged.Files[1].Entries[1].Hits[0]).to.equal(-1)
            expect(merged.Files[1].Entries[3].Hits[31]).to.equal(-2)
        end)

        it("should take per-entry maxima without flattening overlapping lines", function()
            const first, second = snapshot(), snapshot()
            second.Files[1].Entries[1].Hits[2] = 1
            second.Files[1].Entries[1].Hits[9] = 4
            second.Files[1].Entries[2].Hits[2] = 7
            const merged = Coverage.mergeRaw({ first, second })
            expect(merged.Files[1].Entries[1].Hits[2]).to.equal(3)
            expect(merged.Files[1].Entries[2].Hits[2]).to.equal(7)
            const report = Coverage.collectRaw(merged)
            const file = report.Files[1]
            expect(file.ExecutableLines).to.equal(5)
            expect(file.HitLines).to.equal(4)
            expect(file.Percentage).to.equal(80)
            expect(file.Functions[1].Name).to.equal("(top-level)")
            expect(file.Functions[1].ExecutableLines).to.equal(2)
            expect(file.Functions[1].HitLines).to.equal(2)
            expect(file.Functions[3].HitLines).to.equal(0)
            expect(file.LineHits).to.deepEqual({ [2] = 7, [9] = 4, [20] = 2, [30] = 0 })
            expect(report.TotalExecutableLines).to.equal(5)
            expect(report.TotalHitLines).to.equal(4)
            expect(report.TotalPercentage).to.equal(80)
        end)

        it("should union unloaded and loaded files in either order", function()
            const unloaded, loaded = snapshot(), snapshot()
            unloaded.Files[1].Loaded = false
            for _, entry in unloaded.Files[1].Entries do
                for line, count in entry.Hits do
                    if count >= 0 then
                        entry.Hits[line] = 0
                    end
                end
            end
            const missed = Coverage.collectRaw(unloaded)
            expect(missed.Files[1].Loaded).to.equal(false)
            expect(missed.TotalExecutableLines).to.equal(5)
            expect(missed.TotalHitLines).to.equal(0)
            expect(missed.Files[1].LineHits).to.deepEqual({ [2] = 0, [9] = 0, [20] = 0, [30] = 0 })
            expect(Coverage.mergeRaw({ unloaded, loaded })).to.deepEqual(loaded)
            expect(Coverage.mergeRaw({ loaded, unloaded })).to.deepEqual(loaded)
        end)

        it("should union disjoint paths and be associative, idempotent, and permutation independent", function()
            const first, second, third = snapshot(), snapshot(), snapshot()
            first.Files[1].Name = "Zulu"
            second.Files[1].Name = "Alpha"
            second.Files[1].Entries[1].Hits[9] = 8
            third.Files[1].Path = "/coverage/A.luau"
            const expected = Coverage.mergeRaw({ first, second, third })
            const inputs = { first, second, third }
            for a = 1, 3 do
                for b = 1, 3 do
                    if a == b then
                        continue
                    end
                    const c = 6 - a - b
                    expect(Coverage.mergeRaw({ inputs[a], inputs[b], inputs[c] })).to.deepEqual(expected)
                end
            end
            expect(expected.Files[1].Path).to.equal("/coverage/A.luau")
            expect(expected.Files[2].Name).to.equal("Alpha")
            expect(Coverage.mergeRaw({ Coverage.mergeRaw({ first, second }), third })).to.deepEqual(expected)
            expect(Coverage.mergeRaw({ first, Coverage.mergeRaw({ second, third }) })).to.deepEqual(expected)
            expect(Coverage.mergeRaw({ expected, expected })).to.deepEqual(expected)
            expect(Coverage.collectRaw(expected).TotalExecutableLines).to.equal(10)
            expect(Coverage.mergeRaw({})).to.deepEqual({ Files = {}, Version = 1 })
            expect(Coverage.collectRaw({ Files = {}, Version = 1 }).TotalPercentage).to.equal(0)
        end)

        it("should reject function count, order, name, definition line, and depth mismatches", function()
            const changes = {
                function(file)
                    table.remove(file.Entries)
                end,
                function(file)
                    file.Entries[2], file.Entries[3] = file.Entries[3], file.Entries[2]
                end,
                function(file)
                    file.Entries[2].Function = "different"
                end,
                function(file)
                    file.Entries[2].LineDefined += 1
                end,
                function(file)
                    file.Entries[2].Depth += 1
                end,
            }
            for _, change in changes do
                const first, second = snapshot(), snapshot()
                change(second.Files[1])
                rejects({ first, second }, "layout mismatch")
                rejects({ second, first }, "layout mismatch")
            end
        end)

        it("should reject missing and extra hit keys and both executable mask directions", function()
            const changes = {
                function(hits)
                    hits[9] = nil
                end,
                function(hits)
                    hits[10] = -1
                end,
                function(hits)
                    hits[0] = 0
                end,
                function(hits)
                    hits[9] = -1
                end,
            }
            for _, change in changes do
                const first, second = snapshot(), snapshot()
                change(second.Files[1].Entries[1].Hits)
                rejects({ first, second }, "layout mismatch")
                rejects({ second, first }, "layout mismatch")
            end
        end)

        it("should preserve exact hit-key and executable-mask mismatch messages in either order", function()
            const cases = {
                { Count = false, Line = 9, Message = "Hits key set" },
                { Count = -1, Line = 10, Message = "Hits key set" },
                { Count = 0, Line = 0, Message = "Executable mask" },
                { Count = -1, Line = 9, Message = "Executable mask" },
            }
            for _, case in cases do
                const first, second = snapshot(), snapshot()
                second.Files[1].Entries[1].Hits[case.Line] = if case.Count == false then nil else case.Count
                const expected =
                    `Raw coverage layout mismatch for "/coverage/Module.luau". {case.Message} differs at entry 1, line {case.Line}.`
                for _, inputs in { { first, second }, { second, first } } do
                    const ok, problem = pcall(Coverage.mergeRaw, inputs)
                    expect(ok).to.equal(false)
                    expect(tostring(problem):sub(-#expected)).to.equal(expected)
                end
            end
        end)

        it("should merge large matching layouts without changing masks, identities, or input ownership", function()
            const first, second = snapshot(), snapshot()
            table.clear(first.Files[1].Entries)
            table.clear(second.Files[1].Entries)
            for index = 1, 8 do
                const firstHits, secondHits = {}, {}
                for line = 0, 2047 do
                    const kind = line % 4
                    firstHits[line] = if kind == 0 then -2 elseif kind == 1 then 0 else index
                    secondHits[line] = if kind == 0 then -1 elseif kind == 1 then 0 else 9 - index
                end
                for _, pair in { { Hits = firstHits, Snapshot = first }, { Hits = secondHits, Snapshot = second } } do
                    table.insert(pair.Snapshot.Files[1].Entries, {
                        Depth = index - 1,
                        Function = "same",
                        Hits = pair.Hits,
                        LineDefined = index * 10,
                    })
                end
            end
            const firstBefore = Coverage.mergeRaw({ first })
            const secondBefore = Coverage.mergeRaw({ second })
            const merged = Coverage.mergeRaw({ first, second })
            expect(Coverage.mergeRaw({ second, first })).to.deepEqual(merged)
            expect(Coverage.mergeRaw({ merged, merged })).to.deepEqual(merged)
            expect(first).to.deepEqual(firstBefore)
            expect(second).to.deepEqual(secondBefore)
            for index, entry in merged.Files[1].Entries do
                expect(entry.Depth).to.equal(index - 1)
                expect(entry.Function).to.equal("same")
                expect(entry.LineDefined).to.equal(index * 10)
                for line = 0, 2047 do
                    const kind = line % 4
                    const expected = if kind == 0 then -1 elseif kind == 1 then 0 else math.max(index, 9 - index)
                    expect(entry.Hits[line]).to.equal(expected)
                end
                entry.Hits[0] = -3
                expect(first.Files[1].Entries[index].Hits[0]).to.equal(-2)
                expect(second.Files[1].Entries[index].Hits[0]).to.equal(-1)
            end
        end)

        it("should preserve negative markers with a maximum without treating them as hits", function()
            const first, second = snapshot(), snapshot()
            second.Files[1].Entries[3].Hits[31] = -1
            const merged = Coverage.mergeRaw({ first, second })
            expect(merged.Files[1].Entries[3].Hits[31]).to.equal(-1)
            const hits = Coverage.collectRaw(merged).Files[1].LineHits
            assert(hits ~= nil)
            expect(hits[31]).to.equal(nil)
            expect(Coverage.mergeRaw({ second, first })).to.deepEqual(merged)
        end)

        it("should validate complete schemas rather than silently discard malformed input", function()
            const changes = {
                function(raw)
                    raw.Version = 2
                end,
                function(raw)
                    raw.Files = nil
                end,
                function(raw)
                    raw.Unknown = raw
                end,
                function(raw)
                    raw.Files = { [2] = raw.Files[1] }
                end,
                function(raw)
                    raw.Files.Extra = true
                end,
                function(raw)
                    table.insert(raw.Files, raw.Files[1])
                end,
                function(raw)
                    raw.Files[1].Path = "relative.luau"
                end,
                function(raw)
                    raw.Files[1].Path = "/coverage/./Module.luau"
                end,
                function(raw)
                    raw.Files[1].Name = false
                end,
                function(raw)
                    raw.Files[1].Loaded = 1
                end,
                function(raw)
                    raw.Files[1].Loaded = false
                end,
                function(raw)
                    raw.Files[1].Entries[2] = nil
                end,
                function(raw)
                    raw.Files[1].Entries[1].LineDefined = nil
                end,
                function(raw)
                    raw.Files[1].Entries[1].Depth = -1
                end,
                function(raw)
                    raw.Files[1].Entries[1].Function = function() end
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits = raw
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits["2"] = 3
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits[0.5] = 3
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits[-1] = 3
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits[2] = math.huge
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits[2] = 0 / 0
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits[2] = 1.5
                end,
                function(raw)
                    raw.Files[1].Entries[1].Hits[2] = "3"
                end,
                function(raw)
                    setmetatable(raw.Files[1], {})
                end,
            }
            for _, change in changes do
                const raw = snapshot()
                change(raw)
                expect(function()
                    Coverage.mergeRaw({ snapshot(), raw })
                end).to.throw()
                expect(function()
                    Coverage.collectRaw(raw)
                end).to.throw()
            end
            rejects(nil, "Expected an array")
            rejects({ [2] = snapshot() }, "hole")
            rejects({ false }, "Expected a plain table")
        end)

        it("should not change inputs on success or on a mismatch late in the batch", function()
            const first, second, invalid = snapshot(), snapshot(), snapshot()
            second.Files[1].Entries[1].Hits[9] = 8
            invalid.Files[1].Path = "/coverage/Z.luau"
            const invalidOther = snapshot()
            invalidOther.Files[1].Path = invalid.Files[1].Path
            invalidOther.Files[1].Entries[2].Depth += 1
            rejects({ first, second, invalid, invalidOther }, "layout mismatch")
            expect(first).to.deepEqual(snapshot())
            Coverage.mergeRaw({ first, second })
            expect(first).to.deepEqual(snapshot())
            expect(second.Files[1].Entries[1].Hits[9]).to.equal(8)
        end)

        it("should own merged and reported data independently of every caller table", function()
            const input = snapshot()
            const merged = Coverage.mergeRaw({ input })
            const report = Coverage.collectRaw(merged)
            input.Files[1].Entries[1].Hits[2] = 999
            input.Files[1].Entries[1].Function = "changed"
            input.Files[1].Name = "Changed"
            table.clear(input.Files)
            expect(merged).to.deepEqual(snapshot())
            merged.Files[1].Entries[1].Hits[2] = 777
            expect(report.Files[1].LineHits[2]).to.equal(3)
            report.Files[1].LineHits[2] = 555
            expect(merged.Files[1].Entries[1].Hits[2]).to.equal(777)
            expect(Coverage.mergeRaw({ snapshot() })).to.deepEqual(snapshot())
        end)

        it("should report loaded raw data without access to its source or coverage runtime", function()
            const raw = snapshot()
            raw.Files[1].Path = "/nonexistent/raw-coverage-source.luau"
            const report = Coverage.collectRaw(raw)
            expect(report.Files[1].Loaded).to.equal(true)
            expect(report.Files[1].Path).to.equal(raw.Files[1].Path)
            expect(report.TotalExecutableLines).to.equal(5)
            expect(report.TotalHitLines).to.equal(2)
        end)
    end)

    describe("Coverage.captureRaw", function()
        it("should deduplicate extension aliases after resolving the actual source filename", function()
            if not debug.iscoverageenabled() then
                return
            end
            const expected = Coverage.captureRaw({ A = sampleScript })
            const raw = Coverage.captureRaw({
                A = "Tests/CoverageFixtures/SampleModule",
                B = "Tests/CoverageFixtures/SampleModule.luau",
            })
            expect(raw).to.deepEqual(expected)
        end)

        it("should combine overlapping directory and file roots without losing loaded entries", function()
            if not debug.iscoverageenabled() then
                return
            end
            const directory = Coverage.captureRaw(fixturesDir)
            const sample = Coverage.captureRaw(sampleScript)
            const raw = Coverage.captureRaw({
                All = "Tests/CoverageFixtures",
                One = "Tests/CoverageFixtures/SampleModule.luau",
            })
            assert(raw ~= nil and directory ~= nil and sample ~= nil)
            expect(#raw.Files).to.equal(#directory.Files)
            const seen = {}
            local found = false
            for _, file in ipairs(raw.Files) do
                expect(seen[file.Path]).to.equal(nil)
                seen[file.Path] = true
                if file.Path == sample.Files[1].Path then
                    found = true
                    expect(file.Name).to.equal("One")
                    expect(file.Loaded).to.equal(true)
                    expect(file.Entries).to.deepEqual(sample.Files[1].Entries)
                end
            end
            expect(found).to.equal(true)
        end)

        it("should still reject duplicate physical paths inside imported raw snapshots", function()
            const raw = Coverage.captureRaw(sampleScript)
            if raw == nil then
                return
            end
            table.insert(raw.Files, table.clone(raw.Files[1]))
            expect(pcall(Coverage.mergeRaw, { raw })).to.equal(false)
            expect(pcall(Coverage.collectRaw, raw)).to.equal(false)
        end)

        it("should preserve actual loaded entries without reconstructing function layouts", function()
            if not debug.iscoverageenabled() then
                expect(Coverage.captureRaw(sampleScript)).to.equal(nil)
                return
            end
            const raw = Coverage.captureRaw(sampleScript)
            assert(raw ~= nil)
            expect(raw.Version).to.equal(1)
            expect(raw.Files[1].Entries).to.deepEqual(debug.getcoverage(sampleScript))
            expect(raw.Files[1].Loaded).to.equal(true)
            expect(raw.Files[1].Path).to.equal(Coverage.normalizePath("Tests/CoverageFixtures/SampleModule.luau"))
            expect(Coverage.collectRaw(raw)).to.deepEqual(Coverage.collect(sampleScript))
            raw.Files[1].Entries[1].Hits[1] = 999
            const fresh = Coverage.captureRaw(sampleScript)
            assert(fresh ~= nil)
            expect(fresh.Files[1].Entries[1].Hits[1] == 999).to.equal(false)
        end)

        it("should retain unloaded source layouts, zero hits, and exclusions", function()
            const raw = Coverage.captureRaw(fixturesDir)
            if raw == nil then
                return
            end
            local found = false
            for _, file in raw.Files do
                expect(file.Name:match("%.spec$")).to.equal(nil)
                if file.Name == "UnrequiredModule" then
                    found = true
                    expect(file.Loaded).to.equal(false)
                    expect(#file.Entries > 0).to.equal(true)
                    for _, entry in file.Entries do
                        for _, count in entry.Hits do
                            expect(count <= 0).to.equal(true)
                        end
                    end
                end
            end
            expect(found).to.equal(true)
            const specs = Coverage.captureRaw(script)
            assert(specs ~= nil)
            expect(#specs.Files).to.equal(0)
        end)

        it("should retain tracked loaded entries even when on-disk source no longer compiles", function()
            if not debug.iscoverageenabled() then
                return
            end
            const fs = require("@lune/fs")
            const luau = require("@lune/luau")
            const path = `{tostring(fixturesDir)}/GeneratedRawTracked.luau`
            const source = "return function() return 42 end"
            fs.writeFile(path, source)
            const ok, problem = pcall(function()
                const unloaded = Coverage.captureRaw(fixturesDir.GeneratedRawTracked)
                assert(unloaded ~= nil)
                expect(unloaded.Files[1].Loaded).to.equal(false)
                const chunk = luau.load(source, { debugName = path })
                chunk()()
                Coverage.track(path, chunk)
                fs.writeFile(path, "return function(\n")
                const raw = Coverage.captureRaw(fixturesDir.GeneratedRawTracked)
                assert(raw ~= nil)
                expect(raw.Files[1].Loaded).to.equal(true)
                expect(raw.Files[1].Entries).to.deepEqual(debug.getcoverage(chunk))
                expect(Coverage.collectRaw(raw).TotalHitLines > 0).to.equal(true)
                expect(Coverage.mergeRaw({ unloaded, raw })).to.deepEqual(raw)
                expect(Coverage.mergeRaw({ raw, unloaded })).to.deepEqual(raw)
                const alternate = luau.load("return 7", { debugName = path })
                Coverage.track(path, alternate)
                const accepted, mismatch = pcall(Coverage.captureRaw, fixturesDir.GeneratedRawTracked)
                expect(accepted).to.equal(false)
                expect(tostring(mismatch):find("layout mismatch", 1, true) ~= nil).to.equal(true)
            end)
            fs.removeFile(path)
            assert(ok, problem)
        end)

        it("should never retain imported coverage between independent collections", function()
            const before = Coverage.captureRaw(sampleScript)
            if before == nil then
                return
            end
            const imported = Coverage.mergeRaw({ before })
            for _, entry in imported.Files[1].Entries do
                for line, count in entry.Hits do
                    if count >= 0 then
                        entry.Hits[line] = 999
                    end
                end
            end
            Coverage.collectRaw(Coverage.mergeRaw({ before, imported }))
            expect(Coverage.captureRaw(sampleScript)).to.deepEqual(before)
        end)
    end, { Serial = true })

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

        it("should enable Coverage only when runtime coverage is available", function()
            const available = type(debug.iscoverageenabled) == "function" and debug.iscoverageenabled()
            const ok = pcall(Config.set, { Coverage = true })
            expect(ok).to.equal(available)
            expect(Config.Coverage).to.equal(available)
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
            const available = type(debug.iscoverageenabled) == "function" and debug.iscoverageenabled()
            Config.set({ Coverage = available })
            Config.set({ CoverageThreshold = 90 })
            Config.set({ CoverageRoots = script })
            Config.reset()
            expect(Config.Coverage).to.equal(false)
            expect(Config.CoverageRoots).to.equal(nil)
            expect(Config.CoverageThreshold).to.equal(0)
        end)
    end, { Serial = true })

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
    end, { Serial = true })
end
