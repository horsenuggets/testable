--[[

RemoteResultsTest.spec

Tests for parsing what the remote test script prints inside a Roblox place. Covers the
pass, fail, and completion lines, the lines that must be ignored, and telling a complete
run apart from one that stopped early, lost results, or ended with a failed task.

--]]

const RemoteResults = require("./Helpers/RemoteResults")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

return function()
    describe("parse", function()
        it("should read passing and failing checks in order", function()
            const parsed = RemoteResults.parse({
                "[PASS] First check",
                "[FAIL] Second check - it broke",
                "[PASS] Third check",
                "[DONE] 3"
            })

            expect(parsed.Results).to.deepEqual({
                { Name = "First check", Passed = true },
                { Error = "it broke", Name = "Second check", Passed = false },
                { Name = "Third check", Passed = true }
            })
            expect(parsed.ReportedCount).to.equal(3)
        end)

        it("should keep an error whole when it spans lines or contains the separator", function()
            const parsed = RemoteResults.parse({
                "[FAIL] Check - TaskScript:10: expected 1 - 2 to be 3\nTaskScript:10\nTaskScript:4"
            })

            expect(parsed.Results).to.have.length(1)
            expect(parsed.Results[1].Name).to.equal("Check")
            expect(parsed.Results[1].Error).to.equal(
                "TaskScript:10: expected 1 - 2 to be 3\nTaskScript:10\nTaskScript:4"
            )
        end)

        it("should ignore everything that is not a result line", function()
            const parsed = RemoteResults.parse({
                "",
                "Unit Tests",
                "    [PASS] Indented lines belong to a nested report",
                "1 passed, 0 failed, 0 skipped.",
                "[PASS]",
                "[FAIL] No separator",
                "[DONE] many",
                "[DONE] 3 extra",
                "[SKIP] Something else"
            })

            expect(parsed.Results).to.have.length(0)
            expect(parsed.ReportedCount).to.equal(nil)
        end)

        it("should leave the count unset when the script never finished", function()
            const parsed = RemoteResults.parse({ "[PASS] Only check" })

            expect(parsed.Results).to.have.length(1)
            expect(parsed.ReportedCount).to.equal(nil)
        end)

        it("should return nothing for empty logs", function()
            const parsed = RemoteResults.parse({})

            expect(parsed.Results).to.have.length(0)
            expect(parsed.ReportedCount).to.equal(nil)
        end)

        it("should reject logs that are not a table", function()
            expect(function()
                RemoteResults.parse("[PASS] Check" :: any)
            end).to.throw()
        end)
    end)

    describe("findProblem", function()
        const function _createParsed(resultCount: number, reportedCount: number?): RemoteResults.Parsed
            const results = {}
            for index = 1, resultCount do
                table.insert(results, { Name = `Check {index}`, Passed = true })
            end
            return { ReportedCount = reportedCount, Results = results }
        end

        it("should find nothing wrong with a run that reported every check", function()
            expect(RemoteResults.findProblem(_createParsed(3, 3))).to.equal(nil)
            expect(RemoteResults.findProblem(_createParsed(0, 0))).to.equal(nil)
        end)

        it("should not treat failing checks as an incomplete run", function()
            const parsed = RemoteResults.parse({ "[FAIL] Check - it broke", "[DONE] 1" })

            expect(RemoteResults.findProblem(parsed)).to.equal(nil)
        end)

        it("should report a script that stopped before its last line", function()
            expect(RemoteResults.findProblem(_createParsed(2, nil))).to.equal(
                "The remote script stopped before it finished, after reporting 2 checks."
            )
            expect(RemoteResults.findProblem(_createParsed(1, nil))).to.equal(
                "The remote script stopped before it finished, after reporting 1 check."
            )
            expect(RemoteResults.findProblem(_createParsed(0, nil))).to.equal(
                "The remote script stopped before it finished, after reporting 0 checks."
            )
        end)

        it("should report results that went missing or were duplicated", function()
            expect(RemoteResults.findProblem(_createParsed(2, 3))).to.equal(
                "The remote script ran 3 checks, but the logs hold the results of 2."
            )
            expect(RemoteResults.findProblem(_createParsed(2, 1))).to.equal(
                "The remote script ran 1 check, but the logs hold the results of 2."
            )
        end)

        it("should include the error of a failed execution task", function()
            expect(RemoteResults.findProblem(_createParsed(2, nil), "SCRIPT_ERROR: it threw")).to.equal(
                "The remote script stopped before it finished, after reporting 2 checks. "
                    .. 'The execution task failed with "SCRIPT_ERROR: it threw".'
            )
            expect(RemoteResults.findProblem(_createParsed(2, 3), "DEADLINE_EXCEEDED: too slow")).to.equal(
                "The remote script ran 3 checks, but the logs hold the results of 2. "
                    .. 'The execution task failed with "DEADLINE_EXCEEDED: too slow".'
            )
        end)

        it("should report a failed execution task even when every check was reported", function()
            expect(RemoteResults.findProblem(_createParsed(2, 2), "SCRIPT_ERROR: it threw")).to.equal(
                'The remote script finished, but the execution task failed with "SCRIPT_ERROR: it threw".'
            )
        end)

        it("should walk every combination of completion, count, and task state", function()
            -- Zero stands for a script that never printed its last line.
            for _, reportedCount in { 0, 1, 2, 3 } do
                for _, hasTaskError in { false, true } do
                    const problem = RemoteResults.findProblem(
                        _createParsed(2, if reportedCount == 0 then nil else reportedCount),
                        if hasTaskError then "it failed" else nil
                    )
                    const isComplete = reportedCount == 2 and not hasTaskError
                    expect(problem == nil).to.equal(isComplete)
                end
            end
        end)
    end)
end
