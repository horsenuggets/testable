--[[

ValueInspector

Compares and renders arbitrary Luau values for the expectation matchers. Deep equality
walks tables recursively, treats NaN as equal to NaN, and tolerates cyclic tables.
Formatting pretty-prints values deterministically (sorted keys) and truncates deeply
nested tables and very large tables so that failure messages stay readable.

--]]

const DEFAULT_MAX_DEPTH = 4
const DEFAULT_MAX_ITEMS = 50
const INDENT = "    "
const INLINE_WIDTH = 72
const KEY_TYPE_ORDER = {
    number = 1,
    string = 2,
    boolean = 3,
}
const LAST_KEY_TYPE_ORDER = 4
const STRING_ESCAPES = {
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ['"'] = '\\"',
    ["\\"] = "\\\\",
}

const ValueInspector = {}

export type FormatOptions = {
    MaxDepth: number?,
    MaxItems: number?,
}

type VisitedPairs = { [any]: { [any]: boolean } }

const function isNaN(value: any): boolean
    return type(value) == "number" and value ~= value
end

const function deepEqualInner(left: any, right: any, visited: VisitedPairs): boolean
    if rawequal(left, right) then
        return true
    end

    if isNaN(left) and isNaN(right) then
        return true
    end

    if type(left) ~= "table" or type(right) ~= "table" then
        -- Userdata such as Roblox datatypes compare by value through their own __eq.
        return left == right
    end

    -- A pair that is already being compared further up the stack is assumed equal, which
    -- is what keeps cyclic tables from recursing forever.
    local visitedForLeft = visited[left]

    if visitedForLeft == nil then
        visitedForLeft = {}
        visited[left] = visitedForLeft
    elseif visitedForLeft[right] then
        return true
    end

    visitedForLeft[right] = true

    for key, leftValue in next, left do
        if not deepEqualInner(leftValue, rawget(right, key), visited) then
            return false
        end
    end

    for key in next, right do
        if rawget(left, key) == nil then
            return false
        end
    end

    return true
end

const function quoteString(value: string): string
    const escaped = value:gsub('[%c"\\]', function(character)
        return STRING_ESCAPES[character] or ("\\%03d"):format(character:byte())
    end)

    return `"{escaped}"`
end

const function formatNumber(value: number): string
    if value ~= value then
        return "nan"
    elseif value == math.huge then
        return "inf"
    elseif value == -math.huge then
        return "-inf"
    end

    return tostring(value)
end

const function formatScalar(value: any): string
    const valueType = typeof(value)

    if valueType == "string" then
        return quoteString(value)
    elseif valueType == "number" then
        return formatNumber(value)
    elseif valueType == "nil" or valueType == "boolean" then
        return tostring(value)
    elseif valueType == "table" or valueType == "function" or valueType == "thread" then
        -- Addresses change between runs, so they are left out to keep output stable.
        return `<{valueType}>`
    end

    const ok, rendered = pcall(tostring, value)

    return `{valueType}({if ok then rendered else "?"})`
end

const function formatKey(key: any): string
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        return key
    end

    return `[{formatScalar(key)}]`
end

const function compareKeys(left: any, right: any): boolean
    const leftType = type(left)
    const rightType = type(right)
    const leftOrder = KEY_TYPE_ORDER[leftType] or LAST_KEY_TYPE_ORDER
    const rightOrder = KEY_TYPE_ORDER[rightType] or LAST_KEY_TYPE_ORDER

    if leftOrder ~= rightOrder then
        return leftOrder < rightOrder
    end

    if leftType == "number" then
        -- NaN can't be a table key, so numeric keys always have a total order.
        return left < right
    elseif leftType == "string" then
        return left < right
    elseif leftType == "boolean" then
        return left == false and right == true
    end

    return formatScalar(left) < formatScalar(right)
end

local formatInner

const function formatTable(
    value: { [any]: any },
    depth: number,
    maxDepth: number,
    maxItems: number,
    ancestors: { [any]: boolean }
): string
    if ancestors[value] then
        return "<cycle>"
    end

    if next(value) == nil then
        return "{}"
    end

    if depth >= maxDepth then
        return "{...}"
    end

    ancestors[value] = true

    const arrayLength = rawlen(value)
    const keys = {}

    for key in next, value do
        const isArrayIndex = type(key) == "number" and key >= 1 and key <= arrayLength and key % 1 == 0

        if not isArrayIndex then
            table.insert(keys, key)
        end
    end

    table.sort(keys, compareKeys)

    const entries = {}
    const totalItems = arrayLength + #keys

    for index = 1, arrayLength do
        if #entries >= maxItems then
            break
        end

        table.insert(entries, formatInner(rawget(value, index), depth + 1, maxDepth, maxItems, ancestors))
    end

    for _, key in keys do
        if #entries >= maxItems then
            break
        end

        const rendered = formatInner(rawget(value, key), depth + 1, maxDepth, maxItems, ancestors)
        table.insert(entries, `{formatKey(key)} = {rendered}`)
    end

    if totalItems > #entries then
        const omitted = totalItems - #entries
        table.insert(entries, `... {omitted} more {if omitted == 1 then "item" else "items"}`)
    end

    ancestors[value] = nil

    const inline = `\{ {table.concat(entries, ", ")} \}`

    if #inline <= INLINE_WIDTH and not inline:find("\n", 1, true) then
        return inline
    end

    const lines = { "{" }

    for _, entry in entries do
        const indented = entry:gsub("\n", `\n{INDENT}`)
        table.insert(lines, `{INDENT}{indented},`)
    end

    table.insert(lines, "}")

    return table.concat(lines, "\n")
end

function formatInner(
    value: any,
    depth: number,
    maxDepth: number,
    maxItems: number,
    ancestors: { [any]: boolean }
): string
    if type(value) == "table" then
        return formatTable(value, depth, maxDepth, maxItems, ancestors)
    end

    return formatScalar(value)
end

--[[
    Returns whether two values are structurally equal. Tables are compared key by key
    without invoking metamethods, NaN equals NaN, and everything else falls back to "==".
]]
function ValueInspector.deepEqual(left: any, right: any): boolean
    return deepEqualInner(left, right, {})
end

--[[
    Renders a value as readable, deterministic text. Table keys are sorted, tables nested
    deeper than MaxDepth render as "{...}", and tables with more than MaxItems entries
    list how many were left out.
]]
function ValueInspector.format(value: any, options: FormatOptions?): string
    assert(options == nil or type(options) == "table", "options must be a table or nil")

    const maxDepth = if options and options.MaxDepth then options.MaxDepth else DEFAULT_MAX_DEPTH
    const maxItems = if options and options.MaxItems then options.MaxItems else DEFAULT_MAX_ITEMS

    assert(type(maxDepth) == "number", "MaxDepth must be a number")
    assert(type(maxItems) == "number", "MaxItems must be a number")

    return formatInner(value, 0, maxDepth, maxItems, {})
end

return ValueInspector
