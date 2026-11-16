--[[

SnapshotDiff

Produces a line diff between a stored snapshot and a new value. Removed lines start with
"- ", added lines start with "+ ", and unchanged lines around a change start with two
spaces. Long runs of unchanged lines collapse into a single "..." line.

--]]

const CONTEXT_LINES = 3
const MAX_TABLE_CELLS = 4000000

const SnapshotDiff = {}

type Operation = { Kind: string, Text: string }

--[[
    Computes the operations that turn one list of lines into another, using the longest
    common subsequence so that unchanged lines in between stay unchanged.
]]
const function diffMiddle(expected: { string }, actual: { string }, operations: { Operation })
    const expectedCount = #expected
    const actualCount = #actual

    -- Very large inputs fall back to replacing everything rather than building a huge
    -- table.
    if expectedCount * actualCount > MAX_TABLE_CELLS then
        for _, line in expected do
            table.insert(operations, { Kind = "-", Text = line })
        end
        for _, line in actual do
            table.insert(operations, { Kind = "+", Text = line })
        end
        return
    end

    const lengths = {}
    for row = expectedCount + 1, 1, -1 do
        lengths[row] = table.create(actualCount + 1, 0)
    end
    for row = expectedCount, 1, -1 do
        for column = actualCount, 1, -1 do
            if expected[row] == actual[column] then
                lengths[row][column] = lengths[row + 1][column + 1] + 1
            else
                lengths[row][column] = math.max(lengths[row + 1][column], lengths[row][column + 1])
            end
        end
    end

    local row = 1
    local column = 1
    while row <= expectedCount or column <= actualCount do
        if row <= expectedCount and column <= actualCount and expected[row] == actual[column] then
            table.insert(operations, { Kind = " ", Text = expected[row] })
            row += 1
            column += 1
        elseif
            column > actualCount or (row <= expectedCount and lengths[row + 1][column] >= lengths[row][column + 1])
        then
            table.insert(operations, { Kind = "-", Text = expected[row] })
            row += 1
        else
            table.insert(operations, { Kind = "+", Text = actual[column] })
            column += 1
        end
    end
end

--[[
    Returns the diff between two texts as a list of lines.

    @param expected - The stored text
    @param actual - The new text
    @return The diff lines, which are empty when the texts are equal
]]
function SnapshotDiff.lines(expected: string, actual: string): { string }
    assert(type(expected) == "string", "expected must be a string")
    assert(type(actual) == "string", "actual must be a string")

    if expected == actual then
        return {}
    end

    const expectedLines = expected:split("\n")
    const actualLines = actual:split("\n")

    -- Shared lines at both ends never need the table, so only the middle is compared.
    local prefix = 0
    while prefix < #expectedLines and prefix < #actualLines and expectedLines[prefix + 1] == actualLines[prefix + 1] do
        prefix += 1
    end
    local suffix = 0
    while
        suffix < #expectedLines - prefix
        and suffix < #actualLines - prefix
        and expectedLines[#expectedLines - suffix] == actualLines[#actualLines - suffix]
    do
        suffix += 1
    end

    const operations: { Operation } = {}
    for index = 1, prefix do
        table.insert(operations, { Kind = " ", Text = expectedLines[index] })
    end
    diffMiddle(
        table.move(expectedLines, prefix + 1, #expectedLines - suffix, 1, {}),
        table.move(actualLines, prefix + 1, #actualLines - suffix, 1, {}),
        operations
    )
    for index = #expectedLines - suffix + 1, #expectedLines do
        table.insert(operations, { Kind = " ", Text = expectedLines[index] })
    end

    -- Keep only the unchanged lines that sit close to a change.
    const isShown = table.create(#operations, false)
    for index, operation in operations do
        if operation.Kind ~= " " then
            for near = math.max(1, index - CONTEXT_LINES), math.min(#operations, index + CONTEXT_LINES) do
                isShown[near] = true
            end
        end
    end

    const lines = {}
    local isCollapsed = false
    for index, operation in operations do
        if isShown[index] then
            table.insert(lines, `{operation.Kind} {operation.Text}`)
            isCollapsed = false
        elseif not isCollapsed then
            table.insert(lines, "  ...")
            isCollapsed = true
        end
    end

    return lines
end

return SnapshotDiff
