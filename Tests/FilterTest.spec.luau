--[[

FilterTest.spec

Tests for the test name filter, covering plain substring matching against full test
names, how the filter narrows a plan before focus applies, how filtered-out tests are
reported, the Config.Filter option, and the error raised when a filter selects nothing.

--]]

const Config = require("../Source/Testable/Config")
const TestEnum = require("../Source/Testable/TestEnum")
const TestFilter = require("../Source/Testable/TestFilter")
const TestPlanner = require("../Source/Testable/TestPlanner")
const TestRunner = require("../Source/Testable/TestRunner")
const TextReporter = require("../Source/Testable/Reporters/TextReporter")
const ToolError = require("../Source/Testable/ToolError")
const REPORTER_OPTIONS: TextReporter.Options = {
    AlphabeticalSort = false,
    Color = false,
    Indent = "   ",
    PrintSkipped = false,
}
const SKIPPED = TestEnum.TestStatus.Skipped
const SUCCESS = TestEnum.TestStatus.Success

--[[
    Plans a single module named "Suite" with the given body and filter.
]]
const function createPlan(filter: string?, body: () -> ()): any
    return TestPlanner.createPlan({ { method = body, path = { "Suite" }, pathStringForSorting = "suite" } }, filter)
end

--[[
    Plans and runs a single module, returning the results and each test's status keyed
    by its full name.
]]
const function runSuite(filter: string?, body: () -> ()): (any, { [string]: string })
    const results = TestRunner.runPlan(createPlan(filter, body))
    const statuses = {}
    results:visitAllNodes(function(node)
        if node.planNode.type == TestEnum.NodeType.It then
            statuses[node.planNode:getFullName()] = node.status
        end
    end)
    return results, statuses
end

const function nestedSuite()
    describe("outer", function()
        it("runs first", function() end)

        describe("inner", function()
            it("runs second", function() end)
        end)
    end)

    describe("other", function()
        it("runs third", function() end)
    end)
end

