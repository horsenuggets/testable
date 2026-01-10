--[[

Release

Automates the release process. Pass "major", "minor", or "patch" as an argument to bump
the corresponding version component. This script will update the VERSION file, sync the
version to wally.toml, create a git tag, publish to Wally, and create a GitHub release.

Usage: lune run Scripts/Release -- <major|minor|patch>

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local parseVersion = require("./Helpers/parseVersion")

local function release()
    local args = process.args
    if #args < 1 then
        print("Usage: lune run Scripts/Release -- <major|minor|patch>")
        process.exit(1)
    end

    local bumpType = string.lower(args[1])
    if bumpType ~= "major" and bumpType ~= "minor" and bumpType ~= "patch" then
        print(`Invalid bump type "{bumpType}". Must be "major", "minor", or "patch".`)
        process.exit(1)
    end

    -- Read current version
    local currentVersionString = fs.readFile("VERSION")
    local major, minor, patch = parseVersion(currentVersionString)

    if not major then
        print(`Could not parse current version "{currentVersionString}".`)
        process.exit(1)
    end

    local previousVersion = `{major}.{minor}.{patch}`
    print(`Current version is "{previousVersion}".`)

    -- Bump version
    if bumpType == "major" then
        major = major + 1
        minor = 0
        patch = 0
    elseif bumpType == "minor" then
        minor = minor + 1
        patch = 0
    else
        patch = patch + 1
    end

    local newVersion = `{major}.{minor}.{patch}`
    print(`Bumping to "{newVersion}".`)

    -- Write new version to VERSION file
    fs.writeFile("VERSION", newVersion .. "\n")

    -- Run SyncVersion to update wally.toml
    print("Syncing version to wally.toml.")
    local syncResult = process.exec("lune", { "run", "Scripts/SyncVersion" })
    if not syncResult.ok then
        print("Failed to sync version.")
        print(syncResult.stderr)
        process.exit(1)
    end

    -- Stage and commit version changes
    print("Committing version bump.")
    local addResult = process.exec("git", { "add", "VERSION", "wally.toml" })
    if not addResult.ok then
        print("Failed to stage version files.")
        process.exit(1)
    end

    local commitResult = process.exec("git", { "commit", "-m", `Bump version to {newVersion}` })
    if not commitResult.ok then
        print("Failed to commit version bump.")
        print(commitResult.stderr)
        process.exit(1)
    end

    -- Create git tag
    local tagName = `v{newVersion}`
    print(`Creating tag "{tagName}".`)
    local tagResult = process.exec("git", { "tag", tagName })
    if not tagResult.ok then
        print(`Failed to create tag "{tagName}".`)
        print(tagResult.stderr)
        process.exit(1)
    end

    -- Push commit and tag
    print("Pushing commit and tag.")
    local pushResult = process.exec("git", { "push" })
    if not pushResult.ok then
        print("Failed to push commit.")
        print(pushResult.stderr)
        process.exit(1)
    end

    local pushTagResult = process.exec("git", { "push", "origin", tagName })
    if not pushTagResult.ok then
        print(`Failed to push tag "{tagName}".`)
        print(pushTagResult.stderr)
        process.exit(1)
    end

    -- Publish to Wally
    print("Publishing to Wally.")
    local wallyResult = process.exec("wally", { "publish" })
    if not wallyResult.ok then
        print("Failed to publish to Wally.")
        print(wallyResult.stderr)
        process.exit(1)
    end

    -- Create GitHub release
    print("Creating GitHub release.")
    local releaseBody = `This is the release for version \`{newVersion}\`!`

    local ghResult = process.exec("gh", {
        "release",
        "create",
        tagName,
        "--title",
        tagName,
        "--notes",
        releaseBody,
    })
    if not ghResult.ok then
        print("Failed to create GitHub release.")
        print(ghResult.stderr)
        process.exit(1)
    end

    print(`Release {tagName} completed successfully.`)
end

release()
