--[[

Protocol

Transfers completed worker results as versioned, acyclic data. The complete plan tree
has depth-first numeric identities, while result nodes refer to those identities. Extra
plan nodes used by synthetic failures are kept outside the original plan tree. Decoding
recreates the real TestPlan and TestResults classes, never serialized executable code.

--]]

const TestEnum = require("../TestEnum")
const TestPlan = require("../TestPlan")
const TestResults = require("../TestResults")
const TestSession = require("../TestSession")
const ToolError = require("../ToolError")
const VERSION = 1
-- Wire names map to the existing runtime API's lowercase field names and value kinds.
const PLAN_FIELDS = {
    Collected = { "collected", "boolean" },
    FilteredOut = { "filteredOut", "boolean" },
    LoadError = { "loadError", "string" },
    Modifier = { "modifier", "modifier" },
    Phrase = { "phrase", "string", true },
    Serial = { "serial", "boolean" },
    SkipReason = { "skipReason", "string" },
    Timeout = { "timeout", "positive" },
    Type = { "type", "nodeType", true }
}
const RESULT_FIELDS = {
    Duration = { "duration", "nonnegative" },
    Errors = { "errors", "strings", true },
    ExcludedByFocus = { "excludedByFocus", "boolean" },
    Messages = { "messages", "strings" },
    SkipReason = { "skipReason", "string" },
    Status = { "status", "status" }
}
const ROOT_FIELDS = {
    FailureCount = { "failureCount", "count", true },
    FilteredCount = { "filteredCount", "count", true },
    FocusExcludedCount = { "focusExcludedCount", "count" },
    FocusGuardFailed = { "focusGuardFailed", "boolean" },
    SkippedCount = { "skippedCount", "count", true },
    SuccessCount = { "successCount", "count", true }
}
const SPEC_FIELDS = {
    Path = { "path", "strings" },
    PathStringForSorting = { "pathStringForSorting", "string" },
    SnapshotPath = { "snapshotPath", "string" }
}

export type Manifest = {
    Assigned: { string },
    Completed: { string },
    JobId: number,
    RunId: string,
    Version: number
}

const Protocol = {}

const function check(condition: any, message: string)
    assert(condition, `Invalid worker protocol. {message}`)
end

-- Reject metatables before reading fields, including hostile __index/__iter handlers.
-- Shared, noncyclic tables are copied independently, so no alias crosses the boundary.
const function copyPlain(value: any, active: any?): any
    const kind = type(value)
    if kind == "table" then
        check(getmetatable(value) == nil, "Data must not contain metatables.")
        const stack = active or {}
        check(not stack[value], "Data must not contain cyclic tables.")
        stack[value] = true
        const copy = {}
        for key, item in pairs(value) do
            check(type(key) == "string" or type(key) == "number", "Data keys must be strings or numbers.")
            if type(key) == "number" then
                check(key == key and math.abs(key) < math.huge, "Data keys must be finite.")
            end
            copy[key] = copyPlain(item, stack)
        end
        stack[value] = nil
        return copy
    end
    check(
        kind == "nil" or kind == "string" or kind == "boolean" or kind == "number",
        "Data must contain only plain values."
    )
    if kind == "number" then
        check(value == value and math.abs(value) < math.huge, "Data numbers must be finite.")
    end
    return value
end

const function array(value: any, label: string)
    check(type(value) == "table", `"{label}" must be an array.`)
    local count = 0
    for key in pairs(value) do
        check(type(key) == "number" and key >= 1 and key % 1 == 0, `"{label}" must be a dense array.`)
        count += 1
    end
    -- A sparse table's length can equal its key count despite holes before that boundary.
    for index = 1, count do
        check(value[index] ~= nil, `"{label}" must be a dense array.`)
    end
end

const function shape(value: any, fields: any, extra: any?)
    check(type(value) == "table", "Expected an object.")
    for key in pairs(value) do
        check(fields[key] ~= nil or (extra ~= nil and extra[key] == true), `Unknown field "{key}".`)
    end
end

const function validateValue(value: any, kind: string, label: string)
    if kind == "strings" then
        array(value, label)
        for _, item in ipairs(value) do
            check(type(item) == "string", `"{label}" must contain strings.`)
        end
    elseif kind == "status" or kind == "modifier" or kind == "nodeType" then
        const values = if kind == "status"
            then TestEnum.TestStatus
            elseif kind == "modifier" then TestEnum.NodeModifier
            else TestEnum.NodeType
        check(type(value) == "string" and values[value] == value, `"{label}" has an unknown {kind}.`)
    elseif kind == "count" or kind == "nonnegative" or kind == "positive" then
        check(
            type(value) == "number" and value >= 0 and value < math.huge,
            `"{label}" must be a finite nonnegative number.`
        )
        if kind == "count" then
            check(value % 1 == 0, `"{label}" must be an integer.`)
        elseif kind == "positive" then
            check(value > 0, `"{label}" must be positive.`)
        end
    else
        check(type(value) == kind, `"{label}" must be a {kind}.`)
    end
