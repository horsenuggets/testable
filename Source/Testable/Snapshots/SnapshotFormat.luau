--[[

SnapshotFormat

Reads and writes the plain text format of ".snap" files, and builds the keys that name
each snapshot. A file starts with a version line, followed by one entry per snapshot. Each
entry has a header with the snapshot key and the number of lines in its value, followed by
the value written literally. Entries are sorted by key, so the file diffs cleanly.

--]]

const HEADER = "testable snapshot v1"
const NAME_SEPARATOR = " > "

const SnapshotFormat = {}

export type Entries = { [string]: string }

const function escapeKey(key: string): string
    return (key:gsub("\\", "\\\\"):gsub("\n", "\\n"))
end

const function unescapeKey(key: string): string
    return (
        key:gsub("\\(.)", function(character: string): string
            return if character == "n" then "\n" else character
        end)
    )
end

const function countLines(text: string): number
    const _, lineBreaks = text:gsub("\n", "")
    return lineBreaks + 1
end

--[[
    Joins the names on the way to a test (describe blocks, then the test itself) into the
    full test name used in snapshot keys.

    @param names - The names from the outermost describe block down to the test
    @return The full test name
]]
function SnapshotFormat.makeTestName(names: { string }): string
    assert(type(names) == "table", "names must be a table")
    return table.concat(names, NAME_SEPARATOR)
end

--[[
    Builds the key of a snapshot from the full name of its test and its label, which is
    either the hint given to the matcher or the snapshot's number within the test.

    @param testName - The full name of the test
    @param label - The hint or number of the snapshot
    @return The snapshot key
]]
function SnapshotFormat.makeKey(testName: string, label: string): string
    assert(type(testName) == "string", "testName must be a string")
    assert(type(label) == "string", "label must be a string")
    return `{testName} {label}`
end

--[[
    Renders snapshot entries as the contents of a ".snap" file.

    @param entries - The serialized values by snapshot key
    @return The file contents
]]
function SnapshotFormat.render(entries: Entries): string
    assert(type(entries) == "table", "entries must be a table")

    const keys = {}
    for key in entries do
        table.insert(keys, key)
    end
    table.sort(keys)

    const lines = { HEADER }
    for _, key in keys do
        const value = entries[key]
        table.insert(lines, "")
        table.insert(lines, `{escapeKey(key)} {countLines(value)}`)
        table.insert(lines, value)
    end

    return `{table.concat(lines, "\n")}\n`
end

--[[
    Parses the contents of a ".snap" file.

    @param contents - The file contents
    @return entries - The serialized values by snapshot key, or nil if the file is invalid
    @return message - Why the file is invalid, when it is
]]
function SnapshotFormat.parse(contents: string): (Entries?, string?)
    assert(type(contents) == "string", "contents must be a string")

    -- Stored values never contain a raw carriage return, so any that appear come from
    -- line ending conversion and can be dropped.
    const lines = contents:gsub("\r\n", "\n"):split("\n")
    if lines[1] ~= HEADER then
        return nil, `The first line must be "{HEADER}".`
    end

    const entries: Entries = {}
    local index = 2
    while index <= #lines do
        const line = lines[index]
        if line == "" then
            index += 1
            continue
        end

        const escapedKey, countText = line:match("^(.*) (%d+)$")
        const count = tonumber(countText)
        if escapedKey == nil or count == nil or count < 1 then
            return nil, `Line {index} is not a valid entry header.`
        elseif index + count > #lines then
            return nil, `The entry on line {index} has fewer lines than its header says.`
        end

        const key = unescapeKey(escapedKey)
        if entries[key] ~= nil then
            return nil, `The entry on line {index} repeats an earlier key.`
        end

        entries[key] = table.concat(lines, "\n", index + 1, index + count)
        index += count + 1
    end

    return entries, nil
end

return SnapshotFormat
