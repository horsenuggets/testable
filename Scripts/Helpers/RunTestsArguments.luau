--[[

RunTestsArguments

Parses the command line arguments of the RunTests script. Parsing is kept apart from the
script so it can be tested without running the whole suite.

--]]

export type Arguments = {
    Filter: string?,
}

const FILTER_FLAG = "--filter"
const FILTER_PREFIX = `{FILTER_FLAG}=`
const USAGE = `[Usage] ./Scripts/RunTests.exec.luau [{FILTER_FLAG} "<text>"]`

const RunTestsArguments = {}

--[[
    Parses the arguments given to the RunTests script. The filter can be passed as
    "--filter <text>" or "--filter=<text>".

    @param args - The raw command line arguments
    @return arguments - The parsed arguments, or nil if they are invalid
    @return problem - A sentence describing why the arguments are invalid, if they are
]]
function RunTestsArguments.parse(args: { string }): (Arguments?, string?)
    assert(type(args) == "table", "args must be a table")

    const arguments: Arguments = {}
    local index = 1

    while index <= #args do
        const argument = args[index]
        assert(type(argument) == "string", "args must only contain strings")

        local filter: string?
        if argument == FILTER_FLAG then
            index += 1
            filter = args[index]
        elseif argument:sub(1, #FILTER_PREFIX) == FILTER_PREFIX then
            filter = argument:sub(#FILTER_PREFIX + 1)
        else
            return nil, `The argument "{argument}" is not recognized.`
        end

        if filter == nil or filter == "" then
            return nil, `The "{FILTER_FLAG}" option needs the text to filter test names by.`
        elseif arguments.Filter ~= nil then
            return nil, `The "{FILTER_FLAG}" option can only be given once.`
        end

        arguments.Filter = filter
        index += 1
    end

    return arguments, nil
end

RunTestsArguments.Usage = USAGE

return RunTestsArguments
