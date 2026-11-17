--[[

CloudRetry

Pure decision logic for retrying Open Cloud requests. Decides from a response's status
code and headers whether the request is worth sending again and how long to wait first,
honoring the Retry-After header when the server sent one and backing off exponentially
otherwise. This module performs no I/O and reads no clock or random source, so the network
calls and the waiting live in CloudRequest.

--]]

const RATE_LIMITED_STATUS = 429
const RETRY_AFTER_HEADER = "retry-after"
const SERVER_ERROR_MAXIMUM = 599
const SERVER_ERROR_MINIMUM = 500

-- "Return" hands the response to the caller, because it either succeeded or failed in a
-- way that sending it again won't fix. "Retry" sends the request again after Delay
-- seconds. "GiveUp" means the response was transient but no attempts are left.
export type Action = "GiveUp" | "Retry" | "Return"

export type Decision = {
    Action: Action,
    Delay: number,
}

export type Policy = {
    -- The wait before the second attempt in seconds, which doubles for every attempt
    -- after that.
    BaseDelay: number,
    -- How many times a request is sent in total, including the first attempt.
    MaxAttempts: number,
    -- The longest wait between two attempts in seconds, whatever the server asked for.
    MaxDelay: number,
}

const DEFAULT_POLICY: Policy = table.freeze({
    BaseDelay = 2,
    MaxAttempts = 5,
    MaxDelay = 60,
})

const CloudRetry = {}

CloudRetry.DefaultPolicy = DEFAULT_POLICY

const function _isPolicy(policy: any): boolean
    return type(policy) == "table"
        and type(policy.BaseDelay) == "number"
        and policy.BaseDelay >= 0
        and type(policy.MaxAttempts) == "number"
        and policy.MaxAttempts >= 1
        and policy.MaxAttempts % 1 == 0
        and type(policy.MaxDelay) == "number"
        and policy.MaxDelay >= 0
end

--[[
    Tells whether a status code means the request may succeed if it is sent again, which
    is true for rate limiting (429) and for server errors (500 to 599).

    @param statusCode - The HTTP status code of the response
    @return True if the response is transient
]]
function CloudRetry.isTransient(statusCode: number): boolean
    assert(type(statusCode) == "number", "statusCode must be a number")

    return statusCode == RATE_LIMITED_STATUS
        or (statusCode >= SERVER_ERROR_MINIMUM and statusCode <= SERVER_ERROR_MAXIMUM)
end

--[[
    Reads how many seconds the server asked the client to wait from the Retry-After
    header. The header name is matched without regard to case. Only the delay in seconds
    form is understood, so a missing header, an HTTP date, or anything else that isn't a
    non-negative finite number yields nil.

    @param headers - The response headers, if there are any
    @return The number of seconds to wait, or nil when the header gives none
]]
function CloudRetry.parseRetryAfter(headers: { [string]: any }?): number?
    assert(headers == nil or type(headers) == "table", "headers must be a table or nil")

    if headers == nil then
        return nil
    end

    for name, value in headers do
        if type(name) ~= "string" or string.lower(name) ~= RETRY_AFTER_HEADER then
            continue
        end

        -- A header that was sent more than once arrives as a list, and the first value
        -- is the one that counts.
        const first = if type(value) == "table" then value[1] else value
        const seconds = if type(first) == "number"
            then first
            elseif type(first) == "string" then tonumber((first:match("^%s*(%d+%.?%d*)%s*$")))
            else nil

        if seconds == nil or seconds ~= seconds or seconds < 0 or seconds == math.huge then
            return nil
        end
        return seconds
    end

    return nil
end

--[[
    Decides what to do with the response to one attempt of a request.

    A response that isn't transient is returned to the caller. A transient one is retried
    while attempts remain. The wait is what the Retry-After header asked for when it is
    present, and otherwise the policy's base delay doubled for every attempt already
    made. Jitter then adds up to half of the base delay, so that clients which were
    rate limited together don't all come back at the same moment, and the result is capped
    at the policy's maximum delay.

    @param statusCode - The HTTP status code of the response
    @param headers - The response headers, if there are any
    @param attempt - Which attempt the response belongs to, starting at 1
    @param policy - The limits to retry within
    @param jitter - A random number from 0 up to 1, or nil for no jitter
    @return The action to take and the number of seconds to wait before a retry
]]
function CloudRetry.decide(
    statusCode: number,
    headers: { [string]: any }?,
    attempt: number,
    policy: Policy,
    jitter: number?
): Decision
    assert(type(statusCode) == "number", "statusCode must be a number")
    assert(headers == nil or type(headers) == "table", "headers must be a table or nil")
    assert(type(attempt) == "number" and attempt >= 1 and attempt % 1 == 0, "attempt must be a positive integer")
    assert(_isPolicy(policy), "policy must have a BaseDelay, a MaxAttempts, and a MaxDelay")
    assert(
        jitter == nil or (type(jitter) == "number" and jitter >= 0 and jitter <= 1),
        "jitter must be a number from 0 to 1 or nil"
    )

    if not CloudRetry.isTransient(statusCode) then
        return { Action = "Return", Delay = 0 }
    end

    if attempt >= policy.MaxAttempts then
        return { Action = "GiveUp", Delay = 0 }
    end

    const requested = CloudRetry.parseRetryAfter(headers)
    const base = if requested ~= nil then requested else policy.BaseDelay * 2 ^ (attempt - 1)
    const delay = base + policy.BaseDelay * 0.5 * (jitter or 0)

    return { Action = "Retry", Delay = math.min(delay, policy.MaxDelay) }
end

return CloudRetry