return function()
    describe("TestFilter.matches", function()
        it("should select every name when there is no filter", function()
            expect(TestFilter.matches("Suite outer runs", nil)).to.equal(true)
            expect(TestFilter.matches("Suite outer runs", "")).to.equal(true)
        end)

        it("should select names that contain the filter", function()
            expect(TestFilter.matches("Suite outer runs", "outer")).to.equal(true)
            expect(TestFilter.matches("Suite outer runs", "Suite outer runs")).to.equal(true)
            expect(TestFilter.matches("Suite outer runs", "ter ru")).to.equal(true)
        end)

        it("should not select names that lack the filter", function()
            expect(TestFilter.matches("Suite outer runs", "inner")).to.equal(false)
            expect(TestFilter.matches("Suite outer runs", "outer  runs")).to.equal(false)
            expect(TestFilter.matches("Suite outer runs", "OUTER")).to.equal(false)
        end)

        it("should treat the filter as plain text instead of a Luau pattern", function()
            expect(TestFilter.matches("adds 12 items", "%d+")).to.equal(false)
            expect(TestFilter.matches("abc", "a.c")).to.equal(false)
            expect(TestFilter.matches("abc", "^abc$")).to.equal(false)
            expect(TestFilter.matches("costs 100% (roughly)", "100% (")).to.equal(true)
            expect(TestFilter.matches("uses a.c and [x]", "a.c and [x]")).to.equal(true)
        end)

        it("should return the same answer when called twice", function()
            expect(TestFilter.matches("Suite outer runs", "outer")).to.equal(
                TestFilter.matches("Suite outer runs", "outer")
            )
        end)
    end)

    describe("filtering a plan", function()
        it("should run everything without a filter", function()
            const results, statuses = runSuite(nil, nestedSuite)

            expect(results.successCount).to.equal(3)
            expect(results.skippedCount).to.equal(0)
            expect(results.filteredCount).to.equal(0)
            expect(statuses["Suite outer runs first"]).to.equal(SUCCESS)
        end)

        it("should treat an empty filter as no filter", function()
            const results = runSuite("", nestedSuite)

            expect(results.successCount).to.equal(3)
            expect(results.filteredCount).to.equal(0)
        end)

        it("should match the module name, describe path, and test name joined by spaces", function()
            const results, statuses = runSuite("Suite outer inner runs second", nestedSuite)

            expect(results.successCount).to.equal(1)
            expect(statuses["Suite outer inner runs second"]).to.equal(SUCCESS)
            expect(statuses["Suite outer runs first"]).to.equal(SKIPPED)
            expect(statuses["Suite other runs third"]).to.equal(SKIPPED)
        end)

        it("should select every test under a describe whose name matches", function()
            const results, statuses = runSuite("outer", nestedSuite)

            expect(results.successCount).to.equal(2)
            expect(statuses["Suite outer runs first"]).to.equal(SUCCESS)
            expect(statuses["Suite outer inner runs second"]).to.equal(SUCCESS)
            expect(statuses["Suite other runs third"]).to.equal(SKIPPED)
        end)

        it("should report filtered-out tests as skipped and count them separately", function()
            const results = runSuite("runs", function()
                it("runs", function() end)
                xit("runs later", function() end)
                it("is left out", function() end)
                it("is also left out", function() end)
            end)

            expect(results.successCount).to.equal(1)
            expect(results.failureCount).to.equal(0)
            expect(results.skippedCount).to.equal(3)
            expect(results.filteredCount).to.equal(2)
        end)

        it("should give only filtered-out tests the filter's skip reason", function()
            const results = runSuite("runs", function()
                it("runs", function() end)
                xit("runs later", function() end)
                it("is left out", function() end)
            end)
            const reasons = {}
            results:visitAllNodes(function(node)
                reasons[node.planNode.phrase] = node.skipReason
            end)

            expect(reasons["is left out"]).to.equal(TestEnum.SkipReason.Filter)
            expect(TestEnum.SkipReason.Filter).to.equal("excluded by filter")
            expect(reasons["runs later"]).to.equal(nil)
            expect(reasons["runs"]).to.equal(nil)
        end)

        it("should not run the body of a filtered-out test", function()
            local ran = false
            runSuite("kept", function()
                it("kept", function() end)
                it("dropped", function()
                    ran = true
                end)
            end)

            expect(ran).to.equal(false)
        end)

        it("should leave node modifiers alone", function()
            const plan = createPlan("first", nestedSuite)
            const changed = plan:findNodes(function(node)
                return node.modifier ~= TestEnum.NodeModifier.None
            end)

            expect(#changed).to.equal(0)
            expect(plan.filter).to.equal("first")
        end)

        it("should count what the filter selected", function()
            const plan = createPlan(nil, nestedSuite)

            const all = TestFilter.apply(plan, nil)
            expect(all.Total).to.equal(3)
            expect(all.Matched).to.equal(3)
            expect(TestFilter.isEmpty(all, nil)).to.equal(false)

            const some = TestFilter.apply(plan, "inner")
            expect(some.Total).to.equal(3)
            expect(some.Matched).to.equal(1)
            expect(TestFilter.isEmpty(some, "inner")).to.equal(false)

            const none = TestFilter.apply(plan, "missing")
            expect(none.Matched).to.equal(0)
            expect(TestFilter.isEmpty(none, "missing")).to.equal(true)

            -- Applying no filter again clears the earlier marks
            TestFilter.apply(plan, nil)
            expect(#plan:findNodes(function(node)
                return node.filteredOut == true
            end)).to.equal(0)
        end)
    end)

    describe("filter and focus together", function()
        it("should narrow by filter first and by focus second in every combination", function()
            for _, focusFirst in { false, true } do
                for _, focusSecond in { false, true } do
                    for _, matchFirst in { false, true } do
                        for _, matchSecond in { false, true } do
                            const firstName = if matchFirst then "keep first" else "drop first"
                            const secondName = if matchSecond then "keep second" else "drop second"
                            const body = function()
                                const first: any = if focusFirst then fit else it
                                const second: any = if focusSecond then fit else it
                                first(firstName, function() end)
                                second(secondName, function() end)
                            end
                            const case = `{focusFirst} {focusSecond} {matchFirst} {matchSecond}`

                            if not matchFirst and not matchSecond then
                                const ok, problem = pcall(runSuite, "keep", body)
                                expect(ok).to.equal(false)
                                expect(ToolError.is(problem)).to.equal(true)
                                continue
                            end

                            const focusActive = (focusFirst and matchFirst) or (focusSecond and matchSecond)
                            const firstRuns = matchFirst and (focusFirst or not focusActive)
                            const secondRuns = matchSecond and (focusSecond or not focusActive)
                            const _, statuses = runSuite("keep", body)

                            if statuses[`Suite {firstName}`] ~= (if firstRuns then SUCCESS else SKIPPED) then
                                error(`The first test has the wrong status in case "{case}".`)
                            end
                            if statuses[`Suite {secondName}`] ~= (if secondRuns then SUCCESS else SKIPPED) then
                                error(`The second test has the wrong status in case "{case}".`)
                            end
                        end
                    end
                end
            end
        end)

        it("should only count focus-excluded tests as skipped, not as filtered", function()
            const results = runSuite("keep", function()
                fit("keep focused", function() end)
                it("keep plain", function() end)
                it("drop", function() end)
            end)

            expect(results.successCount).to.equal(1)
            expect(results.skippedCount).to.equal(2)
            expect(results.filteredCount).to.equal(1)
        end)

        it("should apply a focused describe only to the tests the filter left in it", function()
            const _, statuses = runSuite("keep", function()
                fdescribe("focused", function()
                    it("keep inside", function() end)
                    it("drop inside", function() end)
                end)
                it("keep outside", function() end)
            end)

            expect(statuses["Suite focused keep inside"]).to.equal(SUCCESS)
            expect(statuses["Suite focused drop inside"]).to.equal(SKIPPED)
            expect(statuses["Suite keep outside"]).to.equal(SKIPPED)
        end)

        it("should ignore a focused describe that holds no selected tests", function()
            const _, statuses = runSuite("keep", function()
                fdescribe("focused", function()
                    it("drop inside", function() end)
                end)
                it("keep outside", function() end)
            end)

            expect(statuses["Suite focused drop inside"]).to.equal(SKIPPED)
            expect(statuses["Suite keep outside"]).to.equal(SUCCESS)
        end)

        it("should keep focus working when there is no filter", function()
            const _, statuses = runSuite(nil, function()
                fit("focused", function() end)
                it("plain", function() end)
            end)

            expect(statuses["Suite focused"]).to.equal(SUCCESS)
            expect(statuses["Suite plain"]).to.equal(SKIPPED)
        end)

        it("should keep skipped tests skipped when the filter selects them", function()
            const results, statuses = runSuite("keep", function()
                xit("keep skipped", function() end)
                it("keep plain", function() end)
            end)

            expect(statuses["Suite keep skipped"]).to.equal(SKIPPED)
            expect(statuses["Suite keep plain"]).to.equal(SUCCESS)
            expect(results.filteredCount).to.equal(0)
        end)
    end)

    describe("a filter that selects nothing", function()
        it("should throw an EmptyFilter tool error instead of producing a plan", function()
            const ok, problem = pcall(createPlan, "missing", nestedSuite)

            expect(ok).to.equal(false)
            expect(ToolError.is(problem)).to.equal(true)
            expect(problem.Kind).to.equal(ToolError.Kind.EmptyFilter)
            expect(problem.Message).to.equal('The filter "missing" did not match any of the 3 planned tests.')
        end)

        it("should use the singular when a single test was planned", function()
            const _, problem = pcall(createPlan, "missing", function()
                it("only", function() end)
            end)

            expect(problem.Message).to.equal('The filter "missing" did not match any of the 1 planned test.')
        end)

        it("should not throw when the filter selects at least one test", function()
            expect(function()
                createPlan("third", nestedSuite)
            end).never.to.throw()
        end)

        it("should not throw without a filter even when no tests are planned", function()
            expect(function()
                createPlan(nil, function() end)
                createPlan("", function() end)
            end).never.to.throw()
        end)

        it("should let planning errors surface as failures instead", function()
            const results = runSuite("missing", function()
                describe("broken", function()
                    error("planning failure")
                end)
            end)

            expect(results.failureCount).to.equal(1)
        end)
    end)

    describe("Config.Filter", function()
        afterEach(function()
            Config.reset()
        end)

        it("should default to no filter after a reset", function()
            Config.reset()
            expect(Config.Filter).to.equal(nil)
        end)

        it("should set and reset the filter", function()
            Config.set({ Filter = "outer runs" })
            expect(Config.Filter).to.equal("outer runs")

            Config.reset()
            expect(Config.Filter).to.equal(nil)
        end)

        it("should clear the filter when set to an empty string", function()
            Config.set({ Filter = "outer" })
            Config.set({ Filter = "" })
            expect(Config.Filter).to.equal(nil)
        end)

        it("should leave the filter alone when other options are set", function()
            Config.set({ Filter = "outer" })
            Config.set({ Indent = "  " })
            expect(Config.Filter).to.equal("outer")
        end)

        it("should reject a filter that is not a string", function()
            expect(function()
                Config.set({ Filter = 5 :: any })
            end).to.throw("Filter must be a string")
        end)
    end)

    describe("reporting filtered-out tests", function()
        const function summary(results: any): string
            const lines = TextReporter.format(results, REPORTER_OPTIONS)
            return lines[#lines]
        end

        it("should mention filtered-out tests in the summary", function()
            const results = runSuite("first", nestedSuite)

            expect(summary(results)).to.equal("1 passed, 0 failed, 2 skipped (2 filtered out).")
        end)

        it("should not mention the filter when nothing was filtered out", function()
            const results = runSuite(nil, function()
                it("runs", function() end)
                xit("waits", function() end)
            end)

            expect(summary(results)).to.equal("1 passed, 0 failed, 1 skipped.")
        end)

        it("should accept results that carry no filtered count", function()
            const results = { children = {}, errors = {}, failureCount = 0, skippedCount = 4, successCount = 2 }

            expect(summary(results)).to.equal("2 passed, 0 failed, 4 skipped.")
        end)
    end)
end
