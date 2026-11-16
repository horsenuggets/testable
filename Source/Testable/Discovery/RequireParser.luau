--[[

RequireParser

Scans Luau source text for string requires without running it. Comments and string
contents are skipped, so a require that is commented out or merely mentioned inside a
string is not reported. The expressions inside an interpolated string are code, so they
are scanned too. Requires whose argument is not a plain string literal can't be followed
and are ignored.

--]]

type State = {
    Paths: { string },
    Seen: { [string]: boolean },
}

const RequireParser = {}

--[[
    Finds the end of a long bracket, with any number of equals signs between its two
    square brackets, that opens at the given position.

    @param source - The source text
    @param position - The index of the opening "["
    @return contentStart - The index of the first content character, or nil if no long
        bracket opens here
    @return contentEnd - The index of the last content character
    @return nextPosition - The index right after the closing bracket
]]
const function readLongBracket(source: string, position: number): (number?, number, number)
    const equals = string.match(source, "^%[(=*)%[", position)
    if equals == nil then
        return nil, 0, position
    end

    const contentStart = position + #equals + 2
    const closeStart, closeEnd = string.find(source, `]{equals}]`, contentStart, true)
    if closeStart == nil or closeEnd == nil then
        return contentStart, #source, #source + 1
    end
    return contentStart, closeStart - 1, closeEnd + 1
end

--[[
    Finds the end of a quoted string that opens at the given position, honoring
    backslash escapes.

    @param source - The source text
    @param position - The index of the opening quote
    @return content - The raw text between the quotes
    @return nextPosition - The index right after the closing quote
]]
const function readQuoted(source: string, position: number): (string, number)
    const quote = string.sub(source, position, position)
    local index = position + 1

    while index <= #source do
        const character = string.sub(source, index, index)
        if character == "\\" then
            index += 2
        elseif character == quote then
            return string.sub(source, position + 1, index - 1), index + 1
        elseif character == "\n" and quote ~= "`" then
            break
        else
            index += 1
        end
    end

    return string.sub(source, position + 1, index - 1), index + 1
end

--[[
    Reads a string literal that starts at the given position, if there is one.

    @param source - The source text
    @param position - The index where the literal would start
    @return content - The text of the literal, or nil if none starts here
    @return nextPosition - The index right after the literal
]]
const function readStringLiteral(source: string, position: number): (string?, number)
    const character = string.sub(source, position, position)
    if character == '"' or character == "'" or character == "`" then
        return readQuoted(source, position)
    end

    if character == "[" then
        const contentStart, contentEnd, nextPosition = readLongBracket(source, position)
        if contentStart ~= nil then
            return string.sub(source, contentStart, contentEnd), nextPosition
        end
    end

    return nil, position
end

--[[
    Finds the end of a comment that starts at the given position, if there is one.

    @param source - The source text
    @param position - The index where the comment would start
    @return The index right after the comment, or nil if none starts here
]]
const function readComment(source: string, position: number): number?
    if string.sub(source, position, position + 1) ~= "--" then
        return nil
    end

    const contentStart, _, nextPosition = readLongBracket(source, position + 2)
    if contentStart ~= nil then
        return nextPosition
    end
    return (string.find(source, "\n", position, true) or #source) + 1
end

--[[
    Skips the whitespace and comments that start at the given position.

    @param source - The source text
    @param position - The index to start from
    @return The index of the first character that is neither whitespace nor a comment
]]
const function skipTrivia(source: string, position: number): number
    local index = position
    while true do
        index = string.match(source, "^%s*()", index) :: number
        const afterComment = readComment(source, index)
        if afterComment == nil then
            return index
        end
        index = afterComment
    end
end

--[[
    Reads the argument of a require call whose name ends right before the given
    position.

    @param source - The source text
    @param position - The index right after the "require" identifier
    @return The required path, or nil if the argument is not a plain string literal
]]
const function readRequireArgument(source: string, position: number): string?
    local index = skipTrivia(source, position)
    const parenthesized = string.sub(source, index, index) == "("
    if parenthesized then
        index = skipTrivia(source, index + 1)
    end

    const quote = string.sub(source, index, index)
    const content, nextPosition = readStringLiteral(source, index)
    if content == nil then
        return nil
    end

    -- An interpolated string only names a fixed path when nothing is interpolated.
    if quote == "`" and string.find(content, "{", 1, true) ~= nil then
        return nil
    end

    -- Anything other than a closing parenthesis means the literal is only one part of
    -- a larger expression, such as a concatenation.
    const closing = skipTrivia(source, nextPosition)
    if parenthesized and string.sub(source, closing, closing) ~= ")" then
        return nil
    end

    return content
end

local scanInterpolatedString: (source: string, position: number, state: State) -> number

--[[
    Scans code for requires, starting at the given position. When the code is an
    expression inside an interpolated string, the scan ends at the closing brace of that
    expression. Otherwise it runs to the end of the source.

    @param source - The source text
    @param position - The index to start from
    @param state - The paths found so far, which the scan adds to
    @param insideInterpolation - Whether the code is an interpolated expression
    @return The index right after the scanned code
]]
const function scanCode(source: string, position: number, state: State, insideInterpolation: boolean): number
    local braceDepth = 0
    local index = position
    local previousSignificant = ""

    while index <= #source do
        const character = string.sub(source, index, index)
        const afterComment = if character == "-" then readComment(source, index) else nil

        if afterComment ~= nil then
            index = afterComment
        elseif character == "`" then
            index = scanInterpolatedString(source, index, state)
            previousSignificant = character
        elseif character == '"' or character == "'" or character == "[" then
            const content, nextPosition = readStringLiteral(source, index)
            index = if content ~= nil then nextPosition else index + 1
            previousSignificant = character
        elseif string.match(character, "[%a_]") ~= nil then
            const identifier = string.match(source, "^[%w_]+", index) :: string
            index += #identifier

            -- A field or method named "require" is not the global function.
            if identifier == "require" and previousSignificant ~= "." and previousSignificant ~= ":" then
                const path = readRequireArgument(source, index)
                if path ~= nil and not state.Seen[path] then
                    state.Seen[path] = true
                    table.insert(state.Paths, path)
                end
            end
            previousSignificant = "a"
        else
            if character == "{" then
                braceDepth += 1
            elseif character == "}" then
                if insideInterpolation and braceDepth == 0 then
                    return index + 1
                end
                braceDepth -= 1
            end
            if string.match(character, "%s") == nil then
                previousSignificant = character
            end
            index += 1
        end
    end

    return index
end

--[[
    Scans an interpolated string that opens at the given position. The literal parts are
    skipped, and each interpolated expression is scanned as code.

    @param source - The source text
    @param position - The index of the opening backtick
    @param state - The paths found so far, which the scan adds to
    @return The index right after the closing backtick
]]
function scanInterpolatedString(source: string, position: number, state: State): number
    local index = position + 1

    while index <= #source do
        const character = string.sub(source, index, index)
        if character == "\\" then
            index += 2
        elseif character == "`" then
            return index + 1
        elseif character == "{" then
            index = scanCode(source, index + 1, state, true)
        else
            index += 1
        end
    end

    return index
end

--[[
    Returns every path that a piece of Luau source requires with a string literal, in
    the order of first appearance and without duplicates.

    @param source - The Luau source text to scan
    @return The required paths, exactly as written
]]
function RequireParser.parse(source: string): { string }
    assert(type(source) == "string", "source must be a string")

    const state: State = { Paths = {}, Seen = {} }
    scanCode(source, 1, state, false)

    return state.Paths
end

return RequireParser
