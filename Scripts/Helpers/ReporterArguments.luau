--[[

ReporterArguments

Parses the command-line flags that choose reporters and their output paths into Testable
configuration options. Parsing is pure, so it never reads the process arguments itself,
and arguments it doesn't know are handed back for the caller to deal with.

--]]

const TestEnum = require("../../Source/Testable/TestEnum")

export type Options = {
    ReporterOutputs: { [string]: string },
    Reporters: { string }?,
    SlowestTests: number?
}

const ReporterArguments = {}

ReporterArguments.Usage = "[--reporter <text|json|junit|lcov> [--output <path>]]... [--slowest <count>]"

--[[
    Raises a message meant for the person running the script. Level zero keeps the source
    position out of it, so the caller can print the message as is.
]]
const function usageError(message: string): never
    error(message, 0)
end

--[[
    Finds the reporter whose name matches the given text without regard to case, so
    "junit" on the command line selects "JUnit".
]]
const function findReporter(text: string): string?
    for _, name in TestEnum.Reporter do
        if name:lower() == text:lower() then
            return name
        end
    end
    return nil
end

--[[
    Parses reporter flags out of a list of command-line arguments.

    > --reporter <name> - Adds a reporter. It can be given several times.
    > --output <path> - Sends the output of the reporter named just before it to a file.
    > --slowest <count> - Lists that many of the slowest tests in the text report.

    @param arguments - The command-line arguments
    @return options - The configuration options the flags describe
    @return remaining - The arguments that aren't reporter flags, in their original order
]]
function ReporterArguments.parse(arguments: { string }): (Options, { string })
    assert(type(arguments) == "table")
    const options: Options = { ReporterOutputs = {} }
    const remaining = {}
    local lastReporter: string? = nil
    local index = 1
    while index <= #arguments do
        const argument = arguments[index]
        const value = arguments[index + 1]
        if argument == "--reporter" then
            const reporter = if value ~= nil then findReporter(value) else nil
            if reporter == nil then
                usageError(`The "--reporter" flag needs "text", "json", "junit", or "lcov", but got "{value or ""}".`)
            end
            const reporters = options.Reporters or {}
            options.Reporters = reporters
            table.insert(reporters, reporter)
            lastReporter = reporter
            index += 2
        elseif argument == "--output" then
            if value == nil or value == "" then
                usageError('The "--output" flag needs a file path.')
            elseif lastReporter == nil then
                usageError('The "--output" flag must come after the "--reporter" flag it belongs to.')
            elseif lastReporter == TestEnum.Reporter.Text then
                usageError('The "text" reporter always writes to standard output, so it can\'t take "--output".')
            elseif options.ReporterOutputs[lastReporter] ~= nil then
                usageError(`The "{lastReporter:lower()}" reporter was given more than one "--output" path.`)
            end
            options.ReporterOutputs[lastReporter :: string] = value :: string
            index += 2
        elseif argument == "--slowest" then
            const count = if value ~= nil then tonumber(value) else nil
            if count == nil or count < 0 or count % 1 ~= 0 then
                usageError(`The "--slowest" flag needs a whole number of tests, but got "{value or ""}".`)
            end
            options.SlowestTests = count
            index += 2
        else
            table.insert(remaining, argument)
            index += 1
        end
    end
    return options, remaining
end

return ReporterArguments
