--[[

SnapshotArguments

Parses the command-line flags for snapshot testing into Testable configuration options.
Parsing is pure, so it never reads the process arguments itself, and arguments it doesn't
know are handed back for the caller to deal with.

--]]

export type Options = {
    UpdateSnapshots: boolean?,
}

const SnapshotArguments = {}

SnapshotArguments.Usage = "[--update-snapshots]"

--[[
    Parses snapshot flags out of a list of command-line arguments.

    > --update-snapshots, -u - Accepts changed snapshots and removes obsolete ones.

    @param arguments - The command-line arguments
    @return options - The configuration options the flags describe
    @return remaining - The arguments that aren't snapshot flags, in their original order
]]
function SnapshotArguments.parse(arguments: { string }): (Options, { string })
    assert(type(arguments) == "table", "arguments must be a table")

    const options: Options = {}
    const remaining = {}
    for _, argument in arguments do
        if argument == "--update-snapshots" or argument == "-u" then
            options.UpdateSnapshots = true
        else
            table.insert(remaining, argument)
        end
    end

    return options, remaining
end

return SnapshotArguments
