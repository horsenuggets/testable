--[[

Gates

Grants file-boundary execution tokens in global preferred order. Ordinary files overlap
across persistent workers, while exclusive files wait for every active token to release.
All decisions are synchronous and own their input data without loading or running suites.

--]]

export type Grant = {
    JobId: number,
    Name: string,
    RequestId: number
}

export type State = {
    ActiveByName: { [string]: Grant },
    ActiveCount: number,
    ExclusiveActive: boolean,
    ExclusiveByName: { [string]: boolean },
    NextIndex: number,
    Order: { string },
    OwnerByName: { [string]: number },
    ReleasedCount: number,
    RequestedByName: { [string]: Grant },
    UsedRequestIds: { [number]: { [number]: boolean } }
}

const Gates = {}

const function check(condition: any, message: string)
    assert(condition, `Invalid worker gates. {message}`)
end

const function plainTable(value: any, label: string)
    check(type(value) == "table", `"{label}" must be a table.`)
    check(getmetatable(value) == nil, `"{label}" must not have a metatable.`)
end

const function positiveInteger(value: any): boolean
    return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

const function nonemptyString(value: any): boolean
    return type(value) == "string" and value ~= ""
end

const function copyGrant(grant: Grant): Grant
    return { JobId = grant.JobId, Name = grant.Name, RequestId = grant.RequestId }
end

const function drain(state: State): { Grant }
    const grants = {}
    while not state.ExclusiveActive and state.NextIndex <= #state.Order do
        const name = state.Order[state.NextIndex]
        const request = state.RequestedByName[name]
        if request == nil then
            break
        end
        const exclusive = state.ExclusiveByName[name]
        if exclusive and state.ActiveCount > 0 then
            break
        end
        state.ActiveByName[name] = request
        state.ActiveCount += 1
        state.ExclusiveActive = exclusive
        state.NextIndex += 1
        -- Returned tokens must not alias the records used to validate releases.
        table.insert(grants, copyGrant(request))
    end
    return grants
end

function Gates.new(order: { string }, exclusiveByName: { [string]: boolean }, ownerByName: { [string]: number }): State
    plainTable(order, "order")
    plainTable(exclusiveByName, "exclusiveByName")
    plainTable(ownerByName, "ownerByName")
    local count = 0
    for key in pairs(order) do
        check(positiveInteger(key), '"order" must be a dense array.')
        count += 1
    end
    const names = {}
    const ownedOrder = {}
    const ownedExclusive = {}
    const ownedOwners = {}
    for index = 1, count do
        const name = rawget(order, index)
        check(name ~= nil, '"order" must be a dense array.')
        check(nonemptyString(name), '"order" must contain nonempty names.')
        check(not names[name], `Duplicate name "{name}".`)
        names[name] = true
        const exclusive = rawget(exclusiveByName, name)
        const owner = rawget(ownerByName, name)
        check(type(exclusive) == "boolean", `Exclusive flag for "{name}" must be a boolean.`)
        check(positiveInteger(owner), `Owner for "{name}" must be a finite positive integer.`)
        ownedOrder[index] = name
        ownedExclusive[name] = exclusive
        ownedOwners[name] = owner
    end
    for name in pairs(exclusiveByName) do
        check(names[name] == true, '"exclusiveByName" must contain exactly the ordered names.')
    end
    for name in pairs(ownerByName) do
        check(names[name] == true, '"ownerByName" must contain exactly the ordered names.')
    end
    return {
        ActiveByName = {},
        ActiveCount = 0,
        ExclusiveActive = false,
        ExclusiveByName = ownedExclusive,
        NextIndex = 1,
        Order = ownedOrder,
        OwnerByName = ownedOwners,
        ReleasedCount = 0,
        RequestedByName = {},
        UsedRequestIds = {}
    }
end

const function validateToken(state: State, jobId: number, requestId: number, name: string)
    plainTable(state, "state")
    check(positiveInteger(jobId), '"jobId" must be a finite positive integer.')
    check(positiveInteger(requestId), '"requestId" must be a finite positive integer.')
    check(nonemptyString(name), '"name" must be a nonempty string.')
    check(state.OwnerByName[name] ~= nil, `Unknown name "{name}".`)
    check(state.OwnerByName[name] == jobId, `Wrong owner for "{name}".`)
end

function Gates.request(state: State, jobId: number, requestId: number, name: string): { Grant }
    validateToken(state, jobId, requestId, name)
    check(state.RequestedByName[name] == nil, `Duplicate request for "{name}".`)
    const used = state.UsedRequestIds[jobId]
    check(used == nil or not used[requestId], `Reused request ID "{requestId}" for owner "{jobId}".`)
    if used == nil then
        state.UsedRequestIds[jobId] = { [requestId] = true }
    else
        used[requestId] = true
    end
    state.RequestedByName[name] = { JobId = jobId, Name = name, RequestId = requestId }
    return drain(state)
end

function Gates.release(state: State, jobId: number, requestId: number, name: string): { Grant }
    validateToken(state, jobId, requestId, name)
    const active = state.ActiveByName[name]
    check(active ~= nil, `No active grant for "{name}".`)
    check(active.RequestId == requestId, `Mismatched request ID for "{name}".`)
    state.ActiveByName[name] = nil
    state.ActiveCount -= 1
    state.ExclusiveActive = false
    state.ReleasedCount += 1
    return drain(state)
end

function Gates.finished(state: State): boolean
    plainTable(state, "state")
    return state.NextIndex > #state.Order and state.ActiveCount == 0 and state.ReleasedCount == #state.Order
end

return Gates
