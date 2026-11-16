--[[

JsonReporterTest.spec

Tests for the JSON reporter. Every document is parsed back with a real JSON decoder and
checked by structure, so the tests fail when the output stops being valid JSON and not
only when its text changes.

--]]

const JsonReporter = require("../Source/Testable/Reporters/JsonReporter")
const ResultFixture = require("./Helpers/ResultFixture")
const TestEnum = require("../Source/Testable/TestEnum")
const serde = require("@lune/serde")
const FAILURE = TestEnum.TestStatus.Failure
const SKIPPED = TestEnum.TestStatus.Skipped
const SUCCESS = TestEnum.TestStatus.Success

const function decode(results: any): any
    return serde.decode("json", JsonReporter.format(results))
end

return function()
    describe("document", function()
        it("should carry the version and the totals", function()
            const document = decode(ResultFixture.mixed())
            expect(document.Version).to.equal(1)
            expect(document.Totals.Total).to.equal(5)
            expect(document.Totals.Passed).to.equal(1)
            expect(document.Totals.Failed).to.equal(2)
            expect(document.Totals.Skipped).to.equal(2)
            expect(document.Totals.Duration).to.equal(2)
        end)

        it("should keep the shape of the results tree", function()
            const document = decode(ResultFixture.mixed())
            expect(#document.Suites).to.equal(3)

            const math = document.Suites[1]
            expect(math.Name).to.equal("MathTest")
            expect(math.FullName).to.equal("MathTest")
            expect(math.Type).to.equal("Describe")
            expect(math.Status).to.equal(FAILURE)
            expect(math.Duration).to.equal(1)
            expect(#math.Children).to.equal(2)

            const division = math.Children[2]
            expect(division.Type).to.equal("Describe")
            expect(division.FullName).to.equal("MathTest > division")
            expect(#division.Children).to.equal(2)
        end)

        it("should describe a passed test", function()
            const adds = decode(ResultFixture.mixed()).Suites[1].Children[1]
            expect(adds.Name).to.equal("adds")
            expect(adds.FullName).to.equal("MathTest > adds")
            expect(adds.Type).to.equal("It")
            expect(adds.Status).to.equal(SUCCESS)
            expect(adds.Duration).to.equal(0.25)
            expect(adds.ErrorMessage).to.equal(nil)
            expect(adds.SkipReason).to.equal(nil)
            expect(#adds.Children).to.equal(0)
        end)

        it("should give a failed test every error it recorded", function()
            const divides = decode(ResultFixture.mixed()).Suites[1].Children[2].Children[1]
            expect(divides.FullName).to.equal("MathTest > division > divides")
            expect(divides.Status).to.equal(FAILURE)
            expect(divides.Duration).to.equal(0.5)
            expect(divides.ErrorMessage).to.equal("expected 2, got 3\nstack line\nsecond error")
            expect(divides.SkipReason).to.equal(nil)
        end)

        it("should give a skipped test its reason only when it has one", function()
            const document = decode(ResultFixture.mixed())
            const rounds = document.Suites[1].Children[2].Children[2]
            expect(rounds.Status).to.equal(SKIPPED)
            expect(rounds.SkipReason).to.equal("not implemented")
            expect(rounds.ErrorMessage).to.equal(nil)
            expect(rounds.Duration).to.equal(0)

            const waits = document.Suites[3].Children[1]
            expect(waits.Status).to.equal(SKIPPED)
            expect(waits.SkipReason).to.equal(nil)
        end)

        it("should not report a skip reason on a test that wasn't skipped", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", SUCCESS, {
                    ResultFixture.it("runs", SUCCESS, { SkipReason = "stale reason" }),
                }),
            })
            expect(decode(results).Suites[1].Children[1].SkipReason).to.equal(nil)
        end)

        it("should report a describe block that failed during planning", function()
            const broken = decode(ResultFixture.mixed()).Suites[2]
            expect(broken.Type).to.equal("Describe")
            expect(broken.Status).to.equal(FAILURE)
            expect(broken.ErrorMessage).to.equal("Error during planning: boom")
            expect(#broken.Children).to.equal(0)
        end)

        it("should render results without any suites", function()
            const document = decode(ResultFixture.results({}))
            expect(#document.Suites).to.equal(0)
            expect(document.Totals.Total).to.equal(0)
            expect(document.Totals.Duration).to.equal(0)
        end)

        it("should sum child durations for nodes without a recorded duration", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", SUCCESS, {
                    ResultFixture.it("one", SUCCESS, { Duration = 0.5 }),
                    ResultFixture.it("two", SUCCESS, { Duration = 0.25 }),
                }),
            })
            const document = decode(results)
            expect(document.Suites[1].Duration).to.equal(0.75)
            expect(document.Totals.Duration).to.equal(0.75)
        end)

        it("should count a test that never ran as skipped", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", FAILURE, { ResultFixture.it("never ran", nil) }),
            })
            const document = decode(results)
            expect(document.Totals.Skipped).to.equal(1)
            expect(document.Suites[1].Children[1].Status).to.equal(SKIPPED)
        end)
    end)

    describe("encoding", function()
        it("should round-trip names with quotes, backslashes, and control characters", function()
            const name = 'quote " backslash \\ newline \n tab \t return \r bell \7 <tag> & unicode ✓'
            const results = ResultFixture.results({
                ResultFixture.describe(name, FAILURE, {
                    ResultFixture.it(name, FAILURE, { Errors = { name } }),
                }),
            })
            const test = decode(results).Suites[1].Children[1]
            expect(test.Name).to.equal(name)
            expect(test.ErrorMessage).to.equal(name)
            expect(test.FullName).to.equal(`{name} > {name}`)
        end)

        it("should strip terminal colors from error messages", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", FAILURE, {
                    ResultFixture.it("fails", FAILURE, { Errors = { "\27[91mred\27[0m plain" } }),
                }),
            })
            expect(decode(results).Suites[1].Children[1].ErrorMessage).to.equal("red plain")
        end)

        it("should replace bytes that aren't valid UTF-8", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", FAILURE, {
                    ResultFixture.it("fails", FAILURE, { Errors = { "bad \255 byte \254" } }),
                }),
            })
            expect(decode(results).Suites[1].Children[1].ErrorMessage).to.equal("bad \u{FFFD} byte \u{FFFD}")
        end)

        it("should write durations that aren't finite as zero", function()
            const results = ResultFixture.results({
                ResultFixture.describe("Spec", SUCCESS, {
                    ResultFixture.it("huge", SUCCESS, { Duration = math.huge }),
                    ResultFixture.it("nan", SUCCESS, { Duration = 0 / 0 }),
                    ResultFixture.it("negative", SUCCESS, { Duration = -1 }),
                }, { Duration = 0 }),
            }, 0)
            for _, test in decode(results).Suites[1].Children do
                expect(test.Duration).to.equal(0)
            end
        end)

        it("should encode strings as JSON literals", function()
            expect(JsonReporter.encodeString("plain")).to.equal('"plain"')
            expect(JsonReporter.encodeString('a"b\\c')).to.equal('"a\\"b\\\\c"')
            expect(JsonReporter.encodeString("a\nb\0c")).to.equal('"a\\nb\\u0000c"')
        end)
    end)

    describe("stability", function()
        it("should produce the same text for the same results", function()
            expect(JsonReporter.format(ResultFixture.mixed())).to.equal(JsonReporter.format(ResultFixture.mixed()))
        end)

        it("should write keys in a fixed order", function()
            const text = JsonReporter.format(ResultFixture.mixed())
            local position = 0
            for _, key in { "Version", "Totals", "Total", "Passed", "Failed", "Skipped", "Duration", "Suites" } do
                const found = text:find(`"{key}":`, position + 1, true)
                expect(found ~= nil).to.equal(true)
                position = found :: number
            end
            position = 0
            for _, key in { "Name", "FullName", "Type", "Status", "Duration", "Children" } do
                const found = text:find(`      "{key}":`, position + 1, true)
                expect(found ~= nil).to.equal(true)
                position = found :: number
            end
        end)

        it("should not modify the results", function()
            const results = ResultFixture.mixed()
            JsonReporter.format(results)
            expect(serde.encode("json", results)).to.equal(serde.encode("json", ResultFixture.mixed()))
        end)
    end)
end
