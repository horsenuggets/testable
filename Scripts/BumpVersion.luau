--[[

BumpVersion

Bumps the version in VERSION file and syncs it to wally.toml. Pass "major", "minor", or
"patch" as an argument to bump the corresponding version component.

[Usage] lune run Scripts/BumpVersion <major|minor|patch>

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local parseVersion = require("./Helpers/parseVersion")

local function bumpVersion()
    local args = process.args
    if #args < 1 then
        print("[Usage] lune run Scripts/BumpVersion <major|minor|patch>")
        process.exit(1)
    end

    local bumpType = string.lower(args[1])
    if bumpType ~= "major" and bumpType ~= "minor" and bumpType ~= "patch" then
        print(`Invalid bump type "{bumpType}". Must be "major", "minor", or "patch".`)
        process.exit(1)
    end

    local currentVersionString = fs.readFile("VERSION")
    local major, minor, patch = parseVersion(currentVersionString)

    if not major then
        print(`Could not parse current version "{currentVersionString}".`)
        process.exit(1)
    end

    local previousVersion = `{major}.{minor}.{patch}`
    print(`Current version is "{previousVersion}".`)

    if bumpType == "major" then
        major += 1
        minor = 0
        patch = 0
    elseif bumpType == "minor" then
        minor += 1
        patch = 0
    else
        patch += 1
    end

    local newVersion = `{major}.{minor}.{patch}`
    print(`Bumping to "{newVersion}".`)

    fs.writeFile("VERSION", newVersion .. "\n")

    print("Syncing version to wally.toml.")
    local syncResult = process.exec("lune", { "run", "Scripts/SyncVersion" })
    if not syncResult.ok then
        print("Failed to sync version.")
        print(syncResult.stderr)
        process.exit(1)
    end

    print("Done.")
end

bumpVersion()
