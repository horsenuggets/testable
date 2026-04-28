--[[

ResultSerializer

Serializes and deserializes test results for transport across environments. Converts
the TestResults tree into a plain table suitable for JSON encoding, and reconstructs
it on the receiving side. Used by the remote execution system to pass structured results
from Roblox back to Lune.

--]]

local Base64 = require("./Base64")
local TestEnum = require("./TestEnum")

local WIRE_MAGIC = "t3st4bl3r3sults"
local WIRE_PREFIX = `TESTABLE_RESULTS::{WIRE_MAGIC}::`
local WIRE_SUFFIX = "::END"

local ResultSerializer = {}

--[[
    Recursively converts a result node into a plain table.

    @param node - A TestResults node
    @return A serializable table
]]
local function serializeNode(node: any): any
    local serialized: any = {
        Phrase = node.planNode.phrase,
        Status = node.status,
        Children = {},
        Errors = node.errors or {},
    }

    for _, child in node.children do
        table.insert(serialized.Children, serializeNode(child))
    end

    return serialized
end

--[[
    Serializes a TestResults object into a plain table suitable for JSON encoding.
    Includes the result tree, counts, and errors.

    @param results - The TestResults object from TestRunner
    @return A plain table ready for JSON encoding
]]
function ResultSerializer.serialize(results: any): any
    local serialized = {
        SuccessCount = results.successCount,
        FailureCount = results.failureCount,
        SkippedCount = results.skippedCount,
        Errors = results.errors or {},
        Children = {},
    }

    for _, child in results.children do
        table.insert(serialized.Children, serializeNode(child))
    end

    return serialized
end

--[[
    Reconstructs a result node from a deserialized table.

    @param data - A plain table from deserialization
    @return A TestResults-compatible node
]]
local function deserializeNode(data: any): any
    local node = {
        planNode = { phrase = data.Phrase },
        status = data.Status,
        children = {},
        errors = data.Errors or {},
    }

    for _, childData in data.Children do
        table.insert(node.children, deserializeNode(childData))
    end

    return node
end

--[[
    Reconstructs a TestResults object from a deserialized table.

    @param data - A plain table from JSON decoding
    @return A TestResults-compatible object
]]
function ResultSerializer.deserialize(data: any): any
    local results = {
        planNode = { phrase = "Root" },
        successCount = data.SuccessCount,
        failureCount = data.FailureCount,
        skippedCount = data.SkippedCount,
        errors = data.Errors or {},
        children = {},
    }

    for _, childData in data.Children do
        table.insert(results.children, deserializeNode(childData))
    end

    return results
end

--[[
    Encodes a serialized results table into the wire format string.
    Uses JSON encoding (HttpService on Roblox, serde on Lune) and Base64.

    @param results - The TestResults object from TestRunner
    @return The wire format string ready to be printed
]]
function ResultSerializer.encode(results: any): string
    local data = ResultSerializer.serialize(results)
    local json: string

    if game then
        json = game:GetService("HttpService"):JSONEncode(data)
    else
        local serde = require("@lune/serde")
        json = serde.encode("json", data)
    end

    local encoded = Base64.encode(json)
    return `{WIRE_PREFIX}{encoded}{WIRE_SUFFIX}`
end

--[[
    Extracts and decodes the wire format from a log line or string.
    Returns nil if the wire format is not found.

    @param text - The text to search for the wire format
    @return The deserialized TestResults object, or nil
]]
function ResultSerializer.decode(text: string): any?
    local pattern = `TESTABLE_RESULTS::{WIRE_MAGIC}::(.+)::END`
    local encoded = text:match(pattern)

    if not encoded then
        return nil
    end

    local json = Base64.decode(encoded)

    local data
    if game then
        data = game:GetService("HttpService"):JSONDecode(json)
    else
        local serde = require("@lune/serde")
        data = serde.decode("json", json)
    end

    return ResultSerializer.deserialize(data)
end

--[[
    Scans an array of log lines for the wire format and decodes it.

    @param logs - Array of log line strings
    @return The deserialized TestResults object, or nil
]]
function ResultSerializer.decodeFromLogs(logs: { string }): any?
    for _, line in logs do
        local results = ResultSerializer.decode(line)
        if results then
            return results
        end
    end
    return nil
end

ResultSerializer.WIRE_MAGIC = WIRE_MAGIC

return ResultSerializer
