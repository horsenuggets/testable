--[[

TextReporter

Formats test results as a status tree and reports failures to stdout or TestService.

--]]

const Ansi = require("../Ansi")
const Config = require("../Config")
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

const function aggregateStatus(node): string?
    if node.status then
        return node.status
    end
    local status = nil
    for _, child in node.children do
        const childStatus = aggregateStatus(child)
        if childStatus == TestEnum.TestStatus.Failure then
            return childStatus
        elseif childStatus == TestEnum.TestStatus.Success then
            status = childStatus
        elseif childStatus == TestEnum.TestStatus.Skipped and status == nil then
            status = childStatus
        end
    end
    return status
end

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

--[[
    Returns the suffix that shows why a skipped node was skipped, or an empty string for
    nodes that ran or have no reason.
]]
const function skipReasonText(node, color: boolean): string
    if node.status ~= TestEnum.TestStatus.Skipped or type(node.skipReason) ~= "string" or node.skipReason == "" then
        return ""
    end
    const text = ` ({node.skipReason})`
    return if color then Ansi.dim(text) else text
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
        )}{skipReasonText(node, options.Color)}`
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
    const skipped = formatCount(results.skippedCount, "skipped", options.Color, Ansi.brightYellow)
    table.insert(lines, `{passed}, {failed}, {skipped}.`)
    const focusSummary = TextReporter.formatFocusSummary(results.focusExcludedCount or 0)
    if focusSummary then
        table.insert(lines, if options.Color then Ansi.brightYellow(focusSummary) else focusSummary)
    end
    return lines
end

--[[
    Returns the line that says how many tests a focus modifier excluded from the run, or
    nil when focus excluded nothing.
]]
function TextReporter.formatFocusSummary(excludedCount: number): string?
    assert(type(excludedCount) == "number")
    if excludedCount <= 0 then
        return nil
    end
    return if excludedCount == 1
        then "1 test was excluded by focus."
        else `{excludedCount} tests were excluded by focus.`
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

function TextReporter.report(results)
    assert(type(results) == "table")
    for _, line in TextReporter.format(results, getOptions()) do
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
