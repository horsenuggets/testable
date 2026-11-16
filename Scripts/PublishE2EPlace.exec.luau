#!/usr/bin/env -S lune run

--[[

PublishE2EPlace.exec

Builds the Testable E2E test place and uploads it to Roblox as a new saved version. This
place contains the Testable source in ReplicatedStorage so remote test scripts can require
it. The upload is skipped when the build is identical to the last upload, and the
resulting version is recorded in Build/ so the cloud tests can pin their execution task to
it.

[Usage] ./Scripts/PublishE2EPlace.exec.luau

--]]

const E2EPlace = require("./Helpers/E2EPlace")
const process = require("@lune/process")

const PublishE2EPlace = {}

function PublishE2EPlace.exec()
    const apiKey = process.env.TESTABLE_CICD_ROBLOX_API_KEY
    assert(apiKey ~= nil and apiKey ~= "", "TESTABLE_CICD_ROBLOX_API_KEY was not found in the environment.")

    E2EPlace.ensureCurrent(apiKey)
end

PublishE2EPlace.exec()
