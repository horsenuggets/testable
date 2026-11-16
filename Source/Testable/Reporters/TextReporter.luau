--[[

TextReporter

Formats test results as a status tree and reports failures to stdout or TestService.

--]]

const Ansi = require("../Ansi")
const Config = require("../Config")
const ResultTree = require("./ResultTree")
const TestEnum = require("../TestEnum")
const IS_LUNE = Ansi.isLune()
const SEPARATOR = string.rep("─", 64)
const STATUS_SYMBOLS = {
    [TestEnum.TestStatus.Failure] = "✗",
    [TestEnum.TestStatus.Skipped] = "○",
    [TestEnum.TestStatus.Success] = "✓",
}
const TestService = game and game:GetService("TestService")

const TextReporter = {}

export type Options = {
    AlphabeticalSort: boolean,
    Color: boolean,
    Indent: string,
    PrintSkipped: boolean,
}

const function getOptions(): Options
    return {
        AlphabeticalSort = Config.AlphabeticalSort,
        Color = IS_LUNE,
        Indent = Config.Indent,
        PrintSkipped = Config.PrintSkipped,
    }
end

const function visibleChildren(node, options: Options)
    const children = {}
    for _, child in node.children do
        if child.status ~= TestEnum.TestStatus.Skipped or options.PrintSkipped then
            table.insert(children, child)
        end
    end
    if options.AlphabeticalSort then
        table.sort(children, function(a, b)
            return a.planNode.phrase:lower() < b.planNode.phrase:lower()
        end)
    end
    return children
end

const aggregateStatus = ResultTree.status

const function statusText(status: string?, phrase: string, color: boolean): string
    if not status then
        return phrase
    end
    const text = `{STATUS_SYMBOLS[status] or "?"} {phrase}`
    if not color then
        return text
    elseif status == TestEnum.TestStatus.Success then
        return Ansi.brightGreen(text)
    elseif status == TestEnum.TestStatus.Failure then
        return Ansi.brightRed(text)
    elseif status == TestEnum.TestStatus.Skipped then
        return Ansi.brightYellow(text)
    end
    return text
end

