--[[

ReporterTest.spec

Regression tests for pure test-tree and coverage-table formatting.

--]]

const Ansi = require("../Source/Testable/Ansi")
const Config = require("../Source/Testable/Config")
const CoverageReporter = require("../Source/Testable/Reporters/CoverageReporter")
const DisplayWidth = require("../Source/Testable/DisplayWidth")
const TableRenderer = require("../Source/Testable/TableRenderer")
const TestEnum = require("../Source/Testable/TestEnum")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")
const FAILURE = TestEnum.TestStatus.Failure
const SKIPPED = TestEnum.TestStatus.Skipped
const SUCCESS = TestEnum.TestStatus.Success

const function node(phrase: string, status: string?, children: { any }?): any
    return { children = children or {}, planNode = { phrase = phrase }, status = status }
end

const function options(color: boolean?, skipped: boolean?, sort: boolean?): TextReporter.Options
    return { AlphabeticalSort = sort == true, Color = color == true, Indent = "   ", PrintSkipped = skipped == true }
end

const function strip(text: string): string
    return (text:gsub("\27%[[%d;]*m", ""))
end

const function coverage(path: string, value: number): any
    return {
        Files = {
            { ExecutableLines = 11, Functions = {}, HitLines = 10, Name = "Session", Path = path, Percentage = value },
        },
        TotalExecutableLines = 11,
        TotalHitLines = 10,
        TotalPercentage = value,
    }
end

