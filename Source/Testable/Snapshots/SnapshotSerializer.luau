--[[

SnapshotSerializer

Turns a Luau value into the text stored in a snapshot. The output is deterministic and
lossless, so equal values always serialize to the same text and different values never do.
Table keys are sorted, nesting has no depth cap, and values that cannot be compared across
runs (functions, threads, plain userdata, and so on) are written as their type name.
Vectors and Roblox datatypes are written by value, so two different ones never share a
snapshot. A cyclic value or a table key that is not a scalar raises an error, because
neither can be written deterministically.

--]]

const ADDRESS_PATTERN = ": 0x%x+$"
-- How to read the text of datatypes that tostring doesn't tell apart, by typeof name.
-- Several BrickColor values share one name (e.g., 127 and 333 are both "Gold"), so those
-- are written by number.
const DATATYPE_READERS: { [string]: (value: any) -> string } = {
    BrickColor = function(value: any): string
        return tostring(value.Number)
    end
}
const INDENT = "    "
const KEY_TYPE_RANKS = {
    ["boolean"] = 3,
    ["number"] = 1,
    ["string"] = 2
}
const SIMPLE_ESCAPES = {
    ["\t"] = "\\t",
    ["\r"] = "\\r",
    ["\\"] = "\\\\"
}

const SnapshotSerializer = {}

--[[
    Escapes a string so it survives a round trip through a text file. Nested strings stay
    on one line, while a top-level string keeps its real line breaks and quotation marks so
    multi-line text stays readable and diffs line by line.
]]
const function escapeString(text: string, isTopLevel: boolean): string
    return (
        text:gsub('[%c\127\\"]', function(character: string): string
            if character == "\n" then
                return if isTopLevel then "\n" else "\\n"
            elseif character == '"' then
                return if isTopLevel then '"' else '\\"'
            end
            return SIMPLE_ESCAPES[character] or string.format("\\%03d", string.byte(character))
        end)
    )
end

--[[
    Formats a datatype from its type name and the text tostring gave for it, as in
    "Vector3(1, 2, 3)". Text that is only a memory address (what tostring gives a userdata
    with no text of its own) changes between runs, so it is not usable, and neither is
    anything that isn't a string.

    @param typeName - The name typeof reports for the value
    @param text - What tostring returned for the value
    @return The snapshot text, or nil if the value can't be written by value
]]
function SnapshotSerializer.formatDatatype(typeName: string, text: any): string?
    assert(type(typeName) == "string", "typeName must be a string")

    if type(text) ~= "string" or text:match(ADDRESS_PATTERN) then
        return nil
    end

    return `{typeName}({escapeString(text, false)})`
end

const function serializeNumber(value: number): string
    -- The sign of NaN differs between platforms, so it is always written the same way.
    if value ~= value then
        return "nan"
    end
    return tostring(value)
end

const function serializeKey(key: any): string
    if type(key) == "string" then
        if key:match("^[%a_][%w_]*$") then
            return key
        end
        return `["{escapeString(key, false)}"]`
    elseif type(key) == "number" then
        return `[{serializeNumber(key)}]`
    end
    return `[{tostring(key)}]`
end

const function compareKeys(left: any, right: any): boolean
    const leftRank = KEY_TYPE_RANKS[type(left)]
    const rightRank = KEY_TYPE_RANKS[type(right)]
    if leftRank ~= rightRank then
        return leftRank < rightRank
    elseif type(left) == "boolean" then
        return not left and right
    end
    return left < right
end

--[[
    Serializes a value that is neither a scalar nor a table. Datatypes are written as
    their typeof name and their text (e.g., "Vector3(1, 2, 3)"), since they are plain
    values that read the same on every run. A datatype is a vector, or a userdata that
    typeof gives a name of its own, which covers the Roblox datatypes. Everything else is
    written as its type name alone, and so is a datatype with no usable text.
]]
const function serializeOpaque(value: any, valueType: string): string
    const richType = typeof(value)

    if richType ~= valueType or valueType == "vector" then
        const read: (value: any) -> string = DATATYPE_READERS[richType] or tostring
        const ok, text = pcall(read, value)
        const formatted = if ok then SnapshotSerializer.formatDatatype(richType, text) else nil
        if formatted ~= nil then
            return formatted
        end
    end

    return `<{valueType}>`
end

const function serializeValue(value: any, depth: number, path: string, ancestors: { [any]: boolean }): string
    const valueType = type(value)

    if valueType == "nil" or valueType == "boolean" then
        return tostring(value)
    elseif valueType == "number" then
        return serializeNumber(value)
    elseif valueType == "string" then
        return `"{escapeString(value, depth == 0)}"`
    elseif valueType ~= "table" then
        return serializeOpaque(value, valueType)
    end

    if ancestors[value] then
        error(`Cannot serialize a cyclic value at "{path}".`, 0)
    end

    -- The array part is written positionally and every other key is written explicitly.
    local arrayLength = 0
    while rawget(value, arrayLength + 1) ~= nil do
        arrayLength += 1
    end

    const keys = {}
    for key in next, value do
        const keyType = type(key)
        if KEY_TYPE_RANKS[keyType] == nil then
            error(
                `Cannot serialize a table with a {keyType} key at "{path}", because its order is not deterministic.`,
                0
            )
        end
        const isArrayIndex = keyType == "number" and key % 1 == 0 and key >= 1 and key <= arrayLength
        if not isArrayIndex then
            table.insert(keys, key)
        end
    end

    if arrayLength == 0 and #keys == 0 then
        return "{}"
    end

    table.sort(keys, compareKeys)
    ancestors[value] = true

    const childIndent = string.rep(INDENT, depth + 1)
    const lines = { "{" }
    for index = 1, arrayLength do
        const child = serializeValue(rawget(value, index), depth + 1, `{path}[{index}]`, ancestors)
        table.insert(lines, `{childIndent}{child},`)
    end
    for _, key in keys do
        const keyText = serializeKey(key)
        const childPath = if keyText:sub(1, 1) == "[" then `{path}{keyText}` else `{path}.{keyText}`
        const child = serializeValue(rawget(value, key), depth + 1, childPath, ancestors)
        table.insert(lines, `{childIndent}{keyText} = {child},`)
    end
    table.insert(lines, `{string.rep(INDENT, depth)}}`)

    ancestors[value] = nil

    return table.concat(lines, "\n")
end

--[[
    Serializes a value into snapshot text.

    @param value - The value to serialize
    @return The serialized text, which is never empty
]]
function SnapshotSerializer.serialize(value: any): string
    return serializeValue(value, 0, "value", {})
end

return SnapshotSerializer
