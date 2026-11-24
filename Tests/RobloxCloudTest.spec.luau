--[[

RobloxCloudTest.spec

Runs Testable's test suite in a real Roblox cloud environment using
the Open Cloud Luau Execution API. Submits a test script to the E2E
place and maps each remote result to a Testable it() block.

Requires TESTABLE_CICD_ROBLOX_API_KEY in the environment. Skips gracefully when
the key is not available.

The place is built from the current source and uploaded only when it
differs from the last upload (see Scripts/Helpers/E2EPlace.luau). The
execution task is pinned to that exact place version, so a run never
executes against a stale place or one that another run uploaded.

Every Open Cloud call goes through Scripts/Helpers/CloudRequest.luau, which retries
rate-limited and server-error responses, since many runs can share one API key.

--]]

const CloudPlace = require("../Scripts/Helpers/CloudPlace")
const CloudRequest = require("../Scripts/Helpers/CloudRequest")
const E2EPlace = require("../Scripts/Helpers/E2EPlace")
const RemoteResults = require("./Helpers/RemoteResults")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const process = require("@lune/process")
const serde = require("@lune/serde")
const task = require("@lune/task")
const describe, it = Testable.describe, Testable.it

const BASE_URL = "https://apis.roblox.com/cloud/v2"
const POLL_INTERVAL = 3
const MAX_POLL_ATTEMPTS = 60
const REMOTE_SCRIPT_PATH = "Tests/RobloxCloud/RemoteTestScript.luau"

type RemoteRun = {
    Problem: string?,
    Results: { RemoteResults.TestResult }
}

const function _loadApiKey(): string?
    const key = process.env.TESTABLE_CICD_ROBLOX_API_KEY
    if key == nil or key == "" then
        return nil
    end
    return key
end

const function _createTask(apiKey: string, scriptSource: string, versionNumber: number): string
    const response = CloudRequest.send("The execution task creation", {
        url = CloudPlace.getExecutionTaskUrl(E2EPlace.UniverseId, E2EPlace.PlaceId, versionNumber),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = apiKey
        },
        body = serde.encode("json", {
            script = scriptSource,
            timeout = "120s"
        })
    })

    if not response.ok then
        error(`Task creation failed ({response.statusCode}): {response.body}`)
    end

    const decoded = serde.decode("json", response.body)
    return decoded.path
end

const function _pollTask(apiKey: string, taskPath: string): { [string]: any }
    for i = 1, MAX_POLL_ATTEMPTS do
        task.wait(POLL_INTERVAL)

        const response = CloudRequest.send("The execution task poll", {
            url = `{BASE_URL}/{taskPath}`,
            method = "GET",
            headers = {
                ["x-api-key"] = apiKey
            }
        })

        if not response.ok then
            warn(`Poll request failed ({response.statusCode}): {response.body}`)
            continue
        end

        const decoded = serde.decode("json", response.body)
        const state = decoded.state

        if state == "COMPLETE" or state == "FAILED" then
            return decoded
        end

        if i % 5 == 0 then
            print(`  Polling... attempt {i}/{MAX_POLL_ATTEMPTS}, state: {state}`)
        end
    end

    error("Task timed out after polling limit.")
end

const function _getTaskLogs(apiKey: string, taskPath: string): { string }
    const response = CloudRequest.send("The execution task log request", {
        url = `{BASE_URL}/{taskPath}/logs`,
        method = "GET",
        headers = {
            ["x-api-key"] = apiKey
        }
    })

    if not response.ok then
        warn(`Failed to get task logs ({response.statusCode}): {response.body}`)
        return {}
    end

    const decoded = serde.decode("json", response.body)
    const logEntries = decoded.luauExecutionSessionTaskLogs
    const allMessages: { string } = {}

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

const function _runRemoteTests(apiKey: string): RemoteRun
    const versionNumber = E2EPlace.ensureCurrent(apiKey)

    print(`  Submitting Luau execution task pinned to place version {versionNumber}...`)
    const testScript = fs.readFile(REMOTE_SCRIPT_PATH)
    const taskPath = _createTask(apiKey, testScript, versionNumber)

    print("  Polling for task completion...")
    const taskResult = _pollTask(apiKey, taskPath)

    const logs = _getTaskLogs(apiKey, taskPath)

    for _, line in logs do
        print(`    {line}`)
    end

    local taskError: string? = nil
    if taskResult.state == "FAILED" then
        taskError = if taskResult.error then `{taskResult.error.code}: {taskResult.error.message}` else "unknown error"
    end

    const parsed = RemoteResults.parse(logs)

    return {
        Problem = RemoteResults.findProblem(parsed, taskError),
        Results = parsed.Results
    }
end

return function()
    const apiKey = _loadApiKey()

    if apiKey == nil then
        print("  TESTABLE_CICD_ROBLOX_API_KEY not found, Roblox cloud tests will be skipped.")
        describe("Roblox Cloud", function()
            it("skipped (no API key)", function() end)
        end)
        return
    end

    const remoteRun = _runRemoteTests(apiKey)

    describe("Roblox Cloud", function()
        -- Without this, a remote script that stopped halfway would pass with whatever
        -- checks it got through.
        it("should run the remote script to completion", function()
            if remoteRun.Problem ~= nil then
                error(remoteRun.Problem)
            end
        end)

        for _, result in remoteRun.Results do
            it(result.Name, function()
                if not result.Passed then
                    error(result.Error or "unknown error")
                end
            end)
        end
    end)
end
