--[[

CloudRequest

Sends Open Cloud requests and retries the ones that fail for transient reasons, such as
rate limiting when many runs share one API key. CloudRetry decides whether to retry and
how long to wait, and this module does the sending and the waiting. Both go through
dependencies that tests can replace, so the retry loop can be exercised without the
network or real delays.

--]]

const CloudRetry = require("./CloudRetry")
const net = require("@lune/net")
const task = require("@lune/task")

const BODY_PREVIEW_LENGTH = 500

export type Dependencies = {
    -- Reports a retry that is about to happen.
    Log: (message: string) -> (),
    -- Returns a random number from 0 up to 1 for the retry jitter.
    Random: () -> number,
    Request: (config: net.FetchParams) -> net.FetchResponse,
    Wait: (seconds: number) -> (),
}

const DEFAULT_DEPENDENCIES: Dependencies = table.freeze({
    Log = function(message: string)
        print(message)
    end,
    Random = function(): number
        return math.random()
    end,
    Request = function(config: net.FetchParams): net.FetchResponse
        return net.request(config)
    end,
    Wait = function(seconds: number)
        task.wait(seconds)
    end,
})

const CloudRequest = {}

const function _formatSeconds(seconds: number): string
    const text = string.format("%.1f", seconds):gsub("%.0$", "")
    return if text == "1" then "1 second" else `{text} seconds`
end

const function _formatAttempts(attempts: number): string
    return if attempts == 1 then "1 attempt" else `{attempts} attempts`
end

--[[
    Sends a request, and sends it again when the response is transient (HTTP 429 or a
    server error) until it gets another kind of response or runs out of attempts.

    The returned response is not necessarily a successful one. Failures that a retry
    won't fix, such as a bad API key, are returned for the caller to report.

    @param description - What the request does, used in messages (e.g., "The place upload")
    @param config - The request to send
    @param policy - The retry limits, which default to CloudRetry.DefaultPolicy
    @param dependencies - Replacements for the network, the clock, and logging, used by
    tests
    @return The first response that isn't transient
]]
function CloudRequest.send(
    description: string,
    config: net.FetchParams,
    policy: CloudRetry.Policy?,
    dependencies: Dependencies?
): net.FetchResponse
    assert(type(description) == "string" and description ~= "", "description must be a non-empty string")
    assert(type(config) == "table", "config must be a table")
    assert(policy == nil or type(policy) == "table", "policy must be a table or nil")
    assert(dependencies == nil or type(dependencies) == "table", "dependencies must be a table or nil")

    const resolvedDependencies = dependencies or DEFAULT_DEPENDENCIES
    const resolvedPolicy = policy or CloudRetry.DefaultPolicy

    local attempt = 1
    while true do
        const response = resolvedDependencies.Request(config)
        const decision = CloudRetry.decide(
            response.statusCode,
            response.headers,
            attempt,
            resolvedPolicy,
            resolvedDependencies.Random()
        )

        if decision.Action == "Return" then
            return response
        elseif decision.Action == "GiveUp" then
            error(
                `{description} still failed with status {response.statusCode} after {_formatAttempts(attempt)}. `
                    .. `The last response was "{string.sub(response.body, 1, BODY_PREVIEW_LENGTH)}".`,
                0
            )
        end

        resolvedDependencies.Log(
            `{description} was answered with status {response.statusCode}, so attempt {attempt + 1} of `
                .. `{resolvedPolicy.MaxAttempts} starts in {_formatSeconds(decision.Delay)}.`
        )
        resolvedDependencies.Wait(decision.Delay)
        attempt += 1
    end
end

return CloudRequest
