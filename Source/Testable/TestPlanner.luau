--[[

TestPlanner

Turns a series of specification functions into a test plan. Uses a TestPlanBuilder to
keep track of the state of the tree being built.

--]]
const TestFilter = require("./TestFilter")
const TestPlan = require("./TestPlan")
const ToolError = require("./ToolError")

const TestPlanner = {}

--[[
    Create a new TestPlan from a list of specification functions.

    These functions should call a combination of `describe` and `it` (and their
    variants), which will be turned into a test plan to be executed.

    Parameters:
        - modulesList - list of tables describing test modules {
            method, -- specification function described above
            path, -- array of parent entires, first element is the leaf that owns `method`
            pathStringForSorting -- a string representation of `path`, used for sorting
        }
        - filter - Only tests whose full name contains this plain substring will run
          (see TestFilter). Pass empty or nil to run all tests
        - extraEnvironment - Luau table holding additional functions and variables to be
          injected into the specification function during execution

    Throws an "EmptyFilter" ToolError when the filter selects no tests.
]]
function TestPlanner.createPlan(modulesList: { any }, filter: string?, extraEnvironment: { [string]: any }?): any
    assert(filter == nil or type(filter) == "string", "filter must be a string or nil")

    const plan = TestPlan.new(extraEnvironment)

    table.sort(modulesList, function(a, b)
        return a.pathStringForSorting < b.pathStringForSorting
    end)

    for _, module in ipairs(modulesList) do
        plan:addRoot(module.path, module.method)
    end

    const selection = TestFilter.apply(plan, filter)
    if TestFilter.isEmpty(selection, filter) then
        const noun = if selection.Total == 1 then "test" else "tests"
        error(
            ToolError.new(
                ToolError.Kind.EmptyFilter,
                `The filter "{filter}" did not match any of the {selection.Total} planned {noun}.`
            ),
            0
        )
    end

    return plan
end

return TestPlanner
