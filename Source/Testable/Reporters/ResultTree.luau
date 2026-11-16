--[[

ResultTree

Pure helpers that read a TestResults tree for the reporters. They work out each node's
status, duration, error message, and skip reason, and flatten the tree into one entry per
test case so every reporter agrees on names and counts.

--]]

const TestEnum = require("../TestEnum")
const FULL_NAME_SEPARATOR = " > "
const REPLACEMENT_CHARACTER = "\u{FFFD}"

-- One test as the machine-readable reporters see it. Path holds the phrases of the
-- enclosing describe blocks, starting with the spec root.
export type TestCase = {
    Duration: number,
    ErrorMessage: string?,
    FullName: string,
    Name: string,
    Path: { string },
    SkipReason: string?,
    Status: string,
}

const ResultTree = {}

ResultTree.FullNameSeparator = FULL_NAME_SEPARATOR
ResultTree.ReplacementCharacter = REPLACEMENT_CHARACTER

--[[
    Formats a duration in seconds as a plain decimal with microsecond precision, which is
    a valid number in both JSON and XML. Negative values and values that aren't finite
    count as zero.
]]
function ResultTree.formatSeconds(seconds: number): string
    assert(type(seconds) == "number")
    if seconds ~= seconds or math.abs(seconds) == math.huge then
        return "0.000000"
    end
    return string.format("%.6f", math.max(seconds, 0))
end

--[[
    Removes terminal color sequences and replaces bytes that aren't valid UTF-8, so the
    text is safe to embed in JSON and XML documents.
]]
function ResultTree.sanitize(text: string): string
    assert(type(text) == "string")
    const plain = text:gsub("\27%[[%d;]*%a", "")
    if utf8.len(plain) ~= nil then
        return plain
    end
    const parts = {}
    local position = 1
    while position <= #plain do
        -- utf8.len reports where the first invalid byte is, so everything before it is
        -- kept as is and only that byte is replaced.
        const length, invalidAt = utf8.len(plain, position)
        if length ~= nil then
            table.insert(parts, plain:sub(position))
            break
        end
        table.insert(parts, plain:sub(position, (invalidAt :: number) - 1))
        table.insert(parts, REPLACEMENT_CHARACTER)
        position = (invalidAt :: number) + 1
    end
    return table.concat(parts)
end

--[[
    Returns a node's status. Nodes without one take it from their descendants, where any
    failure wins, then any success, then skipped.
]]
function ResultTree.status(node: any): string?
    assert(type(node) == "table")
    if node.status then
        return node.status
    end
    local status = nil
    for _, child in node.children do
        const childStatus = ResultTree.status(child)
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

--[[
    Returns how long a node took in seconds. Nodes without a recorded duration, such as
    skipped tests and hand-built trees, take the sum of their children.
]]
function ResultTree.duration(node: any): number
    assert(type(node) == "table")
    if type(node.duration) == "number" then
        return node.duration
    end
    local total = 0
    for _, child in node.children do
        total += ResultTree.duration(child)
    end
    return total
end

--[[
    Returns the errors recorded on a node joined into one sanitized message, or nil when
    the node has none.
]]
function ResultTree.errorMessage(node: any): string?
    assert(type(node) == "table")
    if type(node.errors) ~= "table" or #node.errors == 0 then
        return nil
    end
    const messages = {}
    for _, message in node.errors do
        table.insert(messages, ResultTree.sanitize(tostring(message)))
    end
    return table.concat(messages, "\n")
end

--[[
    Returns why a node was skipped, or nil when it wasn't skipped or gave no reason.
]]
function ResultTree.skipReason(node: any): string?
    assert(type(node) == "table")
    if node.status ~= TestEnum.TestStatus.Skipped or type(node.skipReason) ~= "string" or node.skipReason == "" then
        return nil
    end
    return ResultTree.sanitize(node.skipReason)
end

--[[
    Tells whether a node counts as a test case. Every "it" does, and so does a describe
    block whose body failed during planning, since the totals count it as a failure.
]]
function ResultTree.isCase(node: any): boolean
    assert(type(node) == "table")
    const planNode = node.planNode
    if planNode.type == TestEnum.NodeType.It then
        return true
    end
    return planNode.type == TestEnum.NodeType.Describe
        and planNode.loadError ~= nil
        and node.status == TestEnum.TestStatus.Failure
end

--[[
    Joins the phrases leading to a test into its full name.
]]
function ResultTree.fullName(path: { string }, name: string): string
    assert(type(path) == "table")
    assert(type(name) == "string")
    const parts = table.clone(path)
    table.insert(parts, name)
    return table.concat(parts, FULL_NAME_SEPARATOR)
end

--[[
    Returns a node's phrase, sanitized for embedding in a report.
]]
function ResultTree.name(node: any): string
    assert(type(node) == "table")
    return ResultTree.sanitize(tostring(node.planNode.phrase or ""))
end

const function collect(node: any, path: { string }, cases: { TestCase })
    const name = ResultTree.name(node)
    if ResultTree.isCase(node) then
        table.insert(cases, {
            Duration = ResultTree.duration(node),
            ErrorMessage = ResultTree.errorMessage(node),
            FullName = ResultTree.fullName(path, name),
            Name = name,
            Path = table.clone(path),
            SkipReason = ResultTree.skipReason(node),
            -- A test that never got to run, like one behind a failed beforeAll hook,
            -- has no status and counts as skipped.
            Status = ResultTree.status(node) or TestEnum.TestStatus.Skipped,
        })
    end
    const childPath = table.clone(path)
    table.insert(childPath, name)
    for _, child in node.children do
        collect(child, childPath, cases)
    end
end

--[[
    Flattens a whole TestResults tree into its test cases in definition order.
]]
function ResultTree.collectCases(results: any): { TestCase }
    assert(type(results) == "table")
    const cases: { TestCase } = {}
    for _, child in results.children do
        collect(child, {}, cases)
    end
    return cases
end

--[[
    Flattens one spec root into its test cases in definition order. The root lists itself
    first when it counts as a case, which happens when its body failed during planning.
]]
function ResultTree.collectSuiteCases(suite: any): { TestCase }
    assert(type(suite) == "table")
    const cases: { TestCase } = {}
    collect(suite, {}, cases)
    return cases
end

return ResultTree
