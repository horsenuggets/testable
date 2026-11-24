--[[

E2EPlace

Keeps the Testable E2E test place current. Builds the place with Rojo, uploads it as a
new saved version only when its content hash differs from the last upload, and returns
the version number so that Luau execution tasks can be pinned to exactly that build.

The record of the last upload lives in the gitignored Build/ directory, which lets a
publish step hand the version to a later test step and lets repeated local runs skip the
upload. The record is only a cache, so a missing, corrupt, or outdated one just causes a
fresh upload.

The upload goes through CloudRequest, so a rate-limited or failing server is retried
before the upload is given up on.

--]]

const CloudPlace = require("./CloudPlace")
const CloudRequest = require("./CloudRequest")
const fs = require("@lune/fs")
const process = require("@lune/process")
const serde = require("@lune/serde")

const BUILD_DIRECTORY = "Build"
const PLACE_FILE_PATH = `{BUILD_DIRECTORY}/E2ETest.rbxl`
const PLACE_ID = "114852968773810"
const PROJECT_FILE_PATH = "E2E.project.json"
const RECORD_FILE_PATH = `{BUILD_DIRECTORY}/E2EPlaceUpload.json`
const UNIVERSE_ID = "10772475667"

const E2EPlace = {}

E2EPlace.PlaceId = PLACE_ID
E2EPlace.UniverseId = UNIVERSE_ID

const function _build(): string
    if not fs.isDir(BUILD_DIRECTORY) then
        fs.writeDir(BUILD_DIRECTORY)
    end

    const result = process.exec("rojo", { "build", PROJECT_FILE_PATH, "--output", PLACE_FILE_PATH })
    if not result.ok then
        error(`The Rojo build of "{PROJECT_FILE_PATH}" failed with "{result.stderr}".`)
    end

    return fs.readFile(PLACE_FILE_PATH)
end

const function _readRecord(): CloudPlace.UploadRecord?
    if not fs.isFile(RECORD_FILE_PATH) then
        return nil
    end

    return CloudPlace.decodeRecord(fs.readFile(RECORD_FILE_PATH))
end

const function _upload(apiKey: string, placeData: string): number
    -- Retrying an upload that the server did accept only leaves an extra saved version
    -- behind, and the version from the response that arrives is the one that gets pinned.
    const response = CloudRequest.send("The place upload", {
        url = CloudPlace.getUploadUrl(UNIVERSE_ID, PLACE_ID),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/octet-stream",
            ["x-api-key"] = apiKey
        },
        body = placeData
    })

    if not response.ok then
        error(`The place upload failed with status {response.statusCode} and body "{response.body}".`)
    end

    const versionNumber = serde.decode("json", response.body).versionNumber
    assert(type(versionNumber) == "number", "The place upload response did not include a version number.")

    return versionNumber
end

--[[
    Builds the E2E place and makes sure that exact build exists as a place version,
    uploading it only if it differs from the last upload.

    @param apiKey - The Open Cloud API key with the place write scope
    @return The place version number that holds the current build
]]
function E2EPlace.ensureCurrent(apiKey: string): number
    assert(type(apiKey) == "string" and apiKey ~= "", "apiKey must be a non-empty string")

    const placeData = _build()
    const hash = CloudPlace.hashPlace(placeData)

    const reusableVersion = CloudPlace.selectReusableVersion(_readRecord(), UNIVERSE_ID, PLACE_ID, hash)
    if reusableVersion ~= nil then
        print(`The E2E place is unchanged since version {reusableVersion}, so the upload is skipped.`)
        return reusableVersion
    end

    const versionNumber = _upload(apiKey, placeData)
    fs.writeFile(
        RECORD_FILE_PATH,
        CloudPlace.encodeRecord({
            Hash = hash,
            PlaceId = PLACE_ID,
            UniverseId = UNIVERSE_ID,
            VersionNumber = versionNumber
        })
    )
    print(`The E2E place was uploaded as version {versionNumber}.`)

    return versionNumber
end

return E2EPlace
