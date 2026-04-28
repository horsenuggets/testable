--[[

PublishPlace

Builds and publishes a Roblox place via the Open Cloud API. Reusable by both the
standalone PublishE2EPlace script and the RobloxCloudTest spec.

--]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local PublishPlace = {}

export type PublishOptions = {
    ApiKey: string,
    UniverseId: string,
    PlaceId: string,
    ProjectFile: string,
    OutputPath: string?,
}

--[[
    Builds a place with Rojo and publishes it to Roblox via the Open Cloud API.

    @param options - Configuration for the build and publish
    @return The version number of the published place
]]
function PublishPlace.publish(options: PublishOptions): number
    local outputPath = options.OutputPath or "Build/Place.rbxl"

    local outputDir = outputPath:match("^(.+)/[^/]+$")
    if outputDir and not fs.isDir(outputDir) then
        fs.writeDir(outputDir)
    end

    print(`Building place with Rojo ({options.ProjectFile})...`)
    local result = process.exec("rojo", {
        "build",
        options.ProjectFile,
        "--output",
        outputPath,
    })

    if not result.ok then
        error(`Rojo build failed: {result.stderr}`)
    end

    local placeData = fs.readFile(outputPath)
    print(`Uploading place ({#placeData} bytes)...`)

    local response = net.request({
        url = `https://apis.roblox.com/universes/v1/{options.UniverseId}/places/{options.PlaceId}/versions?versionType=Published`,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/octet-stream",
            ["x-api-key"] = options.ApiKey,
        },
        body = placeData,
    })

    if not response.ok then
        error(`Place upload failed ({response.statusCode}): {response.body}`)
    end

    local decoded = serde.decode("json", response.body)
    print(`Place published successfully (version {decoded.versionNumber}).`)

    return decoded.versionNumber
end

return PublishPlace
