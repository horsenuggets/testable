#!/usr/bin/env -S lune run

--[[

PublishE2EPlace

Builds and publishes the Testable E2E test place to Roblox. This
place contains the Testable source in ReplicatedStorage so remote
test scripts can require it.

[Usage] ./Scripts/PublishE2EPlace.luau

--]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local UNIVERSE_ID = "9873131552"
local PLACE_ID = "93713502617477"

local function publishE2EPlace()
    local apiKey = process.env.ROBLOX_E2E_API_KEY
    assert(apiKey ~= nil and apiKey ~= "", "ROBLOX_E2E_API_KEY not found in environment.")

    if not fs.isDir("Build") then
        fs.writeDir("Build")
    end

    print("Building E2E place with Rojo...")
    local result = process.exec("rojo", {
        "build",
        "E2E.project.json",
        "--output",
        "Build/E2ETest.rbxl",
    })

    if not result.ok then
        error(`Rojo build failed: {result.stderr}`)
    end

    local placeData = fs.readFile("Build/E2ETest.rbxl")
    print(`Uploading place ({#placeData} bytes)...`)

    local response = net.request({
        url = `https://apis.roblox.com/universes/v1/{UNIVERSE_ID}/places/{PLACE_ID}/versions?versionType=Published`,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/octet-stream",
            ["x-api-key"] = apiKey,
        },
        body = placeData,
    })

    if response.ok then
        local decoded = serde.decode("json", response.body)
        print(`Place published successfully (version {decoded.versionNumber}).`)
    else
        error(`Place upload failed ({response.statusCode}): {response.body}`)
    end
end

publishE2EPlace()
