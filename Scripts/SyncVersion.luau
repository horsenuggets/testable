--[[

SyncVersion

Synchronizes the version from the VERSION file to wally.toml.

--]]

local fs = require("@lune/fs")

local function syncVersion()
    -- Read version from VERSION file
    local version = fs.readFile("VERSION")

    -- Trim whitespace from version
    version = string.match(version, `^%s*(.-)%s*$`)

    -- Read wally.toml
    local wallyContent = fs.readFile("wally.toml")

    -- Find and replace version in [package] section only
    -- Pattern matches [package] section, then finds the first version = "..." line
    local updatedContent = string.gsub(wallyContent, `(%[package%][^%[]*version%s*=%s*)"(.-)"`, function(prefix, _)
        return `{prefix}"{version}"`
    end, 1)

    -- Write updated content back to wally.toml
    fs.writeFile("wally.toml", updatedContent)

    print(`Updated wally.toml version to "{version}"!`)
end

syncVersion()