const function appendNode(node, lines: { string }, prefix: string, isLast: boolean, options: Options)
    const branchIndent = options.Indent:gsub(" ", "─"):gsub("─$", " ")
    const connector = `{if isLast then "└" else "├"}{branchIndent}`
    const branch = `{prefix}{connector}`
    table.insert(
        lines,
        `{if options.Color then Ansi.dim(branch) else branch}{statusText(
            aggregateStatus(node),
            node.planNode.phrase,
            options.Color
        )}`
    )
    const children = visibleChildren(node, options)
    const childPrefix = `{prefix}{if isLast then " " else "│"}{options.Indent}`
    for index, child in children do
        appendNode(child, lines, childPrefix, index == #children, options)
    end
end

--[[
    Returns tree lines without changing results or emitting output.
]]
function TextReporter.formatTree(results, options: Options?): { string }
    assert(type(results) == "table")
    options = options or getOptions()
    assert(type(options) == "table")
    assert(type(options.AlphabeticalSort) == "boolean")
    assert(type(options.Color) == "boolean")
    assert(type(options.Indent) == "string")
    assert(type(options.PrintSkipped) == "boolean")
    const lines = {}
    for index, child in visibleChildren(results, options) do
        if index > 1 then
            table.insert(lines, "")
        end
        table.insert(lines, statusText(aggregateStatus(child), child.planNode.phrase, options.Color))
        const children = visibleChildren(child, options)
        for childIndex, grandchild in children do
            appendNode(grandchild, lines, "", childIndex == #children, options)
        end
    end
    return lines
end

function TextReporter.formatSeparator(color: boolean): { string }
    assert(type(color) == "boolean")
    return { "", if color then Ansi.dim(SEPARATOR) else SEPARATOR, "" }
end

const function formatCount(count: number, label: string, color: boolean, colorFn: (string) -> string): string
    const text = `{count} {label}`
    return if not color then text else if count > 0 then colorFn(text) else Ansi.dim(text)
end

--[[
    Returns the report header, tree, and summary. Errors remain separate so TestService
    receives the original diagnostic strings.
]]
function TextReporter.format(results, options: Options): { string }
    assert(type(results) == "table")
    assert(type(options) == "table")
    const lines = TextReporter.formatSeparator(options.Color)
    table.insert(lines, if options.Color then Ansi.bold("Unit Tests") else "Unit Tests")
    table.insert(lines, "")
    for _, line in TextReporter.formatTree(results, options) do
        table.insert(lines, line)
    end
    table.insert(lines, "")
    const passed = formatCount(results.successCount, "passed", options.Color, Ansi.brightGreen)
    const failed = formatCount(results.failureCount, "failed", options.Color, Ansi.brightRed)
    -- Tests excluded by Config.Filter are part of the skipped count, so call them out
    const filteredCount = results.filteredCount or 0
    const skippedLabel = if filteredCount > 0 then `skipped ({filteredCount} filtered out)` else "skipped"
    const skipped = formatCount(results.skippedCount, skippedLabel, options.Color, Ansi.brightYellow)
    table.insert(lines, `{passed}, {failed}, {skipped}.`)
    return lines
end

--[[
    Returns the "slowest tests" block, which lists up to the given number of tests that
    ran, longest first. Skipped tests are left out, ties keep their definition order, and
    the block is empty when there is nothing to list.
]]
function TextReporter.formatSlowest(results, count: number, color: boolean): { string }
    assert(type(results) == "table")
    assert(type(count) == "number" and count >= 0 and count % 1 == 0)
    assert(type(color) == "boolean")
    -- The block is off by default, so a run that doesn't want it skips the traversal.
    if count == 0 then
        return {}
    end
    const ran = {}
    for index, case in ResultTree.collectCases(results) do
        if case.Status ~= TestEnum.TestStatus.Skipped then
            table.insert(ran, { Case = case, Index = index })
        end
    end
    table.sort(ran, function(a, b)
        if a.Case.Duration ~= b.Case.Duration then
            return a.Case.Duration > b.Case.Duration
        end
        return a.Index < b.Index
    end)
    const shown = math.min(count, #ran)
    if shown == 0 then
        return {}
    end

    const durations = {}
    local width = 0
    for index = 1, shown do
        durations[index] = string.format("%.3fs", ran[index].Case.Duration)
        width = math.max(width, #durations[index])
    end
    const lines = { "", if color then Ansi.bold("Slowest Tests") else "Slowest Tests", "" }
    for index = 1, shown do
        const duration = `{string.rep(" ", width - #durations[index])}{durations[index]}`
        table.insert(lines, `{if color then Ansi.dim(duration) else duration}  {ran[index].Case.FullName}`)
    end
    return lines
end

function TextReporter.renderTree(results)
    assert(type(results) == "table")
    for _, line in TextReporter.formatTree(results, getOptions()) do
        print(line)
    end
end

function TextReporter.separator()
    for _, line in TextReporter.formatSeparator(IS_LUNE) do
        print(line)
    end
end

--[[
    Prints the report. The slowest tests block lists the given number of tests, or the
    configured number when none is given, and is left out at zero.
]]
function TextReporter.report(results, slowestTests: number?)
    assert(type(results) == "table")
    assert(slowestTests == nil or type(slowestTests) == "number")
    for _, line in TextReporter.format(results, getOptions()) do
        print(line)
    end
    for _, line in TextReporter.formatSlowest(results, slowestTests or Config.SlowestTests, IS_LUNE) do
        print(line)
    end
    if #results.errors > 0 then
        print("")
        print("Errors reported by tests...")
        print("")
        for _, message in results.errors do
            if TestService then
                TestService:Error(message)
                print("")
            else
                print(message)
            end
        end
    end
end

return TextReporter
