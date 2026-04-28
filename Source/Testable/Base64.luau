--[[

Base64

Encodes and decodes strings to and from Base64 representation. Works in both Roblox and
Lune environments. Adapted from Reselim's implementation via hashlib.

--]]

local Alphabet = {}
local Indexes = {}

-- A-Z
for index = 65, 90 do
    table.insert(Alphabet, index)
end

-- a-z
for index = 97, 122 do
    table.insert(Alphabet, index)
end

-- 0-9
for index = 48, 57 do
    table.insert(Alphabet, index)
end

table.insert(Alphabet, 43) -- +
table.insert(Alphabet, 47) -- /

for index, character in ipairs(Alphabet) do
    Indexes[character] = index
end

local bit32_band = bit32.band
local bit32_lshift = bit32.lshift
local bit32_rshift = bit32.rshift

local Base64 = {}

function Base64.encode(input: string): string
    assert(type(input) == "string", "argument #1 must be a string")

    local output = {}
    local length = 0

    for index = 1, #input, 3 do
        local c1, c2, c3 = string.byte(input, index, index + 2)

        local a = bit32_rshift(c1, 2)
        local b = bit32_lshift(bit32_band(c1, 3), 4) + bit32_rshift(c2 or 0, 4)
        local c = bit32_lshift(bit32_band(c2 or 0, 15), 2) + bit32_rshift(c3 or 0, 6)
        local d = bit32_band(c3 or 0, 63)

        length += 1
        output[length] = Alphabet[a + 1]

        length += 1
        output[length] = Alphabet[b + 1]

        length += 1
        output[length] = if c2 then Alphabet[c + 1] else 61

        length += 1
        output[length] = if c3 then Alphabet[d + 1] else 61
    end

    local newOutput = {}
    local newLength = 0

    for index = 1, length, 4096 do
        newLength += 1
        local endIndex = index + 4096 - 1
        newOutput[newLength] = string.char(table.unpack(output, index, if endIndex > length then length else endIndex))
    end

    return table.concat(newOutput)
end

function Base64.decode(input: string): string
    assert(type(input) == "string", "argument #1 must be a string")

    local output = {}
    local length = 0

    for index = 1, #input, 4 do
        local c1, c2, c3, c4 = string.byte(input, index, index + 3)

        local i1 = Indexes[c1] - 1
        local i2 = Indexes[c2] - 1
        local i3 = (Indexes[c3] or 1) - 1
        local i4 = (Indexes[c4] or 1) - 1

        local a = bit32_lshift(i1, 2) + bit32_rshift(i2, 4)
        local b = bit32_lshift(bit32_band(i2, 15), 4) + bit32_rshift(i3, 2)
        local c = bit32_lshift(bit32_band(i3, 3), 6) + i4

        length += 1
        output[length] = a

        if c3 ~= 61 then
            length += 1
            output[length] = b
        end

        if c4 ~= 61 then
            length += 1
            output[length] = c
        end
    end

    local newOutput = {}
    local newLength = 0

    for index = 1, length, 4096 do
        newLength += 1
        local endIndex = index + 4096 - 1
        newOutput[newLength] = string.char(table.unpack(output, index, if endIndex > length then length else endIndex))
    end

    return table.concat(newOutput)
end

return Base64
