--[[

TestFilter

Narrows a test plan to the tests whose full name contains a plain substring. A test's
full name is its module name, describe phrases, and own phrase joined by single spaces.
The filter marks the "it" nodes it excludes instead of changing their modifiers, so focus
and skip modifiers keep their own meaning and apply to whatever the filter leaves.

--]]

const TestEnum = require("./TestEnum")

export type Selection = {
    Matched: number,
    PlanningErrors: number,
    Total: number,
}

const TestFilter = {}

--[[
    Converts a configured filter into the form the rest of the module uses, where an
    empty string means no filter at all.

    @param filter - The configured filter, if any
    @return The filter, or nil when there is nothing to filter by
]]
function TestFilter.normalize(filter: string?): string?
    assert(filter == nil or type(filter) == "string", "filter must be a string or nil")

    return if filter == "" then nil else filter
end

--[[
    Tells whether a test's full name is selected by the filter. The filter is a plain
    substring, so Luau pattern characters in it have no special meaning.

    @param fullName - The test's full name
    @param filter - The filter, or nil to select every test
    @return True if the test is selected
]]
function TestFilter.matches(fullName: string, filter: string?): boolean
    assert(type(fullName) == "string", "fullName must be a string")

    const normalized = TestFilter.normalize(filter)
    return normalized == nil or string.find(fullName, normalized, 1, true) ~= nil
end

--[[
    Marks every "it" node in the plan as filtered out or not, and counts what the filter
    selected. Applying a nil filter clears any earlier marks.

    @param plan - The TestPlan to mark
    @param filter - The filter, or nil to select every test
    @return How many tests exist, how many the filter selected, and how many describe
        nodes failed to plan (their tests are unknown, so they can't be matched)
]]
function TestFilter.apply(plan: any, filter: string?): Selection
    assert(type(plan) == "table", "plan must be a table")

    const normalized = TestFilter.normalize(filter)
    const selection: Selection = { Matched = 0, PlanningErrors = 0, Total = 0 }

    plan.filter = normalized
    plan:visitAllNodes(function(node)
        if node.type == TestEnum.NodeType.It then
            const matched = TestFilter.matches(node:getFullName(), normalized)
            node.filteredOut = not matched
            selection.Total += 1
            if matched then
                selection.Matched += 1
            end
        elseif node.type == TestEnum.NodeType.Describe and node.loadError ~= nil then
            selection.PlanningErrors += 1
        end
    end)

    return selection
end

--[[
    Tells whether a filter that was applied to a plan selected nothing to run. A plan
    with planning errors is never considered empty, since the failed describe nodes hide
    tests the filter might have matched and the run should report those errors instead.

    @param selection - The result of TestFilter.apply
    @param filter - The filter that was applied
    @return True if the filter is set and selected no tests
]]
function TestFilter.isEmpty(selection: Selection, filter: string?): boolean
    assert(type(selection) == "table", "selection must be a table")

    return TestFilter.normalize(filter) ~= nil and selection.Matched == 0 and selection.PlanningErrors == 0
end

const function containsSelectedTest(node: any): boolean
    if node.type == TestEnum.NodeType.It then
        return not node.filteredOut
    end
    for _, child in ipairs(node.children) do
        if containsSelectedTest(child) then
            return true
        end
    end
    return false
end

--[[
    Tells whether the plan's filter leaves a node out of the run entirely, meaning the
    node is a test the filter excluded or a describe block (or the plan itself) with no
    selected test anywhere under it. Nothing is left out when the plan has no filter.

    @param plan - The TestPlan the node belongs to, after any filter has been applied
    @param node - The plan node to check
    @return True if the filter leaves nothing to run in the node
]]
function TestFilter.excludes(plan: any, node: any): boolean
    assert(type(plan) == "table", "plan must be a table")
    assert(type(node) == "table", "node must be a table")

    return plan.filter ~= nil and not containsSelectedTest(node)
end

--[[
    Tells whether focus mode applies to a plan. The filter narrows first, so when one is
    set, a focus node only counts if it is or contains a test the filter selected.
    Otherwise a focus on filtered-out tests would exclude everything the filter chose.

    @param plan - The TestPlan to inspect, after any filter has been applied
    @return True if tests outside focus nodes should be skipped
]]
function TestFilter.hasFocus(plan: any): boolean
    assert(type(plan) == "table", "plan must be a table")

    const focusNodes = plan:findNodes(function(node)
        return node.modifier == TestEnum.NodeModifier.Focus and not TestFilter.excludes(plan, node)
    end)

    return #focusNodes > 0
end

return TestFilter
