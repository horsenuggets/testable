--[[

RunTestsArguments

Parses the command-line arguments of the RunTests script into a plain table, without
reading the process or exiting, so the parsing rules can be unit tested.

--]]

export type Arguments = {
    Changed: string?,
    Files: { string },
    Watch: boolean,
}

const RunTestsArguments = {}

RunTestsArguments.Usage = "[--changed <ref>] [--watch]"

--[[
    Parses the arguments given to the RunTests script.

    @param arguments - The raw command-line arguments
    @return parsed - The parsed arguments, or nil if they are invalid
    @return message - A sentence describing what is wrong, when the arguments are invalid
]]
function RunTestsArguments.parse(arguments: { string }): (Arguments?, string?)
    assert(type(arguments) == "table", "arguments must be an array of strings")

    const parsed: Arguments = {
        Changed = nil,
        Files = {},
        Watch = false,
    }

    local index = 1
    while index <= #arguments do
        const argument = arguments[index]

        if argument == "--watch" then
            parsed.Watch = true
        elseif argument == "--changed" then
            const ref = arguments[index + 1]
            if ref == nil or string.sub(ref, 1, 1) == "-" then
                return nil, 'The "--changed" flag needs a git ref, such as "origin/main".'
            end
            parsed.Changed = ref
            index += 1
        elseif string.sub(argument, 1, 1) == "-" then
            return nil, `The flag "{argument}" is not recognized.`
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
