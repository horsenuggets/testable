--[[

FocusGuardTest.spec

Tests the focus guard, which reports how many tests a focus modifier excluded and fails
the run when "ForbidFocus" is on. Each case runs in its own Testable instance so the
guard can fail that run without failing this one, and every case covers both the parallel
and sequential paths.

--]]

const IsolatedRun = require("./Helpers/IsolatedRun")
const JUnitReporter = require("../Source/Testable/Reporters/JUnitReporter")
const JsonReporter = require("../Source/Testable/Reporters/JsonReporter")
const TestEnum = require("../Source/Testable/TestEnum")
const TestSession = require("../Source/Testable/TestSession")
const Testable = require("../Source/Testable")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")
const Xml = require("./Helpers/Xml")
const serde = require("@lune/serde")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const BOOLEANS = { false, true }
const EXECUTION_MODES = {
    { Name = "parallel", Parallel = true },
    { Name = "sequential", Parallel = false },
}
-- Each body focuses one test named "focused" and leaves two others excluded.
const FOCUS_VARIANTS = {
    {
        Body = [[
            itFOCUS("focused", function() end)
            it("first excluded", function() end)
            it("second excluded", function() end)
        ]],
        Name = "itFOCUS",
    },
    {
        Body = [[
            fit("focused", function() end)
            it("first excluded", function() end)
            it("second excluded", function() end)
        ]],
        Name = "fit",
    },
    {
        Body = [[
            describeFOCUS("focused block", function()
                it("focused", function() end)
            end)
            describe("other block", function()
                it("first excluded", function() end)
            end)
            it("second excluded", function() end)
        ]],
        Name = "describeFOCUS",
    },
    {
        Body = [[
            fdescribe("focused block", function()
                it("focused", function() end)
            end)
            describe("other block", function()
                it("first excluded", function() end)
            end)
            it("second excluded", function() end)
        ]],
        Name = "fdescribe",
    },
    {
        Body = [[
            describe("focused block", function()
                FOCUS()
                describe("nested block", function()
                    it("focused", function() end)
                end)
            end)
            describe("other block", function()
                it("first excluded", function() end)
                it("second excluded", function() end)
            end)
        ]],
        Name = "FOCUS",
    },
}
const FOCUS_SUMMARY = "tests were excluded by focus."
const GUARD_ERROR = 'Focus is forbidden by "ForbidFocus"'
const TEXT_OPTIONS = { AlphabeticalSort = false, Color = false, Indent = "   ", PrintSkipped = false }
const UNFOCUSED_BODY = [[
    it("focused", function() end)
    it("first excluded", function() end)
    it("second excluded", function() end)
]]

const function contains(output: string, text: string): boolean
    return string.find(output, text, 1, true) ~= nil
end

--[[
    Runs a plan with one spec of three tests inside this process and returns its results.
    The guard is set on the plan itself, where a run keeps it, so the shared configuration
    is left alone.
]]
const function runPlan(focusPresent: boolean, guardEnabled: boolean, focusedFails: boolean): any
    const plan = Testable.TestPlanner.createPlan({
        {
            method = function()
                const declare = if focusPresent then Testable.itFOCUS else Testable.it
                declare("focused", function()
                    if focusedFails then
                        error("focused failure")
                    end
                end)
                Testable.it("first excluded", function() end)
                Testable.it("second excluded", function() end)
            end,
            path = { "GuardSpec" },
            pathStringForSorting = "guardspec",
        },
    })
    plan.forbidFocus = guardEnabled
    return Testable.TestRunner.runPlan(plan)
end

