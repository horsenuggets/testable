--[[

RobloxCloudTest.spec

Runs Testable's test suite in a real Roblox cloud environment using the Open Cloud Luau
Execution API. Publishes the latest E2E place, submits a test script, receives structured
results via the wire format, and displays them using the standard reporters.

Requires ROBLOX_E2E_API_KEY in the environment. Skips gracefully when the key is not
available.

--]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local PublishPlace = require("../../Source/Testable/PublishPlace")
local ResultSerializer = require("../../Source/Testable/ResultSerializer")

local UNIVERSE_ID = "9873131552"
local PLACE_ID = "93713502617477"
local BASE_URL = "https://apis.roblox.com/cloud/v2"
local POLL_INTERVAL = 3
local MAX_POLL_ATTEMPTS = 60
local REMOTE_SCRIPT_PATH = "Tests/RobloxCloudTest.spec/RemoteTestScript.luau"

local function loadApiKey(): string?
    local key = process.env.ROBLOX_E2E_API_KEY
    if key == nil or key == "" then
        return nil
    end
    return key
end

local function publishE2EPlace(apiKey: string)
    PublishPlace.publish({
        ApiKey = apiKey,
        UniverseId = UNIVERSE_ID,
        PlaceId = PLACE_ID,
        ProjectFile = "e2e.project.json",
        OutputPath = "Build/E2ETest.rbxl",
    })
end

local function createTask(apiKey: string, scriptSource: string): string
    local response = net.request({
        url = `{BASE_URL}/universes/{UNIVERSE_ID}/places/{PLACE_ID}/luau-execution-session-tasks`,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = apiKey,
        },
        body = serde.encode("json", {
            script = scriptSource,
            timeout = "120s",
        }),
    })

    if not response.ok then
        error(`Task creation failed ({response.statusCode}): {response.body}`)
    end

    local decoded = serde.decode("json", response.body)
    return decoded.path
end

local function pollTask(apiKey: string, taskPath: string): { [string]: any }
    for i = 1, MAX_POLL_ATTEMPTS do
        task.wait(POLL_INTERVAL)

        local response = net.request({
            url = `{BASE_URL}/{taskPath}`,
            method = "GET",
            headers = {
                ["x-api-key"] = apiKey,
            },
        })

        if not response.ok then
            warn(`Poll request failed ({response.statusCode}): {response.body}`)
            continue
        end

        local decoded = serde.decode("json", response.body)
        local state = decoded.state

        if state == "COMPLETE" or state == "FAILED" then
            return decoded
        end

        if i % 5 == 0 then
            print(`Polling... attempt {i}/{MAX_POLL_ATTEMPTS}, state: {state}`)
        end
    end

    error("Task timed out after polling limit.")
end

local function getTaskLogs(apiKey: string, taskPath: string): { string }
    local response = net.request({
        url = `{BASE_URL}/{taskPath}/logs`,
        method = "GET",
        headers = {
            ["x-api-key"] = apiKey,
        },
    })

    if not response.ok then
        warn(`Failed to get task logs ({response.statusCode}): {response.body}`)
        return {}
    end

    local decoded = serde.decode("json", response.body)
    local logEntries = decoded.luauExecutionSessionTaskLogs
    local allMessages: { string } = {}

    if logEntries then
        for _, entry in logEntries do
            if entry.messages then
                for _, message in entry.messages do
                    table.insert(allMessages, message)
                end
            end
        end
    end

    return allMessages
end

local function runRemoteTests(apiKey: string): any?
    -- Publish the latest E2E place first
    print("Publishing E2E place...")
    publishE2EPlace(apiKey)

    -- Submit the remote test script
    print("Submitting Luau execution task...")
    local testScript = fs.readFile(REMOTE_SCRIPT_PATH)
    local taskPath = createTask(apiKey, testScript)

    print("Polling for task completion...")
    local taskResult = pollTask(apiKey, taskPath)

    local logs = getTaskLogs(apiKey, taskPath)

    -- Try to decode structured results from the wire format
    local remoteResults = ResultSerializer.decodeFromLogs(logs)

    if remoteResults then
        return remoteResults
    end

    -- If wire format not found, the task may have failed before producing results
    if taskResult.state == "FAILED" then
        local errorMsg = "Remote execution failed"
        if taskResult.error then
            errorMsg = `{taskResult.error.code}: {taskResult.error.message}`
        end
        error(errorMsg)
    end

    -- Print raw logs for debugging if no wire format found
    for _, line in logs do
        print(line)
    end

    error("No structured results found in remote execution logs.")
end

return function()
    local apiKey = loadApiKey()

    if apiKey == nil then
        print("ROBLOX_E2E_API_KEY not found, Roblox cloud tests will be skipped.")
        describe("Roblox Cloud", function()
            it("skipped (no API key)", function() end)
        end)
        return
    end

    -- Run the remote tests and get structured results
    local ok, remoteResults = pcall(runRemoteTests, apiKey)

    if not ok then
        describe("Roblox Cloud", function()
            it("should execute remote tests successfully", function()
                error(tostring(remoteResults))
            end)
        end)
        return
    end

    -- Reconstruct the test tree from the remote results
    for _, suite in remoteResults.children do
        describe(suite.planNode.phrase, function()
            for _, child in suite.children do
                if #child.children > 0 then
                    -- Nested describe
                    describe(child.planNode.phrase, function()
                        for _, test in child.children do
                            it(test.planNode.phrase, function()
                                if test.status == "Failure" then
                                    local errMsg = if #test.errors > 0 then test.errors[1] else "Remote test failed"
                                    error(errMsg)
                                end
                            end)
                        end
                    end)
                else
                    -- Leaf test
                    it(child.planNode.phrase, function()
                        if child.status == "Failure" then
                            local errMsg = if #child.errors > 0 then child.errors[1] else "Remote test failed"
                            error(errMsg)
                        end
                    end)
                end
            end
        end)
    end
end
