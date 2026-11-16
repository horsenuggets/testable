--[[

CloudPlaceTest.spec

Tests for the pure decision logic that keeps the E2E test place current and pinned.
Covers content hashing, parsing and serializing the record of the last upload, deciding
whether an uploaded version can be reused, and building the upload and execution task
URLs. None of these tests touch the network or the filesystem.

--]]

const CloudPlace = require("../Scripts/Helpers/CloudPlace")
const Testable = require("../Source/Testable")
const serde = require("@lune/serde")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const HASH = CloudPlace.hashPlace("place contents")
const PLACE_ID = "222"
const UNIVERSE_ID = "111"

const function _createRecord(): CloudPlace.UploadRecord
    return {
        Hash = HASH,
        PlaceId = PLACE_ID,
        UniverseId = UNIVERSE_ID,
        VersionNumber = 7,
    }
end

return function()
    describe("hashPlace", function()
        it("should return the SHA-256 hash as lowercase hex", function()
            expect(CloudPlace.hashPlace("abc")).to.equal(
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )
        end)

        it("should return the same hash for the same contents", function()
            expect(CloudPlace.hashPlace("same")).to.equal(CloudPlace.hashPlace("same"))
        end)

        it("should return different hashes for different contents", function()
            expect(CloudPlace.hashPlace("one")).never.to.equal(CloudPlace.hashPlace("two"))
        end)

        it("should hash binary contents with embedded zero bytes", function()
            expect(CloudPlace.hashPlace("a\0b")).never.to.equal(CloudPlace.hashPlace("a\0c"))
        end)

        it("should reject contents that are not a string", function()
            expect(function()
                CloudPlace.hashPlace(nil :: any)
            end).to.throw()
        end)
    end)

    describe("decodeRecord", function()
        it("should round-trip a record through encodeRecord", function()
            const decoded = CloudPlace.decodeRecord(CloudPlace.encodeRecord(_createRecord()))

            assert(decoded ~= nil, "The record should decode.")
            expect(decoded.Hash).to.equal(HASH)
            expect(decoded.PlaceId).to.equal(PLACE_ID)
            expect(decoded.UniverseId).to.equal(UNIVERSE_ID)
            expect(decoded.VersionNumber).to.equal(7)
        end)

        it("should return nil when there is no record", function()
            expect(CloudPlace.decodeRecord(nil)).to.equal(nil)
        end)

        it("should return nil for an empty record", function()
            expect(CloudPlace.decodeRecord("")).to.equal(nil)
        end)

        it("should return nil for text that is not JSON", function()
            expect(CloudPlace.decodeRecord("{ not json")).to.equal(nil)
        end)

        it("should return nil for JSON that is not an object", function()
            expect(CloudPlace.decodeRecord("7")).to.equal(nil)
            expect(CloudPlace.decodeRecord('"text"')).to.equal(nil)
            expect(CloudPlace.decodeRecord("null")).to.equal(nil)
        end)

        it("should return nil when any field is missing", function()
            for _, field in { "Hash", "PlaceId", "UniverseId", "VersionNumber" } do
                const record: { [string]: any } = _createRecord()
                record[field] = nil

                expect(CloudPlace.decodeRecord(serde.encode("json", record))).to.equal(nil)
            end
        end)

        it("should return nil when a field has the wrong type", function()
            const wrongValues = {
                Hash = 5,
                PlaceId = 222,
                UniverseId = 111,
                VersionNumber = "7",
            }

            for field, value in wrongValues do
                const record: { [string]: any } = _createRecord()
                record[field] = value

                expect(CloudPlace.decodeRecord(serde.encode("json", record))).to.equal(nil)
            end
        end)

        it("should return nil for an empty hash", function()
            const record = _createRecord()
            record.Hash = ""

            expect(CloudPlace.decodeRecord(serde.encode("json", record))).to.equal(nil)
        end)

        it("should return nil for a version that is not a positive integer", function()
            for _, versionNumber in { 0, -1, 1.5 } do
                const record: { [string]: any } = _createRecord()
                record.VersionNumber = versionNumber

                expect(CloudPlace.decodeRecord(serde.encode("json", record))).to.equal(nil)
            end
        end)

        it("should drop unknown fields", function()
            const record: { [string]: any } = _createRecord()
            record.Extra = "ignored"

            const decoded: { [string]: any }? = CloudPlace.decodeRecord(serde.encode("json", record))

            assert(decoded ~= nil, "The record should decode.")
            expect(decoded.Extra).to.equal(nil)
        end)
    end)

    describe("encodeRecord", function()
        it("should reject a record with an invalid version", function()
            const record = _createRecord()
            record.VersionNumber = 0

            expect(function()
                CloudPlace.encodeRecord(record)
            end).to.throw()
        end)

        it("should reject a record with a missing field", function()
            const record: { [string]: any } = _createRecord()
            record.Hash = nil

            expect(function()
                CloudPlace.encodeRecord(record :: any)
            end).to.throw()
        end)
    end)

    describe("selectReusableVersion", function()
        it("should reuse the version only when the universe, place, and hash all match", function()
            -- Walk the full truth table of the three conditions.
            for _, sameUniverse in { true, false } do
                for _, samePlace in { true, false } do
                    for _, sameHash in { true, false } do
                        const version = CloudPlace.selectReusableVersion(
                            _createRecord(),
                            if sameUniverse then UNIVERSE_ID else "999",
                            if samePlace then PLACE_ID else "999",
                            if sameHash then HASH else CloudPlace.hashPlace("changed contents")
                        )

                        if sameUniverse and samePlace and sameHash then
                            expect(version).to.equal(7)
                        else
                            expect(version).to.equal(nil)
                        end
                    end
                end
            end
        end)

        it("should require an upload when there is no record", function()
            expect(CloudPlace.selectReusableVersion(nil, UNIVERSE_ID, PLACE_ID, HASH)).to.equal(nil)
        end)

        it("should require an upload when the record is corrupt", function()
            const record = CloudPlace.decodeRecord("corrupt")

            expect(CloudPlace.selectReusableVersion(record, UNIVERSE_ID, PLACE_ID, HASH)).to.equal(nil)
        end)

        it("should return the same decision for the same inputs", function()
            const first = CloudPlace.selectReusableVersion(_createRecord(), UNIVERSE_ID, PLACE_ID, HASH)
            const second = CloudPlace.selectReusableVersion(_createRecord(), UNIVERSE_ID, PLACE_ID, HASH)

            expect(first).to.equal(second)
        end)
    end)

    describe("getExecutionTaskUrl", function()
        it("should pin the task to the given version", function()
            expect(CloudPlace.getExecutionTaskUrl(UNIVERSE_ID, PLACE_ID, 7)).to.equal(
                "https://apis.roblox.com/cloud/v2/universes/111/places/222/versions/7/luau-execution-session-tasks"
            )
        end)

        it("should target the live place when no version is given", function()
            expect(CloudPlace.getExecutionTaskUrl(UNIVERSE_ID, PLACE_ID, nil)).to.equal(
                "https://apis.roblox.com/cloud/v2/universes/111/places/222/luau-execution-session-tasks"
            )
        end)

        it("should produce different URLs for different versions", function()
            expect(CloudPlace.getExecutionTaskUrl(UNIVERSE_ID, PLACE_ID, 7)).never.to.equal(
                CloudPlace.getExecutionTaskUrl(UNIVERSE_ID, PLACE_ID, 8)
            )
        end)

        it("should reject a version that is not a positive integer", function()
            for _, versionNumber in { 0, -1, 1.5, "7" :: any } do
                expect(function()
                    CloudPlace.getExecutionTaskUrl(UNIVERSE_ID, PLACE_ID, versionNumber)
                end).to.throw()
            end
        end)
    end)

    describe("getUploadUrl", function()
        it("should upload the place as a saved version", function()
            expect(CloudPlace.getUploadUrl(UNIVERSE_ID, PLACE_ID)).to.equal(
                "https://apis.roblox.com/universes/v1/111/places/222/versions?versionType=Saved"
            )
        end)
    end)
end