end

const function fieldsToWire(source: any, fields: any): any
    const wire = {}
    for name, field in pairs(fields) do
        wire[name] = copyPlain(source[field[1]])
    end
    return wire
end

const function fieldsFromWire(wire: any, target: any, fields: any)
    for name, field in pairs(fields) do
        const value = wire[name]
        check(value ~= nil or not field[3], `Missing field "{name}".`)
        if value ~= nil then
            validateValue(value, field[2], name)
        end
        target[field[1]] = value
    end
end

const function validateSummary(summary: any)
    shape(
        summary,
        {},
        { Failed = true, Matched = true, Obsolete = true, Removed = true, Updated = true, Written = true }
    )
    for _, name in { "Failed", "Matched", "Removed", "Updated", "Written" } do
        validateValue(summary[name], "count", name)
    end
    array(summary.Obsolete, "Obsolete")
    for _, entry in ipairs(summary.Obsolete) do
        shape(entry, {}, { Key = true, Path = true })
        validateValue(entry.Key, "string", "Key")
        validateValue(entry.Path, "string", "Path")
    end
end

--[[
    Encodes completed TestResults, dropping runtime callbacks, environments, snapshot
    managers, and cyclic parent/plan links. Invalid or unfinished results throw.
]]
function Protocol.encodeResults(results: any): any
    check(type(results) == "table", "Results must be a non-nil table.")
    check(type(results.planNode) == "table", "Results must have a plan.")
    const ids = {}
    local nextId = 0
    const function encodePlan(node: any): any
        check(type(node) == "table", "Plan nodes must be tables.")
        check(ids[node] == nil, "The plan must be a tree without repeated or cyclic nodes.")
        nextId += 1
        ids[node] = nextId
        const wire = fieldsToWire(node, PLAN_FIELDS)
        wire.Id = nextId
        wire.Children = {}
        if node.specModule ~= nil then
            check(type(node.specModule) == "table", "Spec metadata must be a table.")
            wire.SpecModule = fieldsToWire(node.specModule, SPEC_FIELDS)
        end
        const children = node.children or {}
        array(children, "plan children")
        for _, child in ipairs(children) do
            table.insert(wire.Children, encodePlan(child))
        end
        return wire
    end
    const plan = results.planNode
    const dto = {
        Detached = {},
        Plan = { Children = {}, Filter = copyPlain(plan.filter), ForbidFocus = copyPlain(plan.forbidFocus) },
        Version = VERSION
    } :: any
    array(plan.children, "plan children")
    for _, child in ipairs(plan.children) do
        table.insert(dto.Plan.Children, encodePlan(child))
    end
    const seen = {}
    const function encodeNode(node: any, root: boolean): any
        check(type(node) == "table" and not seen[node], "Results must be a tree without repeated or cyclic nodes.")
        seen[node] = true
        const wire = fieldsToWire(node, RESULT_FIELDS)
        wire.Children = {}
        if root then
            for key, value in pairs(fieldsToWire(node, ROOT_FIELDS)) do
                wire[key] = value
            end
            wire.SnapshotSummary = copyPlain(node.snapshotSummary)
        else
            check(type(node.planNode) == "table", "Result nodes must refer to a plan node.")
            if ids[node.planNode] == nil then
                table.insert(dto.Detached, encodePlan(node.planNode))
            end
            wire.PlanId = ids[node.planNode]
        end
        array(node.children, "result children")
        for _, child in ipairs(node.children) do
            table.insert(wire.Children, encodeNode(child, false))
        end
        return wire
    end
    dto.Results = encodeNode(results, true)
    if results.focusGuardNode ~= nil then
        check(seen[results.focusGuardNode], "Focus guard must refer to a result node.")
        dto.FocusGuardId = ids[results.focusGuardNode.planNode]
    end
    -- Use the same boundary validation in both directions.
    Protocol.decodeResults(dto)
    return dto
end

