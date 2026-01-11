--[[

TextReporter

Uses the results from a completed test to output text to standard output and TestService.

--]]

local TestService = game and game:GetService("TestService")

local Ansi = require("../Ansi")
local TestEnum = require("../TestEnum")

local INDENT = (" "):rep(3)
local ALPHABETICAL_SORT = false -- Set to true to sort tests alphabetically instead of definition order
local INDIVIDUAL_PRINTS = true -- Set to false to print all results as one big message
local PRINT_SKIPPED = false

local IS_LUNE = Ansi.isLune()

local STATUS_SYMBOLS = if IS_LUNE
    then {
        [TestEnum.TestStatus.Success] = "+",
        [TestEnum.TestStatus.Failure] = "-",
        [TestEnum.TestStatus.Skipped] = "~",
    }
    else {
        [TestEnum.TestStatus.Success] = "✅",
        [TestEnum.TestStatus.Failure] = "❌",
        [TestEnum.TestStatus.Skipped] = "🕐",
    }
local UNKNOWN_STATUS_SYMBOL = "?"

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
        local indent = INDENT:rep(level)
        local fullLine = `[{symbol}] {node.planNode.phrase}`

        -- Apply ANSI colors in Lune environment
        if IS_LUNE then
            if node.status == TestEnum.TestStatus.Success then
                line = indent .. Ansi.brightGreen(fullLine)
            elseif node.status == TestEnum.TestStatus.Failure then
                line = indent .. Ansi.brightRed(fullLine)
            elseif node.status == TestEnum.TestStatus.Skipped then
                line = indent .. Ansi.brightYellow(fullLine)
            else
                line = indent .. fullLine
            end
        else
            line = indent .. fullLine
        end
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
        print("The tests have completed.")

        local reportBuffer = report(results)
        for _, line in ipairs(reportBuffer) do
            print(line)
        end

        local summaryLine
        if IS_LUNE then
            local passedPart = Ansi.brightGreen(`{results.successCount} passed`)
            local failedPart = Ansi.brightRed(`{results.failureCount} failed`)
            if PRINT_SKIPPED and results.skippedCount > 0 then
                local skippedPart = Ansi.brightYellow(`{results.skippedCount} skipped`)
                summaryLine = passedPart .. ", " .. failedPart .. ", " .. skippedPart .. "."
            else
                summaryLine = passedPart .. ", " .. failedPart .. "."
            end
        else
            if PRINT_SKIPPED and results.skippedCount > 0 then
                summaryLine =
                    `{results.successCount} passed, {results.failureCount} failed, {results.skippedCount} skipped.`
            else
                summaryLine = `{results.successCount} passed, {results.failureCount} failed.`
            end
        end
        print(summaryLine)
    else
        -- Print all as one big message
        local summaryLine
        if IS_LUNE then
            local passedPart = Ansi.brightGreen(`{results.successCount} passed`)
            local failedPart = Ansi.brightRed(`{results.failureCount} failed`)
            if PRINT_SKIPPED and results.skippedCount > 0 then
                local skippedPart = Ansi.brightYellow(`{results.skippedCount} skipped`)
                summaryLine = passedPart .. ", " .. failedPart .. ", " .. skippedPart .. "."
            else
                summaryLine = passedPart .. ", " .. failedPart .. "."
            end
        else
            if PRINT_SKIPPED and results.skippedCount > 0 then
                summaryLine =
                    `{results.successCount} passed, {results.failureCount} failed, {results.skippedCount} skipped.`
            else
                summaryLine = `{results.successCount} passed, {results.failureCount} failed.`
            end
        end

        local resultBuffer = {
            "The tests have completed.",
            table.concat(report(results), "\n"),
            summaryLine,
        }

        print(table.concat(resultBuffer, "\n"))
    end

    if #results.errors > 0 then
        print("Errors reported by tests...\n")

        for _, message in ipairs(results.errors) do
            if TestService then
                TestService:Error(message)

                -- Insert a blank line after each error
                print("")
            else
                print(message)
            end
        end
    end
end

return TextReporter
