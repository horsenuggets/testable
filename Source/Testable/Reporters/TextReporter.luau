--[[

TextReporter

Uses the results from a completed test to output text to standard output and TestService.

--]]

local TestService = game and game:GetService("TestService")

local Ansi = require("../Ansi")
local Config = require("../Config")
local TestEnum = require("../TestEnum")
local TestResults = require("../TestResults")

local IS_LUNE = Ansi.isLune()

local STATUS_SYMBOLS = if IS_LUNE
    then {
        [TestEnum.TestStatus.Success] = "✓",
        [TestEnum.TestStatus.Failure] = "✗",
        [TestEnum.TestStatus.Skipped] = "○",
    }
    else TestResults.STATUS_SYMBOLS
local UNKNOWN_STATUS_SYMBOL = "?"

local TREE_BRANCH = "├── "
local TREE_LAST = "└── "
local TREE_PIPE = "│   "
local TREE_SPACE = "    "
local SEPARATOR = string.rep("─", 64)

local TextReporter = {}

local function compareNodes(a, b)
    return a.planNode.phrase:lower() < b.planNode.phrase:lower()
end

local function dim(text: string): string
    return if IS_LUNE then Ansi.dim(text) else text
end

local function bold(text: string): string
    return if IS_LUNE then Ansi.bold(text) else text
end

local function getVisibleChildren(node)
    local visible = {}
    for _, child in ipairs(node.children) do
        if child.status ~= TestEnum.TestStatus.Skipped or Config.PrintSkipped then
            table.insert(visible, child)
        end
    end
    if Config.AlphabeticalSort then
        table.sort(visible, compareNodes)
    end
    return visible
end

local function getStatusFromChildren(node): string?
    local hasFailure = false
    local hasSuccess = false

    for _, child in ipairs(node.children) do
        if child.status == TestEnum.TestStatus.Failure then
            hasFailure = true
        elseif child.status == TestEnum.TestStatus.Success then
            hasSuccess = true
        elseif child.status == nil and #child.children > 0 then
            local childStatus = getStatusFromChildren(child)
            if childStatus == TestEnum.TestStatus.Failure then
                hasFailure = true
            elseif childStatus == TestEnum.TestStatus.Success then
                hasSuccess = true
            end
        end
    end

    if hasFailure then
        return TestEnum.TestStatus.Failure
    elseif hasSuccess then
        return TestEnum.TestStatus.Success
    end
    return nil
end

local function formatStatusText(status: string?, phrase: string): string
    if not status then
        return phrase
    end

    local symbol = STATUS_SYMBOLS[status] or UNKNOWN_STATUS_SYMBOL
    local text = `{symbol} {phrase}`

    if IS_LUNE then
        if status == TestEnum.TestStatus.Success then
            return Ansi.brightGreen(text)
        elseif status == TestEnum.TestStatus.Failure then
            return Ansi.brightRed(text)
        elseif status == TestEnum.TestStatus.Skipped then
            return Ansi.brightYellow(text)
        end
    end

    return text
end

local function reportNode(node, buffer, prefix, isLast)
    if node.status == TestEnum.TestStatus.Skipped and not Config.PrintSkipped then
        return
    end

    local connector = if isLast then TREE_LAST else TREE_BRANCH
    local line

    if node.status then
        line = `{dim(`{prefix}{connector}`)}{formatStatusText(node.status, node.planNode.phrase)}`
    else
        local status = getStatusFromChildren(node)
        line = `{dim(`{prefix}{connector}`)}{formatStatusText(status, node.planNode.phrase)}`
    end

    table.insert(buffer, line)

    local children = getVisibleChildren(node)
    local childPrefix = prefix .. (if isLast then TREE_SPACE else TREE_PIPE)

    for i, child in ipairs(children) do
        reportNode(child, buffer, childPrefix, i == #children)
    end
end

local function buildTree(root)
    local buffer = {}
    local children = getVisibleChildren(root)

    for childIndex, child in ipairs(children) do
        if childIndex > 1 then
            table.insert(buffer, "")
        end

        -- Top-level suites get a status derived from their children
        local status = child.status or getStatusFromChildren(child)
        table.insert(buffer, formatStatusText(status, child.planNode.phrase))

        local suiteChildren = getVisibleChildren(child)
        for i, grandchild in ipairs(suiteChildren) do
            reportNode(grandchild, buffer, "", i == #suiteChildren)
        end
    end

    return buffer
end

local function formatCount(count: number, label: string, colorFn: (string) -> string): string
    local text = `{count} {label}`
    if not IS_LUNE then
        return text
    end
    return if count > 0 then colorFn(text) else Ansi.dim(text)
end

local function buildSummaryLine(results)
    local passedPart = formatCount(results.successCount, "passed", Ansi.brightGreen)
    local failedPart = formatCount(results.failureCount, "failed", Ansi.brightRed)
    local skippedPart = formatCount(results.skippedCount, "skipped", Ansi.brightYellow)
    return `{passedPart}, {failedPart}, {skippedPart}.`
end

--[[
    Renders the test result tree to stdout without the summary line. Used by
    CoverageReporter to display coverage results in the same tree style.

    @param results - A results object with children, planNode, status, etc.
]]
function TextReporter.renderTree(results)
    local buffer = buildTree(results)
    for _, line in ipairs(buffer) do
        print(line)
    end
end

local function separator()
    print("")
    print(if IS_LUNE then Ansi.dim(SEPARATOR) else SEPARATOR)
    print("")
end

function TextReporter.report(results)
    separator()

    print(bold("Unit Tests"))
    print("")

    local reportBuffer = buildTree(results)
    for _, line in ipairs(reportBuffer) do
        print(line)
    end
    print("")
    print(buildSummaryLine(results))

    if #results.errors > 0 then
        print("")
        print("Errors reported by tests...")
        print("")

        for _, message in ipairs(results.errors) do
            if TestService then
                TestService:Error(message)
                print("")
            else
                print(message)
            end
        end
    end

end

function TextReporter.separator()
    separator()
end

return TextReporter
