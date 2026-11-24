--[[

Results

Combines completed worker result trees in the coordinator's exact global spec order.
Owns every imported node, validates both plan and result membership, and finalizes once
so totals, errors, and the focus guard describe the whole run rather than each shard.

--]]

const Protocol = require("./Protocol")
const TestEnum = require("../TestEnum")
const TestFilter = require("../TestFilter")
const TestPlan = require("../TestPlan")
const TestSession = require("../TestSession")

const Results = {}

const function check(condition: any, message: string)
    assert(condition, `Invalid worker results. {message}`)
end

const function checkSequence(value: any, label: string)
    check(type(value) == "table" and getmetatable(value) == nil, `"{label}" must be a plain array.`)
    local count = 0
    for key in pairs(value) do
        check(type(key) == "number" and key >= 1 and key % 1 == 0, `"{label}" must be a dense array.`)
        count += 1
    end
    for index = 1, count do
        check(rawget(value, index) ~= nil, `"{label}" must be a dense array.`)
    end
end

-- Rebind detached synthetic plan nodes as well as nodes in the original plan. Preserve
-- parent links exactly, including nil parents on spec roots and hook placeholders.
const function rebind(node: any, plan: any, seen: { [any]: boolean })
    if seen[node] then
        return
    end
    seen[node] = true
    node.plan = plan
    for _, child in ipairs(node.children) do
        rebind(child, plan, seen)
    end
end

--[[
    Merges decoded, completed TestResults without changing any shard. Names are the exact
    ordered flat spec roots, not a preferred subset. Workers must defer the focus guard.
    The duration is the coordinator's elapsed time, not the sum of worker durations.
]]
function Results.merge(shards: { any }, names: { string }, filter: string?, forbidFocus: boolean, duration: number): any
    checkSequence(shards, "shards")
    checkSequence(names, "names")
    check(filter == nil or type(filter) == "string", '"filter" must be a string or nil.')
    check(type(forbidFocus) == "boolean", '"forbidFocus" must be a boolean.')
    check(
        type(duration) == "number" and duration >= 0 and duration < math.huge,
        '"duration" must be a finite nonnegative number.'
    )

    const expected = {}
    for _, name in ipairs(names) do
        check(type(name) == "string" and name ~= "", '"names" must contain nonempty strings.')
        check(not expected[name], `Duplicate expected spec "{name}".`)
        expected[name] = true
    end

    const plan = TestPlan.new()
    plan.filter = TestFilter.normalize(filter)
    plan.forbidFocus = forbidFocus
    const session = TestSession.new(plan)
    session.forbidFocus = forbidFocus
    const results = session.results
    results.duration = duration
    results.snapshotSummary = { Failed = 0, Matched = 0, Obsolete = {}, Removed = 0, Updated = 0, Written = 0 }
    const planned = {}
    const completed = {}
    const rebound = {}

    for _, shard in ipairs(shards) do
        check(type(shard) == "table", "Every shard must be completed TestResults.")
        check(shard.focusGuardFailed ~= true and shard.focusGuardNode == nil, "Workers must defer the focus guard.")
        -- The protocol checks completed statuses, exact totals/errors, and tree linkage
        -- while stripping runtime state and making independent copies of all metadata.
        const owned = Protocol.decodeResults(Protocol.encodeResults(shard))
        const shardPlan = {}
        const shardResults = {}
        for _, node in ipairs(owned.planNode.children) do
            const name = node.phrase
            check(node.type == TestEnum.NodeType.Describe, "Plan roots must be spec suites.")
            check(expected[name], `Unexpected planned spec "{name}".`)
            check(planned[name] == nil, `Duplicate planned spec "{name}".`)
            planned[name] = node
            shardPlan[name] = node
            rebind(node, plan, rebound)
        end
        for _, node in ipairs(owned.children) do
            const name = node.planNode.phrase
            check(expected[name], `Unexpected completed spec "{name}".`)
            check(completed[name] == nil, `Duplicate completed spec "{name}".`)
            check(node.planNode == shardPlan[name], `Completed spec "{name}" must refer to its shard's plan root.`)
            completed[name] = node
            shardResults[name] = true
        end
        for name in pairs(shardPlan) do
            check(shardResults[name], `Missing completed spec "{name}".`)
        end
        owned:visitAllNodes(function(node)
            rebind(node.planNode, plan, rebound)
        end)

        const summary = owned.snapshotSummary
        if summary ~= nil then
            for field, value in pairs(summary) do
                if type(value) == "number" then
                    results.snapshotSummary[field] += value
                end
            end
            for _, entry in ipairs(summary.Obsolete) do
                table.insert(results.snapshotSummary.Obsolete, entry)
            end
        end
    end

    for _, name in ipairs(names) do
        check(planned[name] ~= nil, `Missing planned spec "{name}".`)
        check(completed[name] ~= nil, `Missing completed spec "{name}".`)
        table.insert(plan.children, planned[name])
        table.insert(results.children, completed[name])
    end
    table.sort(results.snapshotSummary.Obsolete, function(left, right)
        return if left.Path == right.Path then left.Key < right.Key else left.Path < right.Path
    end)

    session:finalize()
    if results.focusGuardNode ~= nil then
        results.focusGuardNode.planNode.plan = plan
    end
    return results
end

return Results
