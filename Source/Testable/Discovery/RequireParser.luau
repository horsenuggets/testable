--[[

RequireParser

Scans Luau source text for string requires without running it. Comments and string
contents are skipped, so a require that is commented out or merely mentioned inside a
string is not reported. Requires whose argument is not a plain string literal can't be
followed and are ignored.

--]]

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
    Reads the argument of a require call whose name ends right before the given
    position.

    @param source - The source text
    @param position - The index right after the "require" identifier
    @return The required path, or nil if the argument is not a plain string literal
]]
const function readRequireArgument(source: string, position: number): string?
    local index = string.match(source, "^%s*()", position) :: number
    const parenthesized = string.sub(source, index, index) == "("
    if parenthesized then
        index = string.match(source, "^%s*()", index + 1) :: number
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
    if parenthesized and string.match(source, "^%s*%)", nextPosition) == nil then
        return nil
    end

    return content
end

--[[
    Returns every path that a piece of Luau source requires with a string literal, in
    the order of first appearance and without duplicates.

    @param source - The Luau source text to scan
    @return The required paths, exactly as written
]]
function RequireParser.parse(source: string): { string }
    assert(type(source) == "string", "source must be a string")

    const paths = {}
    const seen: { [string]: boolean } = {}
    local index = 1
    local previousSignificant = ""

    while index <= #source do
        const character = string.sub(source, index, index)

        if character == "-" and string.sub(source, index, index + 1) == "--" then
            const contentStart, _, nextPosition = readLongBracket(source, index + 2)
            if contentStart ~= nil then
                index = nextPosition
            else
                index = (string.find(source, "\n", index, true) or #source) + 1
            end
        elseif character == '"' or character == "'" or character == "`" or character == "[" then
            const content, nextPosition = readStringLiteral(source, index)
            index = if content ~= nil then nextPosition else index + 1
            previousSignificant = character
        elseif string.match(character, "[%a_]") ~= nil then
            const identifier = string.match(source, "^[%w_]+", index) :: string
            index += #identifier

            -- A field or method named "require" is not the global function.
            if identifier == "require" and previousSignificant ~= "." and previousSignificant ~= ":" then
                const path = readRequireArgument(source, index)
                if path ~= nil and not seen[path] then
                    seen[path] = true
                    table.insert(paths, path)
                end
            end
            previousSignificant = "a"
        else
            if string.match(character, "%s") == nil then
                previousSignificant = character
            end
            index += 1
        end
    end

    return paths
end

return RequireParser
