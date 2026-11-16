--[[

ResultFixture

Builds TestResults-shaped trees by hand, so reporter tests can render exact, known results
without running a test plan.

--]]

const TestEnum = require("../../Source/Testable/TestEnum")

-- Extra fields for a fixture node. LoadError marks a describe block whose body failed
-- during planning.
export type Extra = {
    Duration: number?,
    Errors: { string }?,
    LoadError: string?,
    SkipReason: string?,
}

const ResultFixture = {}

const function node(nodeType: string, phrase: string, status: string?, children: { any }, extra: Extra?): any
    const fields: Extra = extra or {}
    return {
        children = children,
        duration = fields.Duration,
        errors = fields.Errors or {},
        planNode = { loadError = fields.LoadError, phrase = phrase, type = nodeType },
        skipReason = fields.SkipReason,
        status = status,
    }
end

--[[
    Builds a result node for a test.
]]
function ResultFixture.it(phrase: string, status: string?, extra: Extra?): any
    assert(type(phrase) == "string")
    return node(TestEnum.NodeType.It, phrase, status, {}, extra)
end

--[[
    Builds a result node for a describe block or spec root.
]]
function ResultFixture.describe(phrase: string, status: string?, children: { any }, extra: Extra?): any
    assert(type(phrase) == "string")
    assert(type(children) == "table")
    return node(TestEnum.NodeType.Describe, phrase, status, children, extra)
end

--[[
    Builds the root of a results tree from its spec roots.
]]
function ResultFixture.results(children: { any }, duration: number?): any
    assert(type(children) == "table")
    return { children = children, duration = duration, errors = {} }
end

--[[
    Builds a tree with a passed, a failed, and a skipped test, plus a describe block that
    failed during planning. Every call returns a fresh, equal tree.
]]
function ResultFixture.mixed(): any
    const failure = TestEnum.TestStatus.Failure
    const skipped = TestEnum.TestStatus.Skipped
    const success = TestEnum.TestStatus.Success
    return ResultFixture.results({
        ResultFixture.describe("MathTest", failure, {
            ResultFixture.it("adds", success, { Duration = 0.25 }),
            ResultFixture.describe("division", failure, {
                ResultFixture.it("divides", failure, {
                    Duration = 0.5,
                    Errors = { "expected 2, got 3\nstack line", "second error" },
                }),
                ResultFixture.it("rounds", skipped, { SkipReason = "not implemented" }),
            }, { Duration = 0.75 }),
        }, { Duration = 1 }),
        ResultFixture.describe("BrokenTest", failure, {}, {
            Duration = 0.125,
            Errors = { "Error during planning: boom" },
            LoadError = "boom",
        }),
        ResultFixture.describe("SkippedTest", skipped, {
            ResultFixture.it("waits", skipped),
        }, { Duration = 0 }),
    }, 2)
end

return ResultFixture
