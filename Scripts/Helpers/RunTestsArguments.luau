--[[

RunTestsArguments

Parses the command-line arguments of the RunTests script into a plain table, without
reading the process or exiting, so the parsing rules can be unit tested.

--]]

export type WorkerOptions = {
    WorkerSetup: string?,
    Workers: number?,
}

export type Arguments = WorkerOptions & {
    Changed: string?,
    Files: { string },
    Watch: boolean,
}

-- Values belonging to another parser are opaque, even when they look like worker flags.
const VALUE_FLAGS = {
    ["--changed"] = true,
    ["--filter"] = true,
    ["--output"] = true,
    ["--reporter"] = true,
    ["--slowest"] = true,
}

const RunTestsArguments = {}

RunTestsArguments.Usage = "[--changed <ref>] [--watch] [--workers <count>] [--worker-setup <path>]"

--[[
    Extracts worker flags before other parsers remove their flags. This ensures a flag
    such as "--filter" cannot disappear and make its value look like a setup path.
    Unknown arguments keep their original order for the remaining parsers.

    @return options - Worker configuration, or nil if a worker flag is invalid
    @return remaining - Arguments that are not worker flags
    @return message - The problem when a worker flag is invalid
]]
function RunTestsArguments.extractWorkers(arguments: { string }): (WorkerOptions?, { string }, string?)
    assert(type(arguments) == "table", "arguments must be an array of strings")

    const options: WorkerOptions = {}
    const remaining = {}
    local index = 1
    while index <= #arguments do
        const argument = arguments[index]
        if argument == "--workers" or argument == "--worker-setup" then
            const value = arguments[index + 1]
            if argument == "--workers" then
                if options.Workers ~= nil then
                    return nil, {}, 'The "--workers" flag can only be given once.'
                end
                const count = if value ~= nil then tonumber(value) else nil
                if count == nil or count <= 0 or count >= math.huge or count % 1 ~= 0 then
                    return nil, {}, 'The "--workers" flag needs a finite positive integer.'
                end
                options.Workers = count
            else
                if options.WorkerSetup ~= nil then
                    return nil, {}, 'The "--worker-setup" flag can only be given once.'
                end
                if value == nil or string.find(value, "%S") == nil or string.sub(value, 1, 1) == "-" then
                    return nil, {}, 'The "--worker-setup" flag needs a nonblank module path.'
                end
                options.WorkerSetup = value
            end
            index += 2
        else
            table.insert(remaining, argument)
            index += 1
            if VALUE_FLAGS[argument] and arguments[index] ~= nil then
                table.insert(remaining, arguments[index])
                index += 1
            end
        end
    end
    return options, remaining, nil
end

--[[
    Parses the arguments given to the RunTests script.

    @param arguments - The raw command-line arguments
    @return parsed - The parsed arguments, or nil if they are invalid
    @return message - A sentence describing what is wrong, when the arguments are invalid
]]
function RunTestsArguments.parse(arguments: { string }): (Arguments?, string?)
    assert(type(arguments) == "table", "arguments must be an array of strings")

    const workers, remaining, problem = RunTestsArguments.extractWorkers(arguments)
    if workers == nil then
        return nil, problem
    end
    const parsed: Arguments = {
        Changed = nil,
        Files = {},
        Watch = false,
        WorkerSetup = workers.WorkerSetup,
        Workers = workers.Workers,
    }

    local index = 1
    while index <= #remaining do
        const argument = remaining[index]

        if argument == "--watch" then
            parsed.Watch = true
        elseif argument == "--changed" then
            const ref = remaining[index + 1]
            if ref == nil or string.sub(ref, 1, 1) == "-" then
                return nil, 'The "--changed" flag needs a git ref, such as "origin/main".'
            end
            parsed.Changed = ref
            index += 1
        elseif string.sub(argument, 1, 1) == "-" then
            return nil, `The argument "{argument}" is not recognized.`
        else
            table.insert(parsed.Files, argument)
        end

        index += 1
    end

    if parsed.Watch and parsed.Changed ~= nil then
        return nil, 'The "--watch" and "--changed" flags can\'t be combined.'
    end
    if parsed.Changed ~= nil and #parsed.Files > 0 then
        return nil, 'The "--changed" flag can\'t be combined with spec files.'
    end

    return parsed, nil
end

--[[
    Removes a subsequence from a list of arguments. The script uses it to find the flags
    that another parser consumed, so a watch pass can hand exactly those on to its child
    process.

    @param arguments - The full list of arguments
    @param removed - The arguments to take out, in the order they appear in the list
    @return The arguments that are left, in their original order
]]
function RunTestsArguments.without(arguments: { string }, removed: { string }): { string }
    assert(type(arguments) == "table", "arguments must be an array of strings")
    assert(type(removed) == "table", "removed must be an array of strings")

    const kept = {}
    local removedIndex = 1
    for _, argument in arguments do
        if argument == removed[removedIndex] then
            removedIndex += 1
        else
            table.insert(kept, argument)
        end
    end

    return kept
end

return RunTestsArguments
