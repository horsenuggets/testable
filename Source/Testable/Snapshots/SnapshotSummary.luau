--[[

SnapshotSummary

Formats what happened to snapshots during a run as lines for the run summary. Nothing is
printed for runs that only matched existing snapshots.

--]]

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

return SnapshotSummary