return function()
    for _, mode in EXECUTION_MODES do
        describe(`{mode.Name} execution`, function()
            it("should only fail the run when focus is present and the guard is enabled", function()
                for _, focusPresent in BOOLEANS do
                    for _, guardEnabled in BOOLEANS do
                        const outcome = IsolatedRun.run(
                            if focusPresent then FOCUS_VARIANTS[1].Body else UNFOCUSED_BODY,
                            { ForbidFocus = guardEnabled, Parallel = mode.Parallel, PrintSkipped = false }
                        )
                        const shouldFail = focusPresent and guardEnabled

                        expect(outcome.Passed).to.equal(not shouldFail)
                        expect(outcome.ExitedCleanly).to.equal(not shouldFail)
                        expect(outcome.FailureCount).to.equal(if shouldFail then 1 else 0)
                        expect(outcome.ErrorCount).to.equal(if shouldFail then 1 else 0)
                        expect(contains(outcome.Output, GUARD_ERROR)).to.equal(shouldFail)

                        -- The excluded tests are reported whether or not the guard is on.
                        expect(outcome.FocusExcludedCount).to.equal(if focusPresent then 2 else 0)
                        expect(outcome.SkippedCount).to.equal(if focusPresent then 2 else 0)
                        expect(outcome.SuccessCount).to.equal(if focusPresent then 1 else 3)
                        expect(contains(outcome.Output, `2 {FOCUS_SUMMARY}`)).to.equal(focusPresent)
                    end
                end
            end)

            for _, variant in FOCUS_VARIANTS do
                it(`should guard against "{variant.Name}"`, function()
                    for _, guardEnabled in BOOLEANS do
                        const outcome = IsolatedRun.run(
                            variant.Body,
                            { ForbidFocus = guardEnabled, Parallel = mode.Parallel, PrintSkipped = false }
                        )

                        expect(outcome.Passed).to.equal(not guardEnabled)
                        expect(outcome.FocusExcludedCount).to.equal(2)
                        expect(outcome.Nodes["focused"].Status).to.equal("Success")
                        expect(outcome.Nodes["first excluded"].Status).to.equal("Skipped")
                        expect(outcome.Nodes["first excluded"].Reason).to.equal("excluded by focus")
                        expect(outcome.Nodes["second excluded"].Status).to.equal("Skipped")
                        expect(outcome.Nodes["second excluded"].Reason).to.equal("excluded by focus")
                    end
                end)
            end

            it("should not trip on skipped and todo tests when nothing is focused", function()
                const outcome = IsolatedRun.run(
                    [[
                        it("runs", function() end)
                        itSKIP("skipped", function() end)
                        xit("also skipped", function() end, "flaky")
                        itFIXME("broken", function() end)
                        itTODO("unwritten")
                        describeSKIP("skipped block", function()
                            it("inside skipped block", function() end)
                        end)
                    ]],
                    { ForbidFocus = true, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(true)
                expect(outcome.ExitedCleanly).to.equal(true)
                expect(outcome.FailureCount).to.equal(0)
                expect(outcome.SkippedCount).to.equal(5)
                expect(outcome.FocusExcludedCount).to.equal(0)
                expect(contains(outcome.Output, "excluded by focus")).to.equal(false)
                expect(contains(outcome.Output, GUARD_ERROR)).to.equal(false)
            end)

            it("should not trip when focus excludes nothing", function()
                const outcome = IsolatedRun.run(
                    [[
                        itFOCUS("first", function() end)
                        describeFOCUS("block", function()
                            it("second", function() end)
                        end)
                    ]],
                    { ForbidFocus = true, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(true)
                expect(outcome.SuccessCount).to.equal(2)
                expect(outcome.FocusExcludedCount).to.equal(0)
            end)

            it("should not count explicitly skipped tests as excluded by focus", function()
                const outcome = IsolatedRun.run(
                    [[
                        itFOCUS("focused", function() end)
                        itSKIP("skipped", function() end, "not ready")
                        itTODO("unwritten")
                        describeFOCUS("focused block", function()
                            itSKIP("skipped inside focus", function() end)
                        end)
                    ]],
                    { ForbidFocus = true, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(true)
                expect(outcome.SkippedCount).to.equal(3)
                expect(outcome.FocusExcludedCount).to.equal(0)
                expect(outcome.Nodes["skipped"].Reason).to.equal("not ready")
                expect(outcome.Nodes["unwritten"].Reason).to.equal("todo")
                expect(outcome.Nodes["skipped inside focus"].Reason).to.equal(nil)
            end)

            it("should add the guard failure to failures from focused tests", function()
                const outcome = IsolatedRun.run(
                    [[
                        itFOCUS("focused", function()
                            error("focused failure")
                        end)
                        it("excluded", function() end)
                    ]],
                    { ForbidFocus = true, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(false)
                expect(outcome.FailureCount).to.equal(2)
                expect(outcome.ErrorCount).to.equal(2)
                expect(outcome.FocusExcludedCount).to.equal(1)
                expect(contains(outcome.Output, "focused failure")).to.equal(true)
                expect(contains(outcome.Output, "1 test was excluded by focus.")).to.equal(true)
                expect(contains(outcome.Output, "but 1 test was excluded by a focus modifier")).to.equal(true)
            end)

            it("should keep guarding when a test resets the configuration", function()
                const outcome = IsolatedRun.run(
                    [[
                        itFOCUS("focused", function()
                            Testable.resetConfig()
                        end)
                        it("excluded", function() end)
                    ]],
                    { ForbidFocus = true, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Nodes["focused"].Status).to.equal("Success")
                expect(outcome.Passed).to.equal(false)
                expect(outcome.FailureCount).to.equal(1)
            end)

            it("should keep guarding when planning resets the configuration", function()
                const outcome = IsolatedRun.run(
                    [[
                        Testable.resetConfig()
                        describe("block", function()
                            Testable.configure({ ForbidFocus = false })
                            itFOCUS("focused", function() end)
                        end)
                        it("excluded", function() end)
                    ]],
                    { ForbidFocus = true, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Nodes["focused"].Status).to.equal("Success")
                expect(outcome.Passed).to.equal(false)
                expect(outcome.FailureCount).to.equal(1)
                expect(outcome.FocusExcludedCount).to.equal(1)
            end)

            it("should stay off when planning turns the option on too late", function()
                const outcome = IsolatedRun.run(
                    [[
                        Testable.configure({ ForbidFocus = true })
                        itFOCUS("focused", function() end)
                        it("excluded", function() end)
                    ]],
                    { ForbidFocus = false, Parallel = mode.Parallel, PrintSkipped = false }
                )

                expect(outcome.Passed).to.equal(true)
                expect(outcome.FailureCount).to.equal(0)
                expect(outcome.FocusExcludedCount).to.equal(1)
            end)
        end)
    end

    describe("reports", function()
        it("should give every reporter the failure count that decides the exit code", function()
            for _, focusPresent in BOOLEANS do
                for _, guardEnabled in BOOLEANS do
                    const results = runPlan(focusPresent, guardEnabled, false)
                    const tripped = focusPresent and guardEnabled
                    const expectedFailures = if tripped then 1 else 0

                    expect(results.focusGuardFailed).to.equal(tripped)
                    expect(results.failureCount).to.equal(expectedFailures)
                    expect(#results.errors).to.equal(expectedFailures)

                    const document = serde.decode("json", JsonReporter.format(results))
                    expect(document.Totals.Failed).to.equal(results.failureCount)
                    expect(document.Totals.Passed).to.equal(results.successCount)
                    expect(document.Totals.Skipped).to.equal(results.skippedCount)
                    expect(document.Totals.Total).to.equal(
                        results.successCount + results.failureCount + results.skippedCount
                    )

                    const root = Xml.parse(JUnitReporter.format(results))
                    expect(root.Attributes.failures).to.equal(tostring(results.failureCount))
                    expect(root.Attributes.skipped).to.equal(tostring(results.skippedCount))

                    const text = table.concat(TextReporter.format(results, TEXT_OPTIONS), "\n")
                    expect(contains(text, `{expectedFailures} failed`)).to.equal(true)
                    expect(contains(text, `✗ {TestSession.FocusGuardPhrase}`)).to.equal(tripped)
                end
            end
        end)

        it("should report the tripped guard as a failed test in the JSON report", function()
            const document = serde.decode("json", JsonReporter.format(runPlan(true, true, false)))
            expect(#document.Suites).to.equal(2)
            expect(document.Suites[1].Name).to.equal("GuardSpec")
            expect(document.Suites[1].Status).to.equal("Success")

            const guard = document.Suites[2]
            expect(guard.Name).to.equal(TestSession.FocusGuardPhrase)
            expect(guard.FullName).to.equal(TestSession.FocusGuardPhrase)
            expect(guard.Type).to.equal("It")
            expect(guard.Status).to.equal("Failure")
            expect(#guard.Children).to.equal(0)
            expect(contains(guard.ErrorMessage, GUARD_ERROR)).to.equal(true)
            expect(contains(guard.ErrorMessage, "but 2 tests were excluded")).to.equal(true)
        end)

        it("should report the tripped guard as a failed testcase in the JUnit report", function()
            const root = Xml.parse(JUnitReporter.format(runPlan(true, true, false)))
            expect(root.Attributes.tests).to.equal("4")
            expect(#root.Children).to.equal(2)
            expect(root.Children[1].Attributes.failures).to.equal("0")

            const suite = root.Children[2]
            expect(suite.Attributes.name).to.equal(TestSession.FocusGuardPhrase)
            expect(suite.Attributes.tests).to.equal("1")
            expect(suite.Attributes.failures).to.equal("1")
            expect(#suite.Children).to.equal(1)

            const case = suite.Children[1]
            expect(case.Attributes.name).to.equal(TestSession.FocusGuardPhrase)
            expect(#case.Children).to.equal(1)
            expect(case.Children[1].Name).to.equal("failure")
            expect(contains(case.Children[1].Text, GUARD_ERROR)).to.equal(true)
        end)

        it("should add the guard failure to the failures of focused tests in every report", function()
            const results = runPlan(true, true, true)
            expect(results.failureCount).to.equal(2)
            expect(#results.errors).to.equal(2)
            expect(serde.decode("json", JsonReporter.format(results)).Totals.Failed).to.equal(2)
            expect(Xml.parse(JUnitReporter.format(results)).Attributes.failures).to.equal("2")
        end)

        it("should not add a guard test to reports of a run that the guard let pass", function()
            for _, results in { runPlan(true, false, false), runPlan(false, true, false) } do
                expect(results.focusGuardNode).to.equal(nil)
                expect(#serde.decode("json", JsonReporter.format(results)).Suites).to.equal(1)
                expect(#Xml.parse(JUnitReporter.format(results)).Children).to.equal(1)
            end
        end)

        it("should only record the guard failure once when the results are finalized again", function()
            const session = TestSession.new({})
            session.forbidFocus = true
            session:pushNode({ phrase = "excluded", type = TestEnum.NodeType.It })
            session:setSkipped(TestEnum.SkipReason.Focus, true)
            session:popNode()

            for _ = 1, 2 do
                const results = session:finalize()
                expect(results.focusGuardFailed).to.equal(true)
                expect(#results.children).to.equal(2)
                expect(results.failureCount).to.equal(1)
                expect(results.skippedCount).to.equal(1)
                expect(results.focusExcludedCount).to.equal(1)
                expect(#results.errors).to.equal(1)
            end
        end)
    end)

    it("should word the focus summary for every count", function()
        expect(TextReporter.formatFocusSummary(0)).to.equal(nil)
        expect(TextReporter.formatFocusSummary(1)).to.equal("1 test was excluded by focus.")
        expect(TextReporter.formatFocusSummary(2)).to.equal("2 tests were excluded by focus.")
    end)

    it("should word the guard error for one and many tests", function()
        expect(contains(TestSession.formatFocusGuardError(1), "but 1 test was excluded")).to.equal(true)
        expect(contains(TestSession.formatFocusGuardError(3), "but 3 tests were excluded")).to.equal(true)
        expect(contains(TestSession.formatFocusGuardError(1), GUARD_ERROR)).to.equal(true)
    end)

    it("should leave the summary unchanged for results without a focus count", function()
        const results = { children = {}, errors = {}, failureCount = 0, skippedCount = 0, successCount = 1 }
        const lines = TextReporter.format(
            results,
            { AlphabeticalSort = false, Color = false, Indent = "   ", PrintSkipped = false }
        )
        expect(lines[#lines]).to.equal("1 passed, 0 failed, 0 skipped.")
    end)
end
