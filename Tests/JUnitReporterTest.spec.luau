--[[

JUnitReporterTest.spec

Tests for the JUnit XML reporter. Documents are parsed back with a strict XML parser and
checked by structure, which also proves that they are well formed and correctly escaped.

--]]

const JUnitReporter = require("../Source/Testable/Reporters/JUnitReporter")
const ResultFixture = require("./Helpers/ResultFixture")
const TestEnum = require("../Source/Testable/TestEnum")
const Testable = require("../Source/Testable")
const Xml = require("./Helpers/Xml")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it
const FAILURE = TestEnum.TestStatus.Failure
const SKIPPED = TestEnum.TestStatus.Skipped
const SUCCESS = TestEnum.TestStatus.Success
const HOSTILE_NAME = "less < greater > ampersand & quote \" apostrophe ' newline \n tab \t return \r ]]> ✓"

const function parse(results: any): Xml.Element
    return Xml.parse(JUnitReporter.format(results))
end

const function single(name: string, status: string?, extra: ResultFixture.Extra?): any
    return ResultFixture.results({
        ResultFixture.describe("Spec", status, { ResultFixture.it(name, status, extra) }),
    })
end

return function()
    describe("document", function()
        it("should wrap every spec root in a testsuite with totals", function()
            const root = parse(ResultFixture.mixed())
            expect(root.Name).to.equal("testsuites")
            expect(root.Attributes.tests).to.equal("5")
            expect(root.Attributes.failures).to.equal("2")
            expect(root.Attributes.errors).to.equal("0")
            expect(root.Attributes.skipped).to.equal("2")
            expect(root.Attributes.time).to.equal("2.000000")
            expect(#root.Children).to.equal(3)

            const math = root.Children[1]
            expect(math.Name).to.equal("testsuite")
            expect(math.Attributes.name).to.equal("MathTest")
            expect(math.Attributes.tests).to.equal("3")
            expect(math.Attributes.failures).to.equal("1")
            expect(math.Attributes.errors).to.equal("0")
            expect(math.Attributes.skipped).to.equal("1")
            expect(math.Attributes.time).to.equal("1.000000")
            expect(#math.Children).to.equal(3)
        end)

        it("should keep suite totals equal to the cases they contain", function()
            const root = parse(ResultFixture.mixed())
            local tests = 0
            for _, suite in root.Children do
                local failures = 0
                local skipped = 0
                for _, case in suite.Children do
                    expect(case.Name).to.equal("testcase")
                    for _, child in case.Children do
                        if child.Name == "failure" then
                            failures += 1
                        elseif child.Name == "skipped" then
                            skipped += 1
                        end
                    end
                end
                expect(suite.Attributes.tests).to.equal(tostring(#suite.Children))
                expect(suite.Attributes.failures).to.equal(tostring(failures))
                expect(suite.Attributes.skipped).to.equal(tostring(skipped))
                tests += #suite.Children
            end
            expect(root.Attributes.tests).to.equal(tostring(tests))
        end)

        it("should write a passed test as an empty testcase", function()
            const adds = parse(ResultFixture.mixed()).Children[1].Children[1]
            expect(adds.Attributes.name).to.equal("adds")
            expect(adds.Attributes.classname).to.equal("MathTest")
            expect(adds.Attributes.time).to.equal("0.250000")
            expect(#adds.Children).to.equal(0)
        end)

        it("should build the classname from the describe path", function()
            const divides = parse(ResultFixture.mixed()).Children[1].Children[2]
            expect(divides.Attributes.name).to.equal("divides")
            expect(divides.Attributes.classname).to.equal("MathTest > division")
        end)

        it("should give a failed test a failure element with the whole error", function()
            const divides = parse(ResultFixture.mixed()).Children[1].Children[2]
            expect(#divides.Children).to.equal(1)
            const failure = divides.Children[1]
            expect(failure.Name).to.equal("failure")
            expect(failure.Attributes.message).to.equal("expected 2, got 3")
            expect(failure.Attributes.type).to.equal("Failure")
            expect(failure.Text).to.equal("expected 2, got 3\nstack line\nsecond error")
        end)

        it("should give a skipped test a skipped element", function()
            const root = parse(ResultFixture.mixed())
            const rounds = root.Children[1].Children[3]
            expect(#rounds.Children).to.equal(1)
            expect(rounds.Children[1].Name).to.equal("skipped")
            expect(rounds.Children[1].Attributes.message).to.equal("not implemented")
            expect(rounds.Attributes.time).to.equal("0.000000")

            const waits = root.Children[3].Children[1]
            expect(waits.Children[1].Name).to.equal("skipped")
            expect(waits.Children[1].Attributes.message).to.equal(nil)
        end)

        it("should not mark passed or failed tests as skipped", function()
            for _, status in { SUCCESS, FAILURE } do
                const case = parse(single("runs", status, { SkipReason = "stale reason" })).Children[1].Children[1]
                for _, child in case.Children do
                    expect(child.Name == "skipped").to.equal(false)
                end
            end
        end)

        it("should report a describe block that failed during planning as a failed case", function()
            const broken = parse(ResultFixture.mixed()).Children[2]
            expect(broken.Attributes.tests).to.equal("1")
            expect(broken.Attributes.failures).to.equal("1")
            const case = broken.Children[1]
            expect(case.Attributes.name).to.equal("BrokenTest")
            expect(case.Attributes.classname).to.equal("BrokenTest")
            expect(case.Children[1].Name).to.equal("failure")
            expect(case.Children[1].Text).to.equal("Error during planning: boom")
        end)

        it("should fall back to a generic message when a failure recorded no error", function()
            const failure = parse(single("fails", FAILURE)).Children[1].Children[1].Children[1]
            expect(failure.Attributes.message).to.equal("The test failed.")
        end)

        it("should render results without any suites", function()
            const root = parse(ResultFixture.results({}))
            expect(root.Attributes.tests).to.equal("0")
            expect(#root.Children).to.equal(0)
        end)

        it("should render a suite without any cases", function()
            const root = parse(ResultFixture.results({ ResultFixture.describe("Empty", SUCCESS, {}) }))
            expect(root.Children[1].Attributes.tests).to.equal("0")
            expect(#root.Children[1].Children).to.equal(0)
        end)

        it("should produce the same text for the same results", function()
            expect(JUnitReporter.format(ResultFixture.mixed())).to.equal(JUnitReporter.format(ResultFixture.mixed()))
        end)
    end)

    describe("snapshots", function()
        const function properties(suite: Xml.Element): { [string]: string }
            expect(#suite.Children).to.equal(1)
            expect(suite.Children[1].Name).to.equal("properties")
            const values = {}
            for _, property in suite.Children[1].Children do
                expect(property.Name).to.equal("property")
                values[property.Attributes.name] = property.Attributes.value
            end
            return values
        end

        it("should add a suite without cases whose properties hold the snapshot summary", function()
            const results = ResultFixture.mixed()
            results.snapshotSummary = { Failed = 1, Matched = 2, Obsolete = {}, Removed = 3, Updated = 4, Written = 5 }

            const root = parse(results)
            expect(#root.Children).to.equal(4)
            expect(root.Attributes.tests).to.equal("5")
            expect(root.Attributes.failures).to.equal("2")

            const suite = root.Children[4]
            expect(suite.Name).to.equal("testsuite")
            expect(suite.Attributes.name).to.equal("Snapshots")
            expect(suite.Attributes.tests).to.equal("0")
            expect(suite.Attributes.failures).to.equal("0")
            expect(suite.Attributes.skipped).to.equal("0")

            const values = properties(suite)
            expect(values["snapshots.written"]).to.equal("5")
            expect(values["snapshots.updated"]).to.equal("4")
            expect(values["snapshots.removed"]).to.equal("3")
            expect(values["snapshots.obsolete"]).to.equal("0")
            expect(values["snapshots.matched"]).to.equal("2")
            expect(values["snapshots.failed"]).to.equal("1")
        end)

        it("should list each obsolete snapshot as a property of its own", function()
            const results = ResultFixture.results({})
            results.snapshotSummary = {
                Failed = 0,
                Matched = 0,
                Obsolete = {
                    { Key = "Spec > old 1", Path = "__snapshots__/Spec.snap" },
                    { Key = HOSTILE_NAME, Path = HOSTILE_NAME },
                },
                Removed = 0,
                Updated = 0,
                Written = 0,
            }

            const root = parse(results)
            expect(#root.Children).to.equal(1)
            const values = properties(root.Children[1])
            expect(values["snapshots.obsolete"]).to.equal("2")
            expect(values["snapshots.obsolete.1"]).to.equal('"Spec > old 1" in "__snapshots__/Spec.snap"')
            expect(values["snapshots.obsolete.2"]).to.equal(`"{HOSTILE_NAME}" in "{HOSTILE_NAME}"`)
        end)

        it("should leave the suite out when the run touched no snapshot", function()
            const results = ResultFixture.mixed()
            results.snapshotSummary = { Failed = 0, Matched = 0, Obsolete = {}, Removed = 0, Updated = 0, Written = 0 }

            expect(#parse(results).Children).to.equal(3)
            expect(JUnitReporter.format(results)).to.equal(JUnitReporter.format(ResultFixture.mixed()))
        end)

        it("should leave the suite out for results without a summary", function()
            expect(JUnitReporter.format(ResultFixture.mixed()):find("properties", 1, true)).to.equal(nil)
        end)

        it("should add the suite for a run that only matched snapshots", function()
            const results = ResultFixture.results({})
            results.snapshotSummary = { Failed = 0, Matched = 1, Obsolete = {}, Removed = 0, Updated = 0, Written = 0 }

            const root = parse(results)
            expect(#root.Children).to.equal(1)
            expect(properties(root.Children[1])["snapshots.matched"]).to.equal("1")
        end)
    end)

    describe("escaping", function()
        it("should round-trip hostile names in every attribute", function()
            const results = ResultFixture.results({
                ResultFixture.describe(HOSTILE_NAME, SKIPPED, {
                    ResultFixture.describe(HOSTILE_NAME, SKIPPED, {
                        ResultFixture.it(HOSTILE_NAME, SKIPPED, { SkipReason = HOSTILE_NAME }),
                    }),
                }),
            })
            const suite = parse(results).Children[1]
            const case = suite.Children[1]
            expect(suite.Attributes.name).to.equal(HOSTILE_NAME)
            expect(case.Attributes.name).to.equal(HOSTILE_NAME)
            expect(case.Attributes.classname).to.equal(`{HOSTILE_NAME} > {HOSTILE_NAME}`)
            expect(case.Children[1].Attributes.message).to.equal(HOSTILE_NAME)
        end)

        it("should round-trip hostile error text", function()
            const failure =
                parse(single("fails", FAILURE, { Errors = { HOSTILE_NAME } })).Children[1].Children[1].Children[1]
            expect(failure.Text).to.equal(HOSTILE_NAME)
            expect(failure.Attributes.message).to.equal("less < greater > ampersand & quote \" apostrophe ' newline ")
        end)

        it("should never leave raw markup characters in the output", function()
            const text = JUnitReporter.format(single(HOSTILE_NAME, FAILURE, { Errors = { HOSTILE_NAME } }))
            expect(text:find("less <", 1, true)).to.equal(nil)
            expect(text:find("ampersand & ", 1, true)).to.equal(nil)
            expect(text:find("]]>", 1, true)).to.equal(nil)
            expect(text:find('quote " apostrophe', 1, true) ~= nil).to.equal(true)
            expect(text:find("quote &quot; apostrophe &apos; newline &#10; tab &#9; return &#13;", 1, true) ~= nil).to.equal(
                true
            )
        end)

        it("should escape attribute values", function()
            expect(JUnitReporter.escapeAttribute("a<b>&\"'")).to.equal("a&lt;b&gt;&amp;&quot;&apos;")
            expect(JUnitReporter.escapeAttribute("a\nb\tc\rd")).to.equal("a&#10;b&#9;c&#13;d")
            expect(JUnitReporter.escapeAttribute("&amp;")).to.equal("&amp;amp;")
            expect(JUnitReporter.escapeAttribute("plain ✓")).to.equal("plain ✓")
        end)

        it("should escape element text and keep newlines readable", function()
            expect(JUnitReporter.escapeText("a<b>&\"'")).to.equal("a&lt;b&gt;&amp;\"'")
            expect(JUnitReporter.escapeText("a\nb\tc\rd")).to.equal("a\nb\tc&#13;d")
        end)

        it("should replace characters that XML can't represent", function()
            const replacement = "\u{FFFD}"
            expect(JUnitReporter.escapeText("a\0b\7c\31d")).to.equal(`a{replacement}b{replacement}c{replacement}d`)
            expect(JUnitReporter.escapeAttribute("\u{FFFE}\u{FFFF}")).to.equal(`{replacement}{replacement}`)
            expect(JUnitReporter.escapeText("bad \255 byte")).to.equal(`bad {replacement} byte`)
            parse(single("control \1 \27 characters", FAILURE, { Errors = { "bell \7 and \255" } }))
        end)

        it("should strip terminal colors", function()
            const failure =
                parse(single("fails", FAILURE, { Errors = { "\27[91mred\27[0m plain" } })).Children[1].Children[1].Children[1]
            expect(failure.Text).to.equal("red plain")
        end)
    end)
end
