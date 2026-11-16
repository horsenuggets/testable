--[[

Xml

A small XML parser for tests. It reads the subset the JUnit reporter writes, which is a
declaration followed by elements with double-quoted attributes and text content, and it
errors on anything malformed, so parsing a document also checks that it is well formed.

--]]

const ENTITIES = {
    amp = "&",
    apos = "'",
    gt = ">",
    lt = "<",
    quot = '"',
}

export type Element = {
    Attributes: { [string]: string },
    Children: { Element },
    Name: string,
    Text: string,
}

const Xml = {}

--[[
    Replaces entity and character references with the characters they stand for. A bare
    ampersand or an unknown entity is an error, as it is for a real parser.
]]
function Xml.unescape(text: string): string
    assert(type(text) == "string")
    const withoutReferences = text:gsub("&[^;&]*;", "")
    assert(not withoutReferences:find("&", 1, true), `The text "{text}" has an ampersand that isn't escaped.`)
    return (
        text:gsub("&([^;&]*);", function(reference: string): string
            const code = reference:match("^#(%d+)$")
            if code ~= nil then
                return utf8.char(tonumber(code) :: number)
            end
            return ENTITIES[reference] or error(`The entity "&{reference};" is not defined.`)
        end)
    )
end

const function parseAttributes(source: string): { [string]: string }
    const attributes = {}
    local position = 1
    while true do
        const nameStart, nameEnd, name = source:find('^%s+([%w_:%-]+)="', position)
        if nameStart == nil then
            break
        end
        const valueEnd = source:find('"', (nameEnd :: number) + 1, true)
        assert(valueEnd ~= nil, `The attribute "{name}" is missing its closing quote.`)
        const value = source:sub((nameEnd :: number) + 1, valueEnd - 1)
        assert(not value:find("[<\n\r\t]"), `The attribute "{name}" has a character that must be escaped.`)
        assert(attributes[name] == nil, `The attribute "{name}" appears twice.`)
        attributes[name :: string] = Xml.unescape(value)
        position = valueEnd + 1
    end
    assert(source:sub(position):match("^%s*$"), `The attributes "{source}" are malformed.`)
    return attributes
end

--[[
    Parses a document and returns its root element.
]]
function Xml.parse(document: string): Element
    assert(type(document) == "string")
    const declarationEnd = select(2, document:find('^<%?xml version="1%.0" encoding="UTF%-8"%?>\n'))
    assert(declarationEnd ~= nil, "The document doesn't start with an XML declaration.")
    assert(utf8.len(document) ~= nil, "The document isn't valid UTF-8.")
    assert(not document:find("[\0-\8\11\12\14-\31]"), "The document has a control character XML doesn't allow.")

    local root: Element? = nil
    const stack: { Element } = {}
    local position = declarationEnd + 1
    while position <= #document do
        const tagStart = document:find("<", position, true)
        const text = document:sub(position, (tagStart or #document + 1) - 1)
        if #stack > 0 then
            assert(not text:find(">", 1, true), 'Text content has a ">" that isn\'t escaped.')
            stack[#stack].Text ..= Xml.unescape(text)
        else
            assert(text:match("^%s*$"), "The document has text outside of its root element.")
        end
        if tagStart == nil then
            break
        end
        const tagEnd = document:find(">", tagStart, true)
        assert(tagEnd ~= nil, "A tag is missing its closing bracket.")
        const tag = document:sub(tagStart + 1, tagEnd - 1)
        if tag:sub(1, 1) == "/" then
            const open = table.remove(stack)
            assert(open ~= nil and open.Name == tag:sub(2), `The closing tag "{tag}" doesn't match an open element.`)
        else
            const selfClosing = tag:sub(-1) == "/"
            const body = if selfClosing then tag:sub(1, -2) else tag
            const name = body:match("^[%w_:%-]+")
            assert(name ~= nil, `The tag "{tag}" has no name.`)
            const element: Element = {
                Attributes = parseAttributes(body:sub(#name + 1)),
                Children = {},
                Name = name,
                Text = "",
            }
            if #stack > 0 then
                table.insert(stack[#stack].Children, element)
            else
                assert(root == nil, "The document has more than one root element.")
                root = element
            end
            if not selfClosing then
                table.insert(stack, element)
            end
        end
        position = tagEnd + 1
    end
    assert(#stack == 0, "The document ends with an element still open.")
    assert(root ~= nil, "The document has no root element.")
    return root
end

return Xml
