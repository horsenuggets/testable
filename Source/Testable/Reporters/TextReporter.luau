--[[

TextReporter

Uses the results from a completed test to output text to standard output and TestService.

--]]

const TestService = game and game:GetService("TestService")

const Ansi = require("../Ansi")
const Config = require("../Config")
const TestEnum = require("../TestEnum")
const TestResults = require("../TestResults")

const INDIVIDUAL_PRINTS = true

const IS_LUNE = Ansi.isLune()

const STATUS_SYMBOLS = if IS_LUNE
    then {
        [TestEnum.TestStatus.Success] = "+",
        [TestEnum.TestStatus.Failure] = "-",
        [TestEnum.TestStatus.Skipped] = "~",
    }
    else TestResults.STATUS_SYMBOLS
const UNKNOWN_STATUS_SYMBOL = "?"

const TextReporter = {}

const function compareNodes(a, b)
    return a.planNode.phrase:lower() < b.planNode.phrase:lower()
end

const function reportNode(node, buffer, level)
    buffer = buffer or {}
    level = level or 0

    if node.status == TestEnum.TestStatus.Skipped then
        return buffer
    end

    local line

    if node.status then
        const symbol = STATUS_SYMBOLS[node.status] or UNKNOWN_STATUS_SYMBOL
        const indent = Config.Indent:rep(level)
        const fullLine = `[{symbol}] {node.planNode.phrase}`

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
        line = ("%s%s"):format(Config.Indent:rep(level), node.planNode.phrase)
    end

    table.insert(buffer, line)

    if Config.AlphabeticalSort then
        table.sort(node.children, compareNodes)
    end

    for _, child in ipairs(node.children) do
        reportNode(child, buffer, level + 1)
    end

    return buffer
end

const function reportRoot(node)
    const buffer = {}

    if Config.AlphabeticalSort then
        table.sort(node.children, compareNodes)
    end

    for _, child in ipairs(node.children) do
        reportNode(child, buffer, 0)
    end

    return buffer
end

const function report(root)
    const buffer = reportRoot(root)

    return buffer
end

const function buildSummaryLine(results)
    if IS_LUNE then
        const passedPart = Ansi.brightGreen(`{results.successCount} passed`)
        const failedPart = Ansi.brightRed(`{results.failureCount} failed`)
        if Config.PrintSkipped and results.skippedCount > 0 then
            const skippedPart = Ansi.brightYellow(`{results.skippedCount} skipped`)
            return passedPart .. ", " .. failedPart .. ", " .. skippedPart .. "."
        else
            return passedPart .. ", " .. failedPart .. "."
        end
    else
        if Config.PrintSkipped and results.skippedCount > 0 then
            return `{results.successCount} passed, {results.failureCount} failed, {results.skippedCount} skipped.`
        else
            return `{results.successCount} passed, {results.failureCount} failed.`
        end
    end
end

function TextReporter.report(results)
    if INDIVIDUAL_PRINTS then
        -- Print each line separately
        print("The tests have completed.")

        const reportBuffer = report(results)
        for _, line in ipairs(reportBuffer) do
            print(line)
        end

        print(buildSummaryLine(results))
    else
        -- Print all as one big message
        const resultBuffer = {
            "The tests have completed.",
            table.concat(report(results), "\n"),
            buildSummaryLine(results),
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
