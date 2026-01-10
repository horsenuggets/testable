--[[

EnsureProperVersionUpdate

Validates that the VERSION file contains a proper semantic version and that it has been
bumped correctly since the last release tag. Compares against the most recent git tag
(excluding 0.0.0) to determine if a valid version bump has occurred.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local parseVersion = require("./Helpers/parseVersion")

local function ensureProperVersionUpdate()
    assert(fs.isFile("VERSION"), "VERSION file does not exist.")

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

    -- Get the latest tag (excluding v0.0.0)
    local tagResult = process.exec("git", { "tag", "--sort=-version:refname" })

    if not tagResult.ok then
        print("Could not retrieve git tags.")
        print("Version format is valid.")
        return
    end

    -- Find the first tag that isn't 0.0.0
    local latestTag = nil
    for tag in string.gmatch(tagResult.stdout, "[^\n]+") do
        if tag ~= "0.0.0" then
            latestTag = tag
            break
        end
    end

    if not latestTag then
        print("No previous release tags found.")
        print("Version format is valid.")
        return
    end

    print(`Latest release tag is "{latestTag}".`)

    -- Get VERSION from the tag
    local versionAtTagResult = process.exec("git", { "show", `{latestTag}:VERSION` })

    if not versionAtTagResult.ok then
        print(`Could not read VERSION at tag "{latestTag}".`)
        print("Version format is valid.")
        return
    end

    local previousVersionString = versionAtTagResult.stdout
    local previousMajor, previousMinor, previousPatch = parseVersion(previousVersionString)

    if not previousMajor then
        print(`VERSION at tag "{latestTag}" was not in proper format, skipping comparison.`)
        print("Current version format is valid.")
        return
    end

    print(`Version at last release was "{previousMajor}.{previousMinor}.{previousPatch}".`)

    -- Check if versions are identical
    if currentMajor == previousMajor and currentMinor == previousMinor and currentPatch == previousPatch then
        print("Version has not been updated since last release.")
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
        print("Valid bumps are")
        print(`  Major: {previousMajor}.{previousMinor}.{previousPatch} -> {previousMajor + 1}.0.0`)
        print(`  Minor: {previousMajor}.{previousMinor}.{previousPatch} -> {previousMajor}.{previousMinor + 1}.0`)
        print(
            `  Patch: {previousMajor}.{previousMinor}.{previousPatch} -> {previousMajor}.{previousMinor}.{previousPatch + 1}`
        )
        process.exit(1)
    end

    print("Version update is valid.")
end

ensureProperVersionUpdate()
