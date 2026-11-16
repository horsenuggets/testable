--[[

TestEnum

Constants used throughout the testing framework including test status values, node types,
node modifiers, built-in skip reasons, and reporter names.

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

TestEnum.Reporter = {
    JUnit = "JUnit",
    Json = "Json",
    Lcov = "Lcov",
    Text = "Text",
}

return TestEnum
