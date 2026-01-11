--[[

Ansi

Simple ANSI color module for terminal output. Only used when running in Lune.

--]]

local Ansi = {}

local ESCAPE = "\27["
local RESET = ESCAPE .. "0m"

local Colors = {
    BrightGreen = ESCAPE .. "92m",
    BrightRed = ESCAPE .. "91m",
    BrightYellow = ESCAPE .. "93m",
}

local IS_LUNE = pcall(function()
    require("@lune/fs")
end)

function Ansi.isLune(): boolean
    return IS_LUNE
end

function Ansi.brightGreen(text: string): string
    return Colors.BrightGreen .. text .. RESET
end

function Ansi.brightRed(text: string): string
    return Colors.BrightRed .. text .. RESET
end

function Ansi.brightYellow(text: string): string
    return Colors.BrightYellow .. text .. RESET
end

return Ansi
