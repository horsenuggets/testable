--[[

CloudPlace

Pure decision logic for keeping the E2E test place current and pinned. Decides whether a
built place file needs to be uploaded by comparing its content hash against the record of
the last upload, and builds the Open Cloud URLs that upload a place version and create a
Luau execution task pinned to one. This module performs no I/O, so the network and
filesystem calls live in E2EPlace.

--]]

const serde = require("@lune/serde")

const EXECUTION_BASE_URL = "https://apis.roblox.com/cloud/v2"
const PUBLISH_BASE_URL = "https://apis.roblox.com/universes/v1"

export type UploadRecord = {
    Hash: string,
    PlaceId: string,
    UniverseId: string,
    VersionNumber: number,
}

const CloudPlace = {}

const function _isVersionNumber(value: any): boolean
    return type(value) == "number" and value >= 1 and value % 1 == 0
end

--[[
    Parses the persisted record of the last upload. The record is only a cache, so
    anything that isn't a complete, well-formed record (a missing file, invalid JSON, or
    missing or mistyped fields) yields nil instead of an error.

    @param text - The contents of the record file, or nil if the file doesn't exist
    @return The decoded record, or nil if there is no usable record
]]
function CloudPlace.decodeRecord(text: string?): UploadRecord?
    assert(text == nil or type(text) == "string", "text must be a string or nil")

    if text == nil then
        return nil
    end

    const ok, decoded = pcall(serde.decode, "json" :: "json", text)
    if not ok or type(decoded) ~= "table" then
        return nil
    end

    if
        type(decoded.Hash) ~= "string"
        or decoded.Hash == ""
        or type(decoded.PlaceId) ~= "string"
        or type(decoded.UniverseId) ~= "string"
        or not _isVersionNumber(decoded.VersionNumber)
    then
        return nil
    end

    return {
        Hash = decoded.Hash,
        PlaceId = decoded.PlaceId,
        UniverseId = decoded.UniverseId,
        VersionNumber = decoded.VersionNumber,
    }
end

--[[
    Serializes an upload record so that decodeRecord can read it back.

    @param record - The record to serialize
    @return The JSON text to persist
]]
function CloudPlace.encodeRecord(record: UploadRecord): string
    assert(type(record) == "table", "record must be a table")
    assert(type(record.Hash) == "string", "record.Hash must be a string")
    assert(type(record.PlaceId) == "string", "record.PlaceId must be a string")
    assert(type(record.UniverseId) == "string", "record.UniverseId must be a string")
    assert(_isVersionNumber(record.VersionNumber), "record.VersionNumber must be a positive integer")

    return serde.encode("json", record, true)
end

--[[
    Returns the Open Cloud URL that creates a Luau execution task. With a version, the
    task is pinned to exactly that place version. Without one, it runs against whatever
    version of the place is currently live.

    @param universeId - The universe that owns the place
    @param placeId - The place to execute in
    @param versionNumber - The place version to pin the task to, if any
    @return The task creation URL
]]
function CloudPlace.getExecutionTaskUrl(universeId: string, placeId: string, versionNumber: number?): string
    assert(type(universeId) == "string", "universeId must be a string")
    assert(type(placeId) == "string", "placeId must be a string")
    assert(versionNumber == nil or _isVersionNumber(versionNumber), "versionNumber must be a positive integer or nil")

    const placeUrl = `{EXECUTION_BASE_URL}/universes/{universeId}/places/{placeId}`
    if versionNumber == nil then
        return `{placeUrl}/luau-execution-session-tasks`
    end

    return `{placeUrl}/versions/{versionNumber}/luau-execution-session-tasks`
end

--[[
    Returns the Open Cloud URL that uploads a place file as a new saved version. Saved
    versions can be pinned by execution tasks without replacing the live published place.

    @param universeId - The universe that owns the place
    @param placeId - The place to upload to
    @return The upload URL
]]
function CloudPlace.getUploadUrl(universeId: string, placeId: string): string
    assert(type(universeId) == "string", "universeId must be a string")
    assert(type(placeId) == "string", "placeId must be a string")

    return `{PUBLISH_BASE_URL}/{universeId}/places/{placeId}/versions?versionType=Saved`
end

--[[
    Hashes the contents of a place file.

    @param placeData - The raw bytes of the place file
    @return The SHA-256 hash as a lowercase hex string
]]
function CloudPlace.hashPlace(placeData: string): string
    assert(type(placeData) == "string", "placeData must be a string")

    return serde.hash("sha256", placeData)
end

--[[
    Decides which already uploaded version can be reused for a place file. A version is
    only reusable when the record is for the same universe and place and has the same
    content hash, since place versions are immutable once uploaded.

    @param record - The record of the last upload, or nil if there isn't one
    @param universeId - The universe the place file is destined for
    @param placeId - The place the place file is destined for
    @param hash - The content hash of the place file
    @return The version to reuse, or nil if the file must be uploaded
]]
function CloudPlace.selectReusableVersion(
    record: UploadRecord?,
    universeId: string,
    placeId: string,
    hash: string
): number?
    assert(record == nil or type(record) == "table", "record must be a table or nil")
    assert(type(universeId) == "string", "universeId must be a string")
    assert(type(placeId) == "string", "placeId must be a string")
    assert(type(hash) == "string", "hash must be a string")

    if record == nil then
        return nil
    end

    if record.UniverseId ~= universeId or record.PlaceId ~= placeId or record.Hash ~= hash then
        return nil
    end

    return record.VersionNumber
end

return CloudPlace
