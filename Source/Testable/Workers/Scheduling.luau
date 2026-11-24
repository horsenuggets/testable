--[[

Scheduling

Partitions globally ordered files into deterministic worker jobs without loading suites.
Overlapping ownership groups stay together, including overlaps through unselected files.

--]]

export type Job = {
    Files: { string },
    Id: number,
}

const Scheduling = {}

const function check(condition: any, message: string)
    assert(condition, `Invalid worker scheduling. {message}`)
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

const function array(value: any, label: string): number
    plainTable(value, label)
    local count = 0
    for key in pairs(value) do
        check(positiveInteger(key), `"{label}" must be a dense array.`)
        count += 1
    end
    -- Counting keys alone cannot detect holes, even when that count equals #value.
    for index = 1, count do
        check(rawget(value, index) ~= nil, `"{label}" must be a dense array.`)
    end
    return count
end

const function paths(value: any, label: string, seen: { [string]: boolean }?): number
    const count = array(value, label)
    for index = 1, count do
        const path = value[index]
        check(nonemptyString(path), `"{label}" must contain nonempty paths.`)
        if seen ~= nil then
            check(not seen[path], `Duplicate path "{path}".`)
            seen[path] = true
        end
    end
    return count
end

-- Names validate global identities only. The caller already applied SuiteOrder.
function Scheduling.partition(
    files: { string },
    names: { [string]: string },
    workers: number,
    groups: { { string } }
): { Job }
    const fileCount = paths(files, "files", {})
    plainTable(names, "names")
    check(positiveInteger(workers), '"workers" must be a finite positive integer.')
    const groupCount = array(groups, "groups")
    const usedNames = {}
    for path, name in pairs(names) do
        check(nonemptyString(path), '"names" must use nonempty paths as keys.')
        check(nonemptyString(name), '"names" must contain nonempty names.')
        check(not usedNames[name], `Duplicate name "{name}".`)
        usedNames[name] = true
    end
    for _, path in ipairs(files) do
        check(rawget(names, path) ~= nil, `Missing name for "{path}".`)
    end
    for index = 1, groupCount do
        check(paths(groups[index], `groups[{index}]`) > 0, "Ownership groups must not be empty.")
    end

    const parents: { [string]: string } = {}
    const function root(path: string): string
        if parents[path] == nil then
            parents[path] = path
        end
        local current = path
        while parents[current] ~= current do
            current = parents[current]
        end
        while parents[path] ~= path do
            const nextPath = parents[path]
            parents[path] = current
            path = nextPath
        end
        return current
    end

    -- Union every group before selecting files. Missing files can bridge two groups.
    for _, group in ipairs(groups) do
        for _, path in ipairs(group) do
            parents[root(path)] = root(group[1])
        end
    end

    const components: { { string } } = {}
    const byRoot: { [string]: { string } } = {}
    for _, path in ipairs(files) do
        const owner = root(path)
        local component = byRoot[owner]
        if component == nil then
            component = {}
            byRoot[owner] = component
            table.insert(components, component)
        end
        table.insert(component, path)
    end

    const buckets: { Job } = {}
    for id = 1, math.min(workers, fileCount) do
        table.insert(buckets, { Files = {}, Id = id })
    end
    const loads: { number } = table.create(#buckets, 0)
    const bucketByPath: { [string]: number } = {}
    for _, component in ipairs(components) do
        local bucket = 1
        for id = 2, #buckets do
            if loads[id] < loads[bucket] then
                bucket = id
            end
        end
        loads[bucket] += #component
        for _, path in ipairs(component) do
            bucketByPath[path] = bucket
        end
    end
    -- Components can interleave globally. Append files in input order, not group order.
    for _, path in ipairs(files) do
        table.insert(buckets[bucketByPath[path]].Files, path)
    end
    const jobs: { Job } = {}
    for _, bucket in ipairs(buckets) do
        if #bucket.Files > 0 then
            bucket.Id = #jobs + 1
            table.insert(jobs, bucket)
        end
    end
    return jobs
end

return Scheduling
