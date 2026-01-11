--[[

CheckChangelogVersion

Validates that CHANGELOG.md contains an entry for the current VERSION.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local function checkChangelogVersion()
    -- Read current version
    if not fs.isFile("VERSION") then
        print("VERSION file not found.")
        process.exit(1)
    end

    local version = fs.readFile("VERSION")
    version = string.match(version, "^%s*(.-)%s*$")

    print(`Checking for version "{version}" in CHANGELOG.md...`)

    -- Read changelog
    if not fs.isFile("CHANGELOG.md") then
        print("CHANGELOG.md not found.")
        process.exit(1)
    end

    local changelog = fs.readFile("CHANGELOG.md")

    -- Check if version header exists
    local pattern = "## " .. version:gsub("%.", "%%.")
    if not string.find(changelog, pattern) then
        print(`CHANGELOG.md does not contain an entry for version "{version}".`)
        print("Please add a changelog section before releasing.")
        process.exit(1)
    end

    -- Check that the version section has content
    local sectionPattern = "## " .. version:gsub("%.", "%%.") .. "\n(.-)\n## "
    local section = string.match(changelog, sectionPattern)

    if not section then
        -- Try matching to end of file
        sectionPattern = "## " .. version:gsub("%.", "%%.") .. "\n(.-)$"
        section = string.match(changelog, sectionPattern)
    end

    if not section or string.match(section, "^%s*$") then
        print(`CHANGELOG.md entry for version "{version}" is empty.`)
        print("Please add changelog content before releasing.")
        process.exit(1)
    end

    print(`CHANGELOG.md contains valid entry for version "{version}".`)
end

checkChangelogVersion()
