--[[
    The TextReporter uses the results from a completed test to output text to
    standard output and TestService.
]]

local TestService = game and game:GetService("TestService")

local TestEnum = require("../TestEnum")

local INDENT = (" "):rep(3)
local ALPHABETICAL_SORT = false -- Set to true to sort tests alphabetically instead of definition order
local INDIVIDUAL_PRINTS = true -- Set to false to print all results as one big message
local STATUS_SYMBOLS = {
    [TestEnum.TestStatus.Success] = "✅",
    [TestEnum.TestStatus.Failure] = "❌",
    [TestEnum.TestStatus.Skipped] = "🕐",
}
local UNKNOWN_STATUS_SYMBOL = "?"
local PRINT_SKIPPED = false

local TextReporter = {}

local function compareNodes(a, b)
    return a.planNode.phrase:lower() < b.planNode.phrase:lower()
end

local function reportNode(node, buffer, level)
    buffer = buffer or {}
    level = level or 0

    if node.status == TestEnum.TestStatus.Skipped then
        return buffer
    end

    local line

    if node.status then
        local symbol = STATUS_SYMBOLS[node.status] or UNKNOWN_STATUS_SYMBOL

        line = ("%s[%s] %s"):format(INDENT:rep(level), symbol, node.planNode.phrase)
    else
        line = ("%s%s"):format(INDENT:rep(level), node.planNode.phrase)
    end

    table.insert(buffer, line)

    if ALPHABETICAL_SORT then
        table.sort(node.children, compareNodes)
    end

    for _, child in ipairs(node.children) do
        reportNode(child, buffer, level + 1)
    end

    return buffer
end

local function reportRoot(node)
    local buffer = {}

    if ALPHABETICAL_SORT then
        table.sort(node.children, compareNodes)
    end

    for _, child in ipairs(node.children) do
        reportNode(child, buffer, 0)
    end

    return buffer
end

local function report(root)
    local buffer = reportRoot(root)

    return buffer
end

function TextReporter.report(results)
    if INDIVIDUAL_PRINTS then
        -- Print each line separately
        print("[Testable] The tests have completed.")

        local reportBuffer = report(results)
        for _, line in ipairs(reportBuffer) do
            print(line)
        end

        print(`[{STATUS_SYMBOLS[TestEnum.TestStatus.Success]}] [PASSED] {results.successCount}`)
        print(`[{STATUS_SYMBOLS[TestEnum.TestStatus.Failure]}] [FAILED] {results.failureCount}`)
        if PRINT_SKIPPED then
            print(`[{STATUS_SYMBOLS[TestEnum.TestStatus.Skipped]}] [SKIPPED] {results.skippedCount}`)
        end
    else
        -- Print all as one big message
        local resultBuffer = {
            "[Testable] The tests have completed.",
            table.concat(report(results), "\n"),
            `[{STATUS_SYMBOLS[TestEnum.TestStatus.Success]}] [PASSED] {results.successCount}`,
            `[{STATUS_SYMBOLS[TestEnum.TestStatus.Failure]}] [FAILED] {results.failureCount}`,
            if PRINT_SKIPPED
                then `[{STATUS_SYMBOLS[TestEnum.TestStatus.Skipped]}] [SKIPPED] {results.skippedCount}`
                else nil,
        }

        print(table.concat(resultBuffer, "\n"))
    end

    if results.failureCount > 0 then
        print(("%d test nodes reported failures."):format(results.failureCount))
    end

    if #results.errors > 0 then
        print("Errors reported by tests...")
        print("")

        for _, message in ipairs(results.errors) do
            if TestService then
                TestService:Error(message)
            end

            -- Insert a blank line after each error
            print("")
        end
    end
end

return TextReporter
