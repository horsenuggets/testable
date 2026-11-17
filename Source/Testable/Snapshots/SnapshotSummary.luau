--[[

SnapshotSummary

Formats what happened to snapshots during a run, as lines for the text summary and as
named counts for the machine-readable reports. The text summary prints nothing for runs
that only matched existing snapshots.

--]]

const COUNT_NAMES = { "Written", "Updated", "Removed", "Obsolete", "Matched", "Failed" }

-- One count of a summary. "Obsolete" is the number of obsolete snapshots that were found
-- and left in place.
export type Count = {
    Name: string,
    Value: number,
}

const SnapshotSummary = {}

const function count(amount: number, singular: string, plural: string): string
    return `{amount} {if amount == 1 then singular else plural}`
end

--[[
    Returns the summary lines for a run.

    @param summary - The summary produced by SnapshotManager
    @param indent - The indentation used for the list of obsolete snapshots
    @return The lines to print, which are empty when there is nothing to report
]]
function SnapshotSummary.format(summary: any, indent: string): { string }
    assert(type(summary) == "table", "summary must be a table")
    assert(type(indent) == "string", "indent must be a string")

    const lines = {}
    if summary.Written > 0 then
        table.insert(lines, `{count(summary.Written, "snapshot", "snapshots")} written.`)
    end
    if summary.Updated > 0 then
        table.insert(lines, `{count(summary.Updated, "snapshot", "snapshots")} updated.`)
    end
    if summary.Removed > 0 then
        table.insert(lines, `{count(summary.Removed, "obsolete snapshot", "obsolete snapshots")} removed.`)
    end
    if #summary.Obsolete > 0 then
        const found = count(#summary.Obsolete, "obsolete snapshot", "obsolete snapshots")
        const target = if #summary.Obsolete == 1 then "it" else "them"
        table.insert(lines, `{found} found. Run again with snapshot updates enabled to remove {target}.`)
        for _, obsolete in summary.Obsolete do
            table.insert(lines, `{indent}"{obsolete.Key}" in "{obsolete.Path}"`)
        end
    end

    return lines
end

--[[
    Returns the counts of a summary in the fixed order that the machine-readable reports
    write them, so every report names and orders them the same way.

    @param summary - The summary produced by SnapshotManager
    @return The counts, each with its name and value
]]
function SnapshotSummary.counts(summary: any): { Count }
    assert(type(summary) == "table", "summary must be a table")
    assert(type(summary.Obsolete) == "table", "summary.Obsolete must be an array")

    const counts: { Count } = {}
    for _, name in COUNT_NAMES do
        const value = if name == "Obsolete" then #summary.Obsolete else summary[name]
        assert(type(value) == "number", `summary.{name} must be a number`)
        table.insert(counts, { Name = name, Value = value })
    end

    return counts
end

--[[
    Tells whether a run touched any snapshot at all.

    @param summary - The summary produced by SnapshotManager
    @return True if at least one count is above zero
]]
function SnapshotSummary.hasActivity(summary: any): boolean
    for _, entry in SnapshotSummary.counts(summary) do
        if entry.Value > 0 then
            return true
        end
    end
    return false
end

return SnapshotSummary
