--[[

ReporterTest.spec

Regression tests for pure test-tree and coverage-table formatting.

--]]

const Ansi = require("../Source/Testable/Ansi")
const CoverageReporter = require("../Source/Testable/Reporters/CoverageReporter")
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
    return { AlphabeticalSort = sort == true, Color = color == true, PrintSkipped = skipped == true }
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

    it("renders empty tables with a header and closing border", function()
        const lines = TableRenderer.format({ "Script" }, {}, false)
        expect(#lines).to.equal(4)
        expect(lines[4]).to.equal("└────────┘")
    end)

    it("renders one-decimal percentages and exact threshold outcomes", function()
        for _, value in { 69.9, 70, 90.9 } do
            const report = coverage("Source/Session.luau", value)
            const plain = table.concat(CoverageReporter.format(report, 70, false), "\n")
            const expected = if value >= 70
                then `✓ Code Coverage\n└── ✓ Coverage {string.format("%.1f", value)}% meets threshold of 70.0%.`
                else `✗ Code Coverage\n└── ✗ Coverage 69.9% is below threshold of 70.0%.`
            expect(plain:find(expected, 1, true) ~= nil).to.equal(true)
            expect(plain:find("Executable Lines", 1, true) ~= nil).to.equal(true)
            expect(strip(table.concat(CoverageReporter.format(report, 70, true), "\n"))).to.equal(plain)
        end
    end)

    it("truncates paths only at folder boundaries and preserves long filenames", function()
        for _, path in
            {
                "Source/VeryLongDirectoryName/LobbySystems/ShopSystem/init.luau",
                "C:\\Source\\VeryLongDirectoryName\\LobbySystems\\ShopSystem\\init.luau",
            }
        do
            const text = table.concat(CoverageReporter.format(coverage(path, 100), 70, false), "\n")
            expect(text:find(".../LobbySystems/ShopSystem/init.luau", 1, true) ~= nil).to.equal(true)
        end
        const filename = string.rep("a", 50) .. ".luau"
        const text = table.concat(CoverageReporter.format(coverage(`Source/{filename}`, 0), 70, false), "\n")
        expect(text:find(`.../{filename}`, 1, true) ~= nil).to.equal(true)
    end)
end
