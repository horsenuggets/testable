--[[

FilterArguments

Parses the command-line flag that filters tests by name into Testable configuration
options. Parsing is pure, so it never reads the process arguments itself, and arguments
it doesn't know are handed back for the caller to deal with.

--]]

export type Options = {
    Filter: string?,
}

const FILTER_FLAG = "--filter"
const FILTER_PREFIX = `{FILTER_FLAG}=`

const FilterArguments = {}

FilterArguments.Usage = `[{FILTER_FLAG} "<text>"]`

--[[
    Parses the filter flag out of a list of command-line arguments. Mistakes raise a
    message meant for the person running the script, without a source position, so the
    caller can print it as is.

    > --filter <text> - Only runs the tests whose full name contains the text. It can
      also be written as --filter=<text>.

    @param arguments - The command-line arguments
    @return options - The configuration options the flag describes
    @return remaining - The arguments that aren't the filter flag, in their original order
]]
function FilterArguments.parse(arguments: { string }): (Options, { string })
    assert(type(arguments) == "table", "arguments must be a table")

    const options: Options = {}
    const remaining = {}
    local index = 1

    while index <= #arguments do
        const argument = arguments[index]
        assert(type(argument) == "string", "arguments must only contain strings")

        local filter: string?
        if argument == FILTER_FLAG then
            index += 1
            filter = arguments[index]
        elseif argument:sub(1, #FILTER_PREFIX) == FILTER_PREFIX then
            filter = argument:sub(#FILTER_PREFIX + 1)
        else
            table.insert(remaining, argument)
            index += 1
            continue
        end

        if filter == nil or filter == "" then
            error(`The "{FILTER_FLAG}" flag needs the text to filter test names by.`, 0)
        elseif options.Filter ~= nil then
            error(`The "{FILTER_FLAG}" flag can only be given once.`, 0)
        end

        options.Filter = filter
        index += 1
    end

    return options, remaining
end

return FilterArguments
