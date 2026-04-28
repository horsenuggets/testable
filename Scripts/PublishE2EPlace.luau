#!/usr/bin/env -S lune run

--[[

PublishE2EPlace

Builds and publishes the Testable E2E test place to Roblox. This place contains the
Testable source in ReplicatedStorage so remote test scripts can require it.

[Usage] ./Scripts/PublishE2EPlace.luau

--]]

local process = require("@lune/process")

local Dotenv = require("./Helpers/Dotenv")
local PublishPlace = require("../Source/Testable/PublishPlace")

Dotenv.load()

local function publishE2EPlace()
    local apiKey = process.env.ROBLOX_E2E_API_KEY
    assert(apiKey ~= nil and apiKey ~= "", "ROBLOX_E2E_API_KEY not found in environment.")

    PublishPlace.publish({
        ApiKey = apiKey,
        UniverseId = "9873131552",
        PlaceId = "93713502617477",
        ProjectFile = "e2e.project.json",
        OutputPath = "Build/E2ETest.rbxl",
    })
end

publishE2EPlace()
