--[[

RobloxCloudTest.spec

Runs Testable's test suite in a real Roblox cloud environment using
the Open Cloud Luau Execution API. Submits a test script to a
published place and maps each remote result to a Testable it() block.

Requires TESTABLE_CICD_ROBLOX_API_KEY in the environment. Skips gracefully when
the key is not available.

The place must have Testable published in ReplicatedStorage. Use
Scripts/PublishE2EPlace.exec.luau to build and publish it.

--]]

const fs = require("@lune/fs")
const net = require("@lune/net")
const process = require("@lune/process")
const serde = require("@lune/serde")
const task = require("@lune/task")

const UNIVERSE_ID = "10772475667"
const PLACE_ID = "114852968773810"
const BASE_URL = "https://apis.roblox.com/cloud/v2"
const POLL_INTERVAL = 3
const MAX_POLL_ATTEMPTS = 60
const REMOTE_SCRIPT_PATH = "Tests/RobloxCloud/RemoteTestScript.luau"

type TestResult = {
    Name: string,
    Passed: boolean,
    Error: string?,
}

const function _loadApiKey(): string?
    const key = process.env.TESTABLE_CICD_ROBLOX_API_KEY
    if key == nil or key == "" then
        return nil
    end
    return key
end

const function _createTask(apiKey: string, scriptSource: string): string
    const response = net.request({
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

    const decoded = serde.decode("json", response.body)
    return decoded.path
end

const function _pollTask(apiKey: string, taskPath: string): { [string]: any }
    for i = 1, MAX_POLL_ATTEMPTS do
        task.wait(POLL_INTERVAL)

        const response = net.request({
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
    const response = net.request({
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

const function _parseTestResults(logs: { string }): { TestResult }
    const results: { TestResult } = {}

    for _, line in logs do
        const passName = line:match("^%[PASS%] (.+)$")
        if passName then
            table.insert(results, {
                Name = passName,
                Passed = true,
            })
            continue
        end

        const failName, failErr = line:match("^%[FAIL%] (.+) %- (.+)$")
        if failName then
            table.insert(results, {
                Name = failName,
                Passed = false,
                Error = failErr,
            })
        end
    end

    return results
end

const function _runRemoteTests(apiKey: string): { TestResult }
    print("  Submitting Luau execution task...")
    const testScript = fs.readFile(REMOTE_SCRIPT_PATH)
    const taskPath = _createTask(apiKey, testScript)

    print("  Polling for task completion...")
    const taskResult = _pollTask(apiKey, taskPath)

    const logs = _getTaskLogs(apiKey, taskPath)

    for _, line in logs do
        print(`    {line}`)
    end

    const results = _parseTestResults(logs)

    if taskResult.state == "FAILED" and #results == 0 then
        local errorMsg = "unknown error"
        if taskResult.error then
            errorMsg = `{taskResult.error.code}: {taskResult.error.message}`
        end
        table.insert(results, {
            Name = "Module load",
            Passed = false,
            Error = errorMsg,
        })
    end

    return results
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

    const results = _runRemoteTests(apiKey)

    if #results == 0 then
        describe("Roblox Cloud", function()
            it("should have returned test results", function()
                error("No test results were parsed from remote execution logs")
            end)
        end)
        return
    end

    describe("Roblox Cloud", function()
        for _, result in results do
            it(result.Name, function()
                if not result.Passed then
                    error(result.Error or "unknown error")
                end
            end)
        end
    end)
end
