--[[

CheckVersionMatch

Ensures that the version in VERSION file matches the version in wally.toml. Exits with
code 0 if they match, 1 if they do not.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local function checkVersionMatch()
    local versionFileContent = fs.readFile("VERSION")
    local version = string.match(versionFileContent, "^%s*(.-)%s*$")

    local wallyContent = fs.readFile("wally.toml")
    local wallyVersion = string.match(wallyContent, '%[package%][^%[]*version%s*=%s*"(.-)"')

    if not wallyVersion then
        print("Could not find version in wally.toml.")
        process.exit(1)
    end

    if version == wallyVersion then
        print(`Versions match "{version}".`)
        process.exit(0)
    else
        print(`Version mismatch. VERSION file has "{version}" but wally.toml has "{wallyVersion}".`)
        process.exit(1)
    end
end

checkVersionMatch()
