local fs = require("@lune/fs")
local process = require("@lune/process")

local parseVersion = require("./Helpers/parseVersion")

local function ensureProperVersionUpdate()
    if not fs.isFile("VERSION") then
        print("VERSION file does not exist.")
        process.exit(1)
    end

    -- Read current VERSION file
    local currentVersionString = fs.readFile("VERSION")
    local currentMajor, currentMinor, currentPatch = parseVersion(currentVersionString)

    -- Validate current version format
    if not currentMajor then
        print(
            `VERSION file is not in MAJOR.MINOR.PATCH format, current content is "{string.match(
                currentVersionString,
                "^%s*(.-)%s*$"
            )}".`
        )
        process.exit(1)
    end

    print(`Current version is "{currentMajor}.{currentMinor}.{currentPatch}".`)

    -- Get previous VERSION from git
    local result = process.exec("git", { "show", "HEAD:VERSION" })

    if not result.ok then
        -- No previous version in git (likely first commit), just validate format
        print("No previous version found in git history (possibly first commit).")
        print("Version format is valid!")
        return
    end

    local previousVersionString = result.stdout
    local previousMajor, previousMinor, previousPatch = parseVersion(previousVersionString)

    if not previousMajor then
        print("Previous VERSION was not in proper format, skipping comparison.")
        print("Current version format is valid!")
        return
    end

    print(`Previous version was "{previousMajor}.{previousMinor}.{previousPatch}".`)

    -- Check if versions are identical
    if currentMajor == previousMajor and currentMinor == previousMinor and currentPatch == previousPatch then
        print("Version has not been updated from previous commit.")
        process.exit(1)
    end

    -- Validate proper semantic version bump
    -- Only one of these should be true:
    -- 1. Major bump: major+1, minor=0, patch=0
    -- 2. Minor bump: major same, minor+1, patch=0
    -- 3. Patch bump: major same, minor same, patch+1

    local isMajorBump = currentMajor == previousMajor + 1 and currentMinor == 0 and currentPatch == 0
    local isMinorBump = currentMajor == previousMajor and currentMinor == previousMinor + 1 and currentPatch == 0
    local isPatchBump = currentMajor == previousMajor
        and currentMinor == previousMinor
        and currentPatch == previousPatch + 1

    if isMajorBump then
        print("Valid major version bump.")
    elseif isMinorBump then
        print("Valid minor version bump.")
    elseif isPatchBump then
        print("Valid patch version bump.")
    else
        print("Invalid version bump, must follow semantic versioning.")
        print("Valid bumps are:")
        print(`  - Major: {previousMajor}.{previousMinor}.{previousPatch} -> {previousMajor + 1}.0.0`)
        print(`  - Minor: {previousMajor}.{previousMinor}.{previousPatch} -> {previousMajor}.{previousMinor + 1}.0`)
        print(
            `  - Patch: {previousMajor}.{previousMinor}.{previousPatch} -> {previousMajor}.{previousMinor}.{previousPatch + 1}`
        )
        process.exit(1)
    end

    print("Version update is valid!")
end

ensureProperVersionUpdate()
