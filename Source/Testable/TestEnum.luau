--[[

TestEnum

Constants used throughout the testing framework including test status values, node types,
node modifiers, and reporter names.

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

TestEnum.Reporter = {
    JUnit = "JUnit",
    Json = "Json",
    Lcov = "Lcov",
    Text = "Text",
}

return TestEnum