--[[
    Validates a DTO and rebuilds the original classes and their linkage. Every nested
    input value is copied. No serialized functions or environments are accepted.
]]
function Protocol.decodeResults(value: any): any
    check(type(value) == "table", "Results DTO must be a non-nil table.")
    const dto = copyPlain(value)
    shape(dto, {}, { Detached = true, FocusGuardId = true, Plan = true, Results = true, Version = true })
    check(dto.Version == VERSION, "Unsupported results version.")
    shape(dto.Plan, {}, { Children = true, Filter = true, ForbidFocus = true })
    const plan = TestPlan.new()
    for _, field in { { "Filter", "filter", "string" }, { "ForbidFocus", "forbidFocus", "boolean" } } do
        if dto.Plan[field[1]] ~= nil then
            validateValue(dto.Plan[field[1]], field[3], field[1])
        end
        plan[field[2]] = dto.Plan[field[1]]
    end
    const nodes = {}
    local nextId = 0
    const function decodePlan(wire: any, parent: any)
        shape(wire, PLAN_FIELDS, { Children = true, Id = true, SpecModule = true })
        nextId += 1
        check(wire.Id == nextId, "Plan ids must be unique depth-first positive integers.")
        const metadata = {} :: any
        fieldsFromWire(wire, metadata, PLAN_FIELDS)
        if parent ~= plan and metadata.type == TestEnum.NodeType.It then
            for _, sibling in ipairs(parent.children) do
                check(sibling.phrase ~= metadata.phrase, "Duplicate test phrase in the plan.")
            end
        end
        const node = parent:addChild(metadata.phrase, metadata.type, metadata.modifier)
        fieldsFromWire(wire, node, PLAN_FIELDS)
        nodes[wire.Id] = node
        if wire.SpecModule ~= nil then
            shape(wire.SpecModule, SPEC_FIELDS)
            node.specModule = {}
            fieldsFromWire(wire.SpecModule, node.specModule, SPEC_FIELDS)
        end
        array(wire.Children, "plan Children")
        for _, child in ipairs(wire.Children) do
            decodePlan(child, node)
        end
    end
    array(dto.Plan.Children, "plan Children")
    for _, wire in ipairs(dto.Plan.Children) do
        decodePlan(wire, plan)
    end
    const originalNodeCount = nextId
    array(dto.Detached, "Detached")
    for _, wire in ipairs(dto.Detached) do
        decodePlan(wire, plan)
        -- addChild supplies real methods and the plan pointer, but synthetic nodes must
        -- not change the original plan's children or its traversal results.
        table.remove(plan.children)
    end
    const byPlanId = {}
    const function decodeNode(wire: any, root: boolean, parentPlan: any?): any
        const extra = { Children = true, PlanId = not root, SnapshotSummary = root }
        if root then
            for key in pairs(ROOT_FIELDS) do
                extra[key] = true
            end
        end
        shape(wire, RESULT_FIELDS, extra)
        local node
        if root then
            node = TestResults.new(plan)
            fieldsFromWire(wire, node, ROOT_FIELDS)
            if wire.SnapshotSummary ~= nil then
                validateSummary(wire.SnapshotSummary)
                node.snapshotSummary = wire.SnapshotSummary
            end
        else
            validateValue(wire.PlanId, "count", "PlanId")
            check(nodes[wire.PlanId] ~= nil, "Result has an invalid plan reference.")
            check(byPlanId[wire.PlanId] == nil, "A plan node has duplicate results.")
            if wire.PlanId <= originalNodeCount then
                check(nodes[wire.PlanId].parent == parentPlan, "Result has the wrong parent plan reference.")
            end
            node = TestResults.createNode(nodes[wire.PlanId])
            byPlanId[wire.PlanId] = node
            check(wire.Status ~= nil, "Completed result nodes must have a status.")
        end
        fieldsFromWire(wire, node, RESULT_FIELDS)
        array(wire.Children, "result Children")
        for _, child in ipairs(wire.Children) do
            table.insert(node.children, decodeNode(child, false, if root then nil else node.planNode))
        end
        return node
    end
    const results = decodeNode(dto.Results, true)
    for _, wire in ipairs(dto.Detached) do
        check(byPlanId[wire.Id] ~= nil, "Detached plan nodes must have results.")
    end
    if dto.FocusGuardId ~= nil then
        validateValue(dto.FocusGuardId, "count", "FocusGuardId")
        const guard = byPlanId[dto.FocusGuardId]
        check(guard ~= nil and guard.status == TestEnum.TestStatus.Failure, "Invalid focus guard reference.")
        check(
            guard.planNode.type == TestEnum.NodeType.It
                and guard.planNode.phrase == TestSession.FocusGuardPhrase
                and table.find(results.children, guard) ~= nil
                and results.focusGuardFailed == true,
            "Invalid focus guard failure."
        )
        results.focusGuardNode = guard
    end
    check(results.focusGuardFailed ~= true or results.focusGuardNode ~= nil, "Missing focus guard reference.")
    const session = TestSession.new(plan)
    session.results = results
    const totals = fieldsToWire(results, ROOT_FIELDS)
    const errors = results.errors
    session:calculateTotals()
    for name, field in pairs(ROOT_FIELDS) do
        if field[2] == "count" and totals[name] ~= nil then
            check(results[field[1]] == totals[name], `"{name}" does not match the result tree.`)
        end
    end
    -- Preserve the distinction between an absent optional count and zero.
    fieldsFromWire(totals, results, ROOT_FIELDS)
    session:gatherErrors()
    check(#results.errors == #errors, "Root errors do not match the result tree.")
    for index, message in ipairs(errors) do
        check(results.errors[index] == message, "Root errors do not match the result tree.")
    end
    return results
end

const function identities(value: any, label: string): { string }
    const copy = copyPlain(value)
    validateValue(copy, "strings", label)
    const seen = {}
    for _, identity in ipairs(copy) do
        check(identity ~= "", `"{label}" contains an empty identity.`)
        check(not seen[identity], `"{label}" contains duplicate identity "{identity}".`)
        seen[identity] = true
    end
    return copy
end

--[[
    Validates exact ordered assignment and completion against the coordinator's job.
    Missing results (including nil), duplicate files, and wrong identities throw.
]]
function Protocol.validateManifest(value: any, runId: string, jobId: number, expectedFiles: { string }): Manifest
    check(type(runId) == "string" and runId ~= "", "RunId must be a nonempty string.")
    validateValue(jobId, "count", "JobId")
    check(jobId > 0, "JobId must be positive.")
    const expected = identities(expectedFiles, "expected files")
    const manifest = copyPlain(value)
    shape(manifest, {}, { Assigned = true, Completed = true, JobId = true, RunId = true, Version = true })
    check(manifest.Version == VERSION, "Unsupported manifest version.")
    check(manifest.RunId == runId, "Manifest has the wrong run identity.")
    check(manifest.JobId == jobId, "Manifest has the wrong job identity.")
    for _, name in { "Assigned", "Completed" } do
        const files = identities(manifest[name], name)
        check(#files == #expected, `"{name}" has missing or unexpected files.`)
        for index, file in ipairs(expected) do
            check(files[index] == file, `"{name}" has the wrong ordered file identity.`)
        end
    end
    return manifest
end

--[[
    Constructs a validated completion manifest, taking independent copies of both lists.
]]
function Protocol.makeManifest(runId: string, jobId: number, assigned: { string }, completed: { string }): Manifest
    check(type(runId) == "string", "RunId must be a string.")
    check(type(jobId) == "number", "JobId must be a number.")
    check(type(assigned) == "table", "Assigned must be an array.")
    check(type(completed) == "table", "Completed must be an array.")
    return Protocol.validateManifest({
        Assigned = assigned,
        Completed = completed,
        JobId = jobId,
        RunId = runId,
        Version = VERSION
    }, runId, jobId, assigned)
end

-- Tool errors retain their kind and local identity without transferring a metatable.
function Protocol.decodeProblem(value: any, runId: string, jobId: number): ToolError.ToolError
    check(type(runId) == "string" and runId ~= "", "RunId must be a nonempty string.")
    validateValue(jobId, "count", "JobId")
    check(jobId > 0, "JobId must be positive.")
    const dto = copyPlain(value)
    shape(dto, {}, { JobId = true, Kind = true, Message = true, RunId = true, Version = true })
    check(dto.Version == VERSION, "Unsupported problem version.")
    check(dto.RunId == runId and dto.JobId == jobId, "The problem belongs to another run or job.")
    check(type(dto.Kind) == "string" and ToolError.Kind[dto.Kind] ~= nil, "Unknown tool error kind.")
    validateValue(dto.Message, "string", "Message")
    return ToolError.new(dto.Kind, dto.Message)
end

function Protocol.encodeProblem(problem: any, runId: string, jobId: number): any
    check(ToolError.is(problem), "Expected a local ToolError.")
    const dto = {
        JobId = jobId,
        Kind = problem.Kind,
        Message = problem.Message,
        RunId = runId,
        Version = VERSION
    }
    Protocol.decodeProblem(dto, runId, jobId)
    return dto
end

return Protocol