return function()
    it("renders nested suites and connectors exactly", function()
        const root = node("Root", nil, {
            node("Guild", nil, {
                node("Joining", nil, { node("joins", SUCCESS), node("rejects full", SUCCESS) }),
                node("Leaving", nil, { node("removes", SUCCESS), node("transfers", FAILURE) }),
            }),
            node("Party", nil, { node("queues", SUCCESS) }),
        })
        const expected = {
            "✗ Guild",
            "├── ✓ Joining",
            "│   ├── ✓ joins",
            "│   └── ✓ rejects full",
            "└── ✗ Leaving",
            "    ├── ✓ removes",
            "    └── ✗ transfers",
            "",
            "✓ Party",
            "└── ✓ queues",
        }
        expect(table.concat(TextReporter.formatTree(root, options()), "\n")).to.equal(table.concat(expected, "\n"))
    end)

    it("uses configured indentation for branches and continuation prefixes", function()
        const root = node("Root", nil, {
            node("Suite", nil, {
                node("First", nil, { node("nested", SUCCESS) }),
                node("Last", nil, { node("nested", SUCCESS) }),
            }),
        })
        const previous = Config.Indent
        const ok, message = pcall(function()
            for _, indent in { "\t", "  ", "" } do
                Config.set({ Indent = indent })
                const branch = if indent == "  " then "─ " else indent
                const expected = table.concat({
                    "✓ Suite",
                    `├{branch}✓ First`,
                    `│{indent}└{branch}✓ nested`,
                    `└{branch}✓ Last`,
                    ` {indent}└{branch}✓ nested`,
                }, "\n")
                expect(strip(table.concat(TextReporter.formatTree(root), "\n"))).to.equal(expected)
                const explicit = options()
                explicit.Indent = indent
                expect(table.concat(TextReporter.formatTree(root, explicit), "\n")).to.equal(expected)
                for _, value in { 69.9, 70 } do
                    const report = coverage("Source/Session.luau", value)
                    const symbol = if value >= 70 then "✓" else "✗"
                    const outcome = if value >= 70 then "meets" else "is below"
                    const expectedCoverage = `{symbol} Code Coverage\n└{branch}{symbol} Coverage {string.format(
                        "%.1f",
                        value
                    )}% {outcome} threshold of 70.0%.`
                    const plain = table.concat(CoverageReporter.format(report, 70, false, Config.Indent), "\n")
                    expect(plain:find(expectedCoverage, 1, true) ~= nil).to.equal(true)
                    expect(strip(table.concat(CoverageReporter.format(report, 70, true, Config.Indent), "\n"))).to.equal(
                        plain
                    )
                end
            end
        end)
        Config.set({ Indent = previous })
        assert(ok, message)
    end)

    it("aggregates every combination of child outcomes", function()
        const statuses = { SUCCESS, FAILURE, SKIPPED }
        for _, first in statuses do
            for _, second in statuses do
                const root = node(
                    "Root",
                    nil,
                    { node("Suite", nil, { node("A", first), node("Nested", nil, { node("B", second) }) }) }
                )
                const expected = if first == FAILURE or second == FAILURE
                    then "✗"
                    else if first == SUCCESS or second == SUCCESS then "✓" else "○"
                expect(TextReporter.formatTree(root, options(false, true))[1]).to.equal(`{expected} Suite`)
            end
        end
    end)

    it("filters skipped children before choosing the last connector", function()
        const root = node("Root", nil, { node("Suite", nil, { node("runs", SUCCESS), node("skips", SKIPPED) }) })
        expect(table.concat(TextReporter.formatTree(root, options()), "\n")).to.equal("✓ Suite\n└── ✓ runs")
        expect(table.concat(TextReporter.formatTree(root, options(false, true)), "\n")).to.equal(
            "✓ Suite\n├── ✓ runs\n└── ○ skips"
        )
    end)

    it("hides explicitly skipped suites and preserves unknown and empty statuses", function()
        const root = node("Root", nil, { node("Hidden", SKIPPED), node("Empty"), node("Unknown", "other") })
        expect(table.concat(TextReporter.formatTree(root, options()), "\n")).to.equal("Empty\n\n? Unknown")
    end)

    it("sorts without mutating the original result tree", function()
        const children = { node("zebra", SUCCESS), node("Alpha", SUCCESS) }
        const root = node("Root", nil, { node("Z", nil, children), node("A", SUCCESS) })
        const before = table.concat(TextReporter.formatTree(root, options()), "\n")
        const sorted = table.concat(TextReporter.formatTree(root, options(false, false, true)), "\n")
        expect(sorted).to.equal("✓ A\n\n✓ Z\n├── ✓ Alpha\n└── ✓ zebra")
        expect(table.concat(TextReporter.formatTree(root, options()), "\n")).to.equal(before)
        expect(children[1].planNode.phrase).to.equal("zebra")
    end)

    it("renders a heading and all summary counts including zero skipped", function()
        const results = { children = {}, errors = {}, failureCount = 1, skippedCount = 0, successCount = 22 }
        const plain = table.concat(TextReporter.format(results, options()), "\n")
        expect(plain:find("Unit Tests", 1, true) ~= nil).to.equal(true)
        expect(plain:find("22 passed, 1 failed, 0 skipped.", 1, true) ~= nil).to.equal(true)
        expect(strip(table.concat(TextReporter.format(results, options(true)), "\n"))).to.equal(plain)
        expect(table.concat(TextReporter.format(results, options()), "\n")).to.equal(plain)
    end)

    it("keeps plain and ANSI trees equivalent", function()
        const root = node(
            "Root",
            nil,
            { node("Suite", nil, { node("fails", FAILURE), node("passes", SUCCESS), node("skips", SKIPPED) }) }
        )
        const colored = table.concat(TextReporter.formatTree(root, options(true, true)), "\n")
        expect(colored:find("\27[", 1, true) ~= nil).to.equal(true)
        expect(strip(colored)).to.equal(table.concat(TextReporter.formatTree(root, options(false, true)), "\n"))
        expect(Ansi.boldInline("90.0%")).to.equal("\27[1m90.0%\27[22m")
    end)

    it("aligns table columns independently of ANSI byte lengths", function()
        const rows = {
            { Colored = { Ansi.brightGreen("é"), "10" }, Raw = { "é", "10" } },
            { Colored = { Ansi.bold("Total"), "11" }, Raw = { "Total", "11" }, Separator = true },
        }
        const plain = TableRenderer.format({ "Name", "Hit" }, rows, false)
        const styled = TableRenderer.format({ "Name", "Hit" }, rows, true)
        expect(strip(table.concat(styled, "\n"))).to.equal(table.concat(plain, "\n"))
        for _, line in plain do
            expect(utf8.len(line)).to.equal(utf8.len(plain[1]))
        end
        expect(plain[5]:sub(1, #"├")).to.equal("├")
    end)

    it("aligns wide and combining filenames by terminal columns", function()
        const names = { "界.luau", "e\u{0301}.luau", "Ｚ.luau", "é.luau" }
        const expectedWidths = { 7, 6, 7, 6 }
        const rows = {}
        for index, name in names do
            expect(DisplayWidth.measure(name)).to.equal(expectedWidths[index])
            table.insert(rows, { Colored = { Ansi.brightGreen(name), "1" }, Raw = { name, "1" } })
        end
        const lines = TableRenderer.format({ "Script", "Hit" }, rows, false)
        expect(lines[4]).to.equal("│ 界.luau │ 1   │")
        expect(lines[5]).to.equal("│ e\u{0301}.luau  │ 1   │")
        for _, line in lines do
            expect(DisplayWidth.measure(line)).to.equal(DisplayWidth.measure(lines[1]))
        end
        const styled = TableRenderer.format({ "Script", "Hit" }, rows, true)
        expect(strip(table.concat(styled, "\n"))).to.equal(table.concat(lines, "\n"))
    end)

    it("measures Unicode width boundaries consistently", function()
        for _, codepoint in { 0x02FF, 0x0370, 0x115F, 0x1160, 0x11FF, 0x1200, 0x303F, 0xFF60, 0xFF61 } do
            const expected = if codepoint == 0x1160 or codepoint == 0x11FF
                then 0
                else if codepoint == 0x115F or codepoint == 0xFF60 then 2 else 1
            expect(DisplayWidth.measure(utf8.char(codepoint))).to.equal(expected)
        end
        expect(DisplayWidth.measure("\u{0300}\u{036F}\u{200D}")).to.equal(0)
        expect(DisplayWidth.measure("ASCII")).to.equal(5)
    end)

    it("renders empty tables with a header and closing border", function()
        const lines = TableRenderer.format({ "Script" }, {}, false)
        expect(#lines).to.equal(4)
        expect(lines[4]).to.equal("└────────┘")
    end)

    it("renders one-decimal percentages and exact threshold outcomes", function()
        for _, value in { 69.9, 70, 90.9 } do
            const report = coverage("Source/Session.luau", value)
            const plain = table.concat(CoverageReporter.format(report, 70, false, "   "), "\n")
            const expected = if value >= 70
                then `✓ Code Coverage\n└── ✓ Coverage {string.format("%.1f", value)}% meets threshold of 70.0%.`
                else `✗ Code Coverage\n└── ✗ Coverage 69.9% is below threshold of 70.0%.`
            expect(plain:find(expected, 1, true) ~= nil).to.equal(true)
            expect(plain:find("Executable Lines", 1, true) ~= nil).to.equal(true)
            expect(strip(table.concat(CoverageReporter.format(report, 70, true, "   "), "\n"))).to.equal(plain)
        end
    end)

    it("truncates coverage paths by display width rather than codepoint count", function()
        const widePath = `Source/{string.rep("界", 15)}/init.luau`
        const wide = table.concat(CoverageReporter.format(coverage(widePath, 100), 70, false, "   "), "\n")
        expect(wide:find(".../init.luau", 1, true) ~= nil).to.equal(true)
        const combiningPath = `Source/{string.rep("e\u{0301}", 16)}/init.luau`
        const combining = table.concat(CoverageReporter.format(coverage(combiningPath, 100), 70, false, "   "), "\n")
        expect(combining:find(combiningPath, 1, true) ~= nil).to.equal(true)
    end)

    it("truncates paths at folder boundaries", function()
        for _, path in
            {
                "Source/VeryLongDirectoryName/LobbySystems/ShopSystem/init.luau",
                "C:\\Source\\VeryLongDirectoryName\\LobbySystems\\ShopSystem\\init.luau",
            }
        do
            const text = table.concat(CoverageReporter.format(coverage(path, 100), 70, false, "   "), "\n")
            expect(text:find(".../LobbySystems/ShopSystem/init.luau", 1, true) ~= nil).to.equal(true)
        end
    end)

    it("keeps the end of a file name that can't fit on its own", function()
        const filename = `{string.rep("a", 50)}_Tail.luau`
        const shown = CoverageReporter.formatPath(`Source/{filename}`, false)
        expect(shown).to.equal(`...{string.sub(filename, -37)}`)
        expect(#shown).to.equal(40)
        const wide = CoverageReporter.formatPath(`Source/{string.rep("界", 30)}.luau`, false)
        expect(wide).to.equal(`...{string.rep("界", 16)}.luau`)
        expect(DisplayWidth.measure(wide) <= 40).to.equal(true)
    end)

    it("leaves short paths untouched and dims only their folders", function()
        expect(CoverageReporter.formatPath("Source/Session.luau", false)).to.equal("Source/Session.luau")
        const colored, raw = CoverageReporter.formatPath("Source/Session.luau", true)
        expect(colored).to.equal(`{Ansi.dim("Source/")}Session.luau`)
        expect(raw).to.equal("Source/Session.luau")
    end)

    it("never shows a path wider than 40 columns", function()
        for folderLength = 1, 45, 4 do
            for nameLength = 1, 60, 3 do
                for depth = 1, 4 do
                    const folders = table.create(depth, string.rep("d", folderLength))
                    const path = `{table.concat(folders, "/")}/{string.rep("n", nameLength)}.luau`
                    const _, raw = CoverageReporter.formatPath(path, false)
                    expect(DisplayWidth.measure(raw) <= 40).to.equal(true)
                    if DisplayWidth.measure(path) <= 40 then
                        expect(raw).to.equal(path)
                    else
                        expect(raw:sub(1, 3)).to.equal("...")
                    end
                end
            end
        end
    end)

    it("formats counts with comma thousands separators", function()
        const cases = {
            { 0, "0" },
            { 999, "999" },
            { 1000, "1,000" },
            { 543126, "543,126" },
            { 1234567, "1,234,567" },
        }
        for _, case in cases do
            expect(CoverageReporter.formatCount(case[1])).to.equal(case[2])
        end
    end)

    it("formats percentages with two decimals only below one percent", function()
        const cases = {
            { 0, "0.0%" },
            { 0.08, "0.08%" },
            { 0.57, "0.57%" },
            { 0.29, "0.29%" },
            { 0.999, "0.99%" },
            { 1, "1.0%" },
            { 88.36, "88.3%" },
            { 100, "100.0%" },
        }
        for _, case in cases do
            expect(CoverageReporter.formatPercentage(case[1])).to.equal(case[2])
        end
        for hundredths = 1, 99 do
            expect(CoverageReporter.formatPercentage(hundredths / 100)).to.equal(
                `0.{string.format("%02d", hundredths)}%`
            )
        end
        for tenths = 10, 1000 do
            expect(CoverageReporter.formatPercentage(tenths / 10)).to.equal(`{string.format("%.1f", tenths / 10)}%`)
        end
    end)

    it("sorts files by percentage, then lines, then path, without empty files", function()
        const function file(path: string, executable: number, hit: number): any
            return {
                ExecutableLines = executable,
                Functions = {},
                HitLines = hit,
                Loaded = hit > 0,
                Name = path,
                Path = path,
                Percentage = if executable > 0 then math.floor(hit / executable * 10000) / 100 else 0,
            }
        end
        const files = {
            file("B.luau", 100, 0),
            file("Empty.luau", 0, 0),
            file("Full.luau", 10, 10),
            file("A.luau", 100, 0),
            file("Big.luau", 3000, 0),
            file("Half.luau", 10, 5),
        }
        const order = {}
        for _, entry in CoverageReporter.sortFiles(files) do
            table.insert(order, entry.Path)
        end
        expect(table.concat(order, ",")).to.equal("Full.luau,Half.luau,Big.luau,A.luau,B.luau")
        expect(files[1].Path).to.equal("B.luau")
        expect(#files).to.equal(6)
        const again = {}
        for _, entry in CoverageReporter.sortFiles(files) do
            table.insert(again, entry.Path)
        end
        expect(table.concat(again, ",")).to.equal(table.concat(order, ","))
    end)

    it("folds rows past the limit into a summary row", function()
        for _, count in { 0, 1, 20, 21, 22, 45 } do
            const files = {}
            for index = 1, count do
                table.insert(files, {
                    ExecutableLines = 1000 + index,
                    Functions = {},
                    HitLines = 0,
                    Loaded = false,
                    Name = `M{index}`,
                    Path = `Source/M{index}.luau`,
                    Percentage = 0,
                })
            end
            const report = { Files = files, TotalExecutableLines = 0, TotalHitLines = 0, TotalPercentage = 0 }
            const text = table.concat(CoverageReporter.format(report, 0, false, "   "), "\n")
            const listed = select(2, text:gsub("Source/M%d+%.luau", ""))
            expect(listed).to.equal(math.min(count, 20))
            const hidden = count - 20
            if hidden <= 0 then
                expect(text:find("more module", 1, true)).to.equal(nil)
            else
                local hiddenLines = 0
                for index = 1, hidden do
                    hiddenLines += 1000 + index
                end
                const lines = CoverageReporter.formatCount(hiddenLines)
                const label = `{hidden} more {if hidden == 1 then "module" else "modules"}`
                expect(text:find(`│ {label} +│ +{lines} │ +0 │ +0%.0%% │`) ~= nil).to.equal(true)
            end
            expect(strip(table.concat(CoverageReporter.format(report, 0, true, "   "), "\n"))).to.equal(text)
        end
    end)

    it("right-aligns columns when asked", function()
        const rows = { { Colored = { "a", "1" }, Raw = { "a", "1" } } }
        const lines = TableRenderer.format({ "Name", "Count" }, rows, false, { "Left", "Right" })
        expect(lines[2]).to.equal("│ Name │ Count │")
        expect(lines[4]).to.equal("│ a    │     1 │")
    end)
end
