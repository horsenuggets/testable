--[[

CloudRequestTest.spec

Tests for the retry loop around Open Cloud requests. The network, the waiting, the random
source, and the logging are all replaced, so these tests check what is sent, how long the
loop waits, and what it returns or throws without touching the network or the clock.

--]]

const CloudRequest = require("../Scripts/Helpers/CloudRequest")
const CloudRetry = require("../Scripts/Helpers/CloudRetry")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const CONFIG = { method = "GET" :: "GET", url = "https://example.com/resource" }
const POLICY: CloudRetry.Policy = { BaseDelay = 2, MaxAttempts = 4, MaxDelay = 30 }

type Recorder = {
    Dependencies: CloudRequest.Dependencies,
    Logs: { string },
    Requests: { any },
    Waits: { number },
}

const function _createResponse(statusCode: number, headers: { [string]: string }?, body: string?): any
    return {
        body = body or `body {statusCode}`,
        headers = headers or {},
        ok = statusCode >= 200 and statusCode < 300,
        statusCode = statusCode,
        statusMessage = "",
    }
end

--[[
    Creates dependencies that answer requests with the given responses in order and
    record everything the retry loop does with them.
]]
const function _createRecorder(responses: { any }): Recorder
    const recorder: Recorder = { Dependencies = nil :: any, Logs = {}, Requests = {}, Waits = {} }

    recorder.Dependencies = {
        Log = function(message: string)
            table.insert(recorder.Logs, message)
        end,
        Random = function(): number
            return 0
        end,
        Request = function(config: any): any
            table.insert(recorder.Requests, config)
            const response = responses[#recorder.Requests]
            assert(response ~= nil, "More requests were sent than there are responses.")
            return response
        end,
        Wait = function(seconds: number)
            table.insert(recorder.Waits, seconds)
        end,
    }

    return recorder
end

return function()
    describe("send", function()
        it("should return a successful response without waiting", function()
            const recorder = _createRecorder({ _createResponse(200) })

            const response = CloudRequest.send("The request", CONFIG, POLICY, recorder.Dependencies)

            expect(response.statusCode).to.equal(200)
            expect(recorder.Requests).to.have.length(1)
            expect(recorder.Requests[1]).to.equal(CONFIG)
            expect(recorder.Waits).to.have.length(0)
            expect(recorder.Logs).to.have.length(0)
        end)

        it("should return a failure that a retry won't fix without retrying", function()
            for _, statusCode in { 400, 401, 403, 404 } do
                const recorder = _createRecorder({ _createResponse(statusCode) })

                const response = CloudRequest.send("The request", CONFIG, POLICY, recorder.Dependencies)

                expect(response.statusCode).to.equal(statusCode)
                expect(response.ok).to.equal(false)
                expect(recorder.Requests).to.have.length(1)
                expect(recorder.Waits).to.have.length(0)
            end
        end)

        it("should retry rate-limited and failing responses until one succeeds", function()
            const recorder = _createRecorder({
                _createResponse(429),
                _createResponse(503),
                _createResponse(200, nil, "done"),
            })

            const response = CloudRequest.send("The request", CONFIG, POLICY, recorder.Dependencies)

            expect(response.body).to.equal("done")
            expect(recorder.Requests).to.deepEqual({ CONFIG, CONFIG, CONFIG })
            expect(recorder.Waits).to.deepEqual({ 2, 4 })
        end)

        it("should wait as long as the Retry-After header asks", function()
            const recorder = _createRecorder({
                _createResponse(429, { ["retry-after"] = "11" }),
                _createResponse(429, { ["Retry-After"] = "1" }),
                _createResponse(200),
            })

            CloudRequest.send("The request", CONFIG, POLICY, recorder.Dependencies)

            expect(recorder.Waits).to.deepEqual({ 11, 1 })
        end)

        it("should pass the random source on as jitter", function()
            const recorder = _createRecorder({ _createResponse(429), _createResponse(200) })
            recorder.Dependencies.Random = function(): number
                return 1
            end

            CloudRequest.send("The request", CONFIG, POLICY, recorder.Dependencies)

            expect(recorder.Waits).to.deepEqual({ 3 })
        end)

        it("should stop retrying once a retry is answered with a permanent failure", function()
            const recorder = _createRecorder({ _createResponse(429), _createResponse(403) })

            const response = CloudRequest.send("The request", CONFIG, POLICY, recorder.Dependencies)

            expect(response.statusCode).to.equal(403)
            expect(recorder.Requests).to.have.length(2)
        end)

        it("should throw a clear error when the attempts run out", function()
            const recorder = _createRecorder({
                _createResponse(429),
                _createResponse(429),
                _createResponse(500),
                _createResponse(429, nil, "Too many requests"),
            })

            const ok, message = pcall(CloudRequest.send, "The place upload", CONFIG, POLICY, recorder.Dependencies)

            expect(ok).to.equal(false)
            expect(message).to.equal(
                "The place upload still failed with status 429 after 4 attempts. "
                    .. 'The last response was "Too many requests".'
            )
            expect(recorder.Requests).to.have.length(4)
            -- There is no point in waiting after the last attempt.
            expect(recorder.Waits).to.deepEqual({ 2, 4, 8 })
        end)

        it("should send the request once with a policy of one attempt", function()
            const recorder = _createRecorder({ _createResponse(503) })
            const policy = { BaseDelay = 2, MaxAttempts = 1, MaxDelay = 30 }

            const ok, message = pcall(CloudRequest.send, "The request", CONFIG, policy, recorder.Dependencies)

            expect(ok).to.equal(false)
            expect(message).to.contain("still failed with status 503 after 1 attempt.")
            expect(recorder.Requests).to.have.length(1)
            expect(recorder.Waits).to.have.length(0)
        end)

        it("should keep the error short when the response body is huge", function()
            const recorder = _createRecorder({ _createResponse(500, nil, string.rep("x", 10000)) })
            const policy = { BaseDelay = 2, MaxAttempts = 1, MaxDelay = 30 }

            const _, message = pcall(CloudRequest.send, "The request", CONFIG, policy, recorder.Dependencies)

            expect(string.len(tostring(message))).to.be.lessThan(1000)
        end)

        it("should log every retry with the status, the next attempt, and the wait", function()
            const recorder = _createRecorder({
                _createResponse(429, { ["retry-after"] = "1" }),
                _createResponse(503),
                _createResponse(200),
            })

            CloudRequest.send("The place upload", CONFIG, POLICY, recorder.Dependencies)

            expect(recorder.Logs).to.deepEqual({
                "The place upload was answered with status 429, so attempt 2 of 4 starts in 1 second.",
                "The place upload was answered with status 503, so attempt 3 of 4 starts in 4 seconds.",
            })
        end)

        it("should use the default policy when none is given", function()
            const responses = {}
            for _ = 1, CloudRetry.DefaultPolicy.MaxAttempts do
                table.insert(responses, _createResponse(429))
            end
            const recorder = _createRecorder(responses)

            const ok = pcall(CloudRequest.send, "The request", CONFIG, nil, recorder.Dependencies)

            expect(ok).to.equal(false)
            expect(recorder.Requests).to.have.length(CloudRetry.DefaultPolicy.MaxAttempts)
        end)

        it("should reject invalid arguments before sending anything", function()
            const recorder = _createRecorder({})

            expect(function()
                CloudRequest.send("", CONFIG, POLICY, recorder.Dependencies)
            end).to.throw()
            expect(function()
                CloudRequest.send("The request", nil :: any, POLICY, recorder.Dependencies)
            end).to.throw()
            expect(recorder.Requests).to.have.length(0)
        end)
    end)
end
