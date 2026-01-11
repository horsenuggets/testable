--[[

parseVersion

Parses a semantic version string in MAJOR.MINOR.PATCH format and returns the three
components as numbers. Returns nil for all three values if the string is not valid.
Version numbers must be between 0 and 99999.

--]]

local MAX_VERSION_NUMBER = 99999

local function parseVersion(inputVersionString: string): (number?, number?, number?)
    assert(typeof(inputVersionString) == "string", "Expected a string.")

    -- Trim whitespace
    local versionString: string = string.match(inputVersionString, "^%s*(.-)%s*$") or ""

    -- Parse MAJOR.MINOR.PATCH format
    local major, minor, patch = string.match(versionString, "^(%d+)%.(%d+)%.(%d+)$")

    if not major or not minor or not patch then
        return nil, nil, nil
    end

    local majorNum, minorNum, patchNum = tonumber(major), tonumber(minor), tonumber(patch)

    -- Validate version numbers are within reasonable bounds
    if majorNum > MAX_VERSION_NUMBER or minorNum > MAX_VERSION_NUMBER or patchNum > MAX_VERSION_NUMBER then
        print(`Version number exceeds maximum allowed value of {MAX_VERSION_NUMBER}.`)
        return nil, nil, nil
    end

    return majorNum, minorNum, patchNum
end

return parseVersion
