--[[

JsonReporter

Renders test results as a JSON document for tools to read. The document keeps the shape
of the results tree, with one node per spec root, describe block, and test, and its keys
are always written in the same order so two runs can be compared as text.

Here is the shape of the document...

{
  "Version": 1,
  "Totals": { "Total", "Passed", "Failed", "Skipped", "Duration" },
  "Suites": [ Node ]
}

Every Node has "Name", "FullName", "Type" ("Describe" or "It"), "Status" ("Success",
"Failure", or "Skipped"), "Duration" in seconds, and "Children". A node that failed also
has "ErrorMessage", and a skipped node that gave a reason also has "SkipReason".

--]]

const ResultTree = require("./ResultTree")
const TestEnum = require("../TestEnum")
const CONTROL_ESCAPES = {
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ['"'] = '\\"',
    ["\\"] = "\\\\",
}
const INDENT = "  "
const VERSION = 1

const JsonReporter = {}

JsonReporter.Version = VERSION

--[[
    Encodes text as a JSON string literal, including its quotes.
]]
function JsonReporter.encodeString(text: string): string
    assert(type(text) == "string")
    const escaped = text:gsub('[%c"\\]', function(character: string): string
        return CONTROL_ESCAPES[character] or string.format("\\u%04x", string.byte(character))
    end)
    return `"{escaped}"`
end

const function appendNode(node: any, path: { string }, lines: { string }, depth: number, isLast: boolean)
    const outer = string.rep(INDENT, depth)
    const inner = string.rep(INDENT, depth + 1)
    const name = ResultTree.name(node)
    const isIt = node.planNode.type == TestEnum.NodeType.It
    const status = ResultTree.status(node) or TestEnum.TestStatus.Skipped
    const errorMessage = ResultTree.errorMessage(node)
    const skipReason = ResultTree.skipReason(node)

    table.insert(lines, `{outer}\{`)
    table.insert(lines, `{inner}"Name": {JsonReporter.encodeString(name)},`)
    table.insert(lines, `{inner}"FullName": {JsonReporter.encodeString(ResultTree.fullName(path, name))},`)
    table.insert(lines, `{inner}"Type": "{if isIt then "It" else "Describe"}",`)
    table.insert(lines, `{inner}"Status": {JsonReporter.encodeString(status)},`)
    table.insert(lines, `{inner}"Duration": {ResultTree.formatSeconds(ResultTree.duration(node))},`)
    if errorMessage ~= nil then
        table.insert(lines, `{inner}"ErrorMessage": {JsonReporter.encodeString(errorMessage)},`)
    end
    if skipReason ~= nil then
        table.insert(lines, `{inner}"SkipReason": {JsonReporter.encodeString(skipReason)},`)
    end
    if #node.children == 0 then
        table.insert(lines, `{inner}"Children": []`)
    else
        const childPath = table.clone(path)
        table.insert(childPath, name)
        table.insert(lines, `{inner}"Children": [`)
        for index, child in node.children do
            appendNode(child, childPath, lines, depth + 2, index == #node.children)
        end
        table.insert(lines, `{inner}]`)
    end
    table.insert(lines, `{outer}\}{if isLast then "" else ","}`)
end

--[[
    Returns the JSON document for the given results without emitting anything. The same
    results always produce the same text.
]]
function JsonReporter.format(results: any): string
    assert(type(results) == "table")
    assert(type(results.children) == "table")
    local passed = 0
    local failed = 0
    local skipped = 0
    for _, case in ResultTree.collectCases(results) do
        if case.Status == TestEnum.TestStatus.Success then
            passed += 1
        elseif case.Status == TestEnum.TestStatus.Failure then
            failed += 1
        else
            skipped += 1
        end
    end

    const lines = {
        "{",
        `{INDENT}"Version": {VERSION},`,
        `{INDENT}"Totals": \{`,
        `{INDENT}{INDENT}"Total": {passed + failed + skipped},`,
        `{INDENT}{INDENT}"Passed": {passed},`,
        `{INDENT}{INDENT}"Failed": {failed},`,
        `{INDENT}{INDENT}"Skipped": {skipped},`,
        `{INDENT}{INDENT}"Duration": {ResultTree.formatSeconds(ResultTree.duration(results))}`,
        `{INDENT}\},`,
    }
    if #results.children == 0 then
        table.insert(lines, `{INDENT}"Suites": []`)
    else
        table.insert(lines, `{INDENT}"Suites": [`)
        for index, child in results.children do
            appendNode(child, {}, lines, 2, index == #results.children)
        end
        table.insert(lines, `{INDENT}]`)
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

return JsonReporter
