--[[

Ansi

Simple ANSI color module for terminal output. Only used when running in Lune.

--]]

const Ansi = {}

const ESCAPE = "\27["
const RESET = ESCAPE .. "0m"

const Colors = {
    BrightGreen = ESCAPE .. "92m",
    BrightRed = ESCAPE .. "91m",
    BrightYellow = ESCAPE .. "93m",
}

const IS_LUNE = pcall(function()
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
