--[[

CloudRetryTest.spec

Tests for the pure decision logic behind retrying Open Cloud requests. Covers which status
codes are transient, reading the Retry-After header, and the decision for every
combination of status, header, and remaining attempts. None of these tests touch the
network or wait.

--]]

const CloudRetry = require("../Scripts/Helpers/CloudRetry")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const PERMANENT_STATUSES = { 200, 201, 204, 301, 400, 401, 403, 404, 409, 422, 428, 430, 499, 600 }
const POLICY: CloudRetry.Policy = { BaseDelay = 2, MaxAttempts = 4, MaxDelay = 30 }
const TRANSIENT_STATUSES = { 429, 500, 502, 503, 504, 599 }

return function()
    describe("isTransient", function()
        it("should treat rate limiting and server errors as transient", function()
            for _, statusCode in TRANSIENT_STATUSES do
                expect(CloudRetry.isTransient(statusCode)).to.equal(true)
            end
        end)

        it("should treat successes and client errors as permanent", function()
            for _, statusCode in PERMANENT_STATUSES do
                expect(CloudRetry.isTransient(statusCode)).to.equal(false)
            end
        end)

        it("should reject a status code that is not a number", function()
            expect(function()
                CloudRetry.isTransient("429" :: any)
            end).to.throw()
        end)
    end)

    describe("parseRetryAfter", function()
        it("should read a delay in seconds", function()
            expect(CloudRetry.parseRetryAfter({ ["retry-after"] = "7" })).to.equal(7)
            expect(CloudRetry.parseRetryAfter({ ["retry-after"] = "0" })).to.equal(0)
            expect(CloudRetry.parseRetryAfter({ ["retry-after"] = "1.5" })).to.equal(1.5)
            expect(CloudRetry.parseRetryAfter({ ["retry-after"] = " 12 " })).to.equal(12)
            expect(CloudRetry.parseRetryAfter({ ["retry-after"] = 3 })).to.equal(3)
        end)

        it("should match the header name without regard to case", function()
            expect(CloudRetry.parseRetryAfter({ ["Retry-After"] = "7" })).to.equal(7)
            expect(CloudRetry.parseRetryAfter({ ["RETRY-AFTER"] = "7" })).to.equal(7)
        end)

        it("should use the first value of a header that was sent more than once", function()
            expect(CloudRetry.parseRetryAfter({ ["retry-after"] = { "4", "9" } })).to.equal(4)
        end)

        it("should return nil when the header is missing", function()
            expect(CloudRetry.parseRetryAfter(nil)).to.equal(nil)
            expect(CloudRetry.parseRetryAfter({})).to.equal(nil)
            expect(CloudRetry.parseRetryAfter({ ["content-type"] = "application/json" })).to.equal(nil)
            expect(CloudRetry.parseRetryAfter({ ["x-retry-after"] = "7" })).to.equal(nil)
        end)

        it("should return nil for values that are not a delay in seconds", function()
            const values: { any } = {
                "",
                "soon",
                "-5",
                "5 seconds",
                "0x10",
                "1e3",
                "inf",
                "nan",
                "Wed, 21 Oct 2015 07:28:00 GMT",
                -1,
                math.huge,
                0 / 0,
                true,
                {},
            }
            for _, value in values do
                expect(CloudRetry.parseRetryAfter({ ["retry-after"] = value })).to.equal(nil)
            end
        end)

        it("should reject headers that are not a table", function()
            expect(function()
                CloudRetry.parseRetryAfter("retry-after: 7" :: any)
            end).to.throw()
        end)
    end)

    describe("decide", function()
        it("should return responses that are not transient, whatever else is true", function()
            for _, statusCode in PERMANENT_STATUSES do
                for _, headers in { {}, { ["retry-after"] = "7" } } do
                    for attempt = 1, POLICY.MaxAttempts + 1 do
                        const decision = CloudRetry.decide(statusCode, headers, attempt, POLICY, 0.5)
                        expect(decision.Action).to.equal("Return")
                        expect(decision.Delay).to.equal(0)
                    end
                end
            end
        end)

        it("should retry transient responses exactly while attempts remain", function()
            for _, statusCode in TRANSIENT_STATUSES do
                for _, headers in { {}, { ["retry-after"] = "7" } } do
                    for attempt = 1, POLICY.MaxAttempts + 1 do
                        const decision = CloudRetry.decide(statusCode, headers, attempt, POLICY)
                        const expected = if attempt < POLICY.MaxAttempts then "Retry" else "GiveUp"
                        expect(decision.Action).to.equal(expected)
                    end
                end
            end
        end)

        it("should not wait when giving up", function()
            const decision = CloudRetry.decide(429, { ["retry-after"] = "7" }, POLICY.MaxAttempts, POLICY, 1)
            expect(decision.Action).to.equal("GiveUp")
            expect(decision.Delay).to.equal(0)
        end)

        it("should never retry with a policy of one attempt", function()
            const policy = { BaseDelay = 2, MaxAttempts = 1, MaxDelay = 30 }
            expect(CloudRetry.decide(429, nil, 1, policy).Action).to.equal("GiveUp")
            expect(CloudRetry.decide(200, nil, 1, policy).Action).to.equal("Return")
        end)

        it("should double the wait for every attempt when there is no Retry-After header", function()
            expect(CloudRetry.decide(503, nil, 1, POLICY).Delay).to.equal(2)
            expect(CloudRetry.decide(503, {}, 2, POLICY).Delay).to.equal(4)
            expect(CloudRetry.decide(429, {}, 3, POLICY).Delay).to.equal(8)
        end)

        it("should wait as long as the Retry-After header asks, on any attempt", function()
            for attempt = 1, POLICY.MaxAttempts - 1 do
                expect(CloudRetry.decide(429, { ["Retry-After"] = "7" }, attempt, POLICY).Delay).to.equal(7)
                expect(CloudRetry.decide(503, { ["retry-after"] = "0" }, attempt, POLICY).Delay).to.equal(0)
            end
        end)

        it("should back off when the Retry-After header can't be read", function()
            expect(CloudRetry.decide(429, { ["retry-after"] = "soon" }, 2, POLICY).Delay).to.equal(4)
        end)

        it("should cap the wait at the maximum delay", function()
            const policy = { BaseDelay = 2, MaxAttempts = 10, MaxDelay = 30 }
            expect(CloudRetry.decide(429, {}, 9, policy).Delay).to.equal(30)
            expect(CloudRetry.decide(429, { ["retry-after"] = "3600" }, 1, policy).Delay).to.equal(30)
            expect(CloudRetry.decide(429, { ["retry-after"] = "30" }, 1, policy, 1).Delay).to.equal(30)
        end)

        it("should add up to half of the base delay as jitter", function()
            expect(CloudRetry.decide(429, {}, 1, POLICY, 0).Delay).to.equal(2)
            expect(CloudRetry.decide(429, {}, 1, POLICY, 0.5).Delay).to.equal(2.5)
            expect(CloudRetry.decide(429, {}, 1, POLICY, 1).Delay).to.equal(3)
            expect(CloudRetry.decide(429, { ["retry-after"] = "7" }, 1, POLICY, 1).Delay).to.equal(8)
        end)

        it("should never wait less than the Retry-After header asks unless the cap applies", function()
            for _, jitter in { 0, 0.25, 0.999 } do
                for _, seconds in { 0, 1, 7, 29 } do
                    const headers = { ["retry-after"] = tostring(seconds) }
                    const delay = CloudRetry.decide(429, headers, 1, POLICY, jitter).Delay
                    expect(delay).to.be.greaterThanOrEqual(seconds)
                    expect(delay).to.be.lessThanOrEqual(POLICY.MaxDelay)
                end
            end
        end)

        it("should give the same decision for the same inputs", function()
            const first = CloudRetry.decide(429, { ["retry-after"] = "7" }, 2, POLICY, 0.3)
            const second = CloudRetry.decide(429, { ["retry-after"] = "7" }, 2, POLICY, 0.3)
            expect(first).to.deepEqual(second)
        end)

        it("should reject invalid arguments", function()
            const calls: { () -> any } = {
                function()
                    return CloudRetry.decide("429" :: any, {}, 1, POLICY)
                end,
                function()
                    return CloudRetry.decide(429, "headers" :: any, 1, POLICY)
                end,
                function()
                    return CloudRetry.decide(429, {}, 0, POLICY)
                end,
                function()
                    return CloudRetry.decide(429, {}, 1.5, POLICY)
                end,
                function()
                    return CloudRetry.decide(429, {}, 1, {} :: any)
                end,
                function()
                    return CloudRetry.decide(429, {}, 1, { BaseDelay = 2, MaxAttempts = 0, MaxDelay = 30 })
                end,
                function()
                    return CloudRetry.decide(429, {}, 1, POLICY, 2)
                end,
            }
            for _, call in calls do
                expect(call).to.throw()
            end
        end)
    end)

    describe("DefaultPolicy", function()
        it("should bound the number of attempts and the wait", function()
            expect(CloudRetry.DefaultPolicy.MaxAttempts).to.be.greaterThan(1)
            expect(CloudRetry.DefaultPolicy.MaxAttempts).to.be.lessThanOrEqual(10)
            expect(CloudRetry.DefaultPolicy.MaxDelay).to.be.lessThanOrEqual(120)
            expect(CloudRetry.DefaultPolicy.BaseDelay).to.be.greaterThan(0)
        end)

        it("should be frozen", function()
            expect(table.isfrozen(CloudRetry.DefaultPolicy)).to.equal(true)
        end)
    end)
end
