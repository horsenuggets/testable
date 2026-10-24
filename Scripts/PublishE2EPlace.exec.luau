#!/usr/bin/env -S lune run

--[[

PublishE2EPlace.exec

Builds and publishes the Testable E2E test place to Roblox. This
place contains the Testable source in ReplicatedStorage so remote
test scripts can require it.

[Usage] ./Scripts/PublishE2EPlace.exec.luau

--]]

const fs = require("@lune/fs")
const net = require("@lune/net")
const process = require("@lune/process")
const serde = require("@lune/serde")

const UNIVERSE_ID = "10772475667"
const PLACE_ID = "114852968773810"

const PublishE2EPlace = {}

function PublishE2EPlace.exec()
    const apiKey = process.env.TESTABLE_CICD_ROBLOX_API_KEY
    assert(apiKey ~= nil and apiKey ~= "", "TESTABLE_CICD_ROBLOX_API_KEY not found in environment.")

    if not fs.isDir("Build") then
        fs.writeDir("Build")
    end

    print("Building E2E place with Rojo...")
    const result = process.exec("rojo", {
        "build",
        "E2E.project.json",
        "--output",
        "Build/E2ETest.rbxl",
    })

    if not result.ok then
        error(`Rojo build failed: {result.stderr}`)
    end

    const placeData = fs.readFile("Build/E2ETest.rbxl")
    print(`Uploading place ({#placeData} bytes)...`)

    const response = net.request({
        url = `https://apis.roblox.com/universes/v1/{UNIVERSE_ID}/places/{PLACE_ID}/versions?versionType=Published`,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/octet-stream",
            ["x-api-key"] = apiKey,
        },
        body = placeData,
    })

    if response.ok then
        const decoded = serde.decode("json", response.body)
        print(`Place published successfully (version {decoded.versionNumber}).`)
    else
        error(`Place upload failed ({response.statusCode}): {response.body}`)
    end
end

PublishE2EPlace.exec()
