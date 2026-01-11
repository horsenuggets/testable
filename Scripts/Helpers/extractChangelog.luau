--[[

extractChangelog

Extracts the changelog section for a specific version from CHANGELOG.md.

--]]

local fs = require("@lune/fs")

local function extractChangelog(version: string): string?
    assert(type(version) == "string", "version must be a string")

    if not fs.isFile("CHANGELOG.md") then
        return nil
    end

    local content = fs.readFile("CHANGELOG.md")

    -- Pattern to match version header and content until next version header or end
    local pattern = "## " .. version:gsub("%.", "%%.") .. "\n(.-)\n## "
    local section = string.match(content, pattern)

    if not section then
        -- Try matching to end of file (for last version in changelog)
        pattern = "## " .. version:gsub("%.", "%%.") .. "\n(.-)$"
        section = string.match(content, pattern)
    end

    if not section then
        return nil
    end

    -- Trim leading and trailing whitespace
    section = string.match(section, "^%s*(.-)%s*$")

    return section
end

return extractChangelog
