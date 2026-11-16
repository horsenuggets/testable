--[[

TestEnum

Constants used throughout the testing framework including test status values, node types,
node modifiers, and built-in skip reasons.

--]]

const TestEnum = {}

TestEnum.TestStatus = {
    Success = "Success",
    Failure = "Failure",
    Skipped = "Skipped",
}

TestEnum.NodeType = {
    Describe = "Describe",
    It = "It",
    BeforeAll = "BeforeAll",
    AfterAll = "AfterAll",
    BeforeEach = "BeforeEach",
    AfterEach = "AfterEach",
}

TestEnum.NodeModifier = {
    None = "None",
    Skip = "Skip",
    Focus = "Focus",
}

-- Reasons the framework attaches to skipped tests on its own. Tests skipped with a skip
-- variant carry whatever reason the caller passed instead.
TestEnum.SkipReason = {
    Fixme = "fixme",
    Focus = "excluded by focus",
    Todo = "todo",
}

return TestEnum
