--[[

SnapshotLogic

Holds the pure decisions behind snapshot testing, with no I/O. That covers what to do with
a new value given what is stored, which stored snapshots are obsolete, and where the
snapshot file of a spec lives.

--]]

const SNAPSHOT_DIRECTORY = "__snapshots__"
const SNAPSHOT_EXTENSION = ".snap"

const SnapshotLogic = {}

-- What a snapshot assertion does with its value.
export type Decision = "Match" | "Mismatch" | "Update" | "Write"

--[[
    Decides the outcome of a snapshot assertion. A value with nothing stored is written, a
    value equal to the stored one matches, and a different value is a mismatch unless
    update mode is on, in which case it replaces the stored one.

    @param stored - The stored text, or nil if nothing is stored
    @param actual - The newly serialized text
    @param isUpdating - Whether update mode is on
    @return The decision
]]
function SnapshotLogic.decide(stored: string?, actual: string, isUpdating: boolean): Decision
    assert(stored == nil or type(stored) == "string", "stored must be a string or nil")
    assert(type(actual) == "string", "actual must be a string")
    assert(type(isUpdating) == "boolean", "isUpdating must be a boolean")

    if stored == nil then
        return "Write"
    elseif stored == actual then
        return "Match"
    elseif isUpdating then
        return "Update"
    end
    return "Mismatch"
end

--[[
    Finds the stored snapshot keys that no test produced during the run.

    @param entries - The stored values by snapshot key
    @param usedKeys - The set of keys that tests produced
    @return The obsolete keys, sorted
]]
function SnapshotLogic.findObsolete(entries: { [string]: string }, usedKeys: { [string]: boolean }): { string }
    assert(type(entries) == "table", "entries must be a table")
    assert(type(usedKeys) == "table", "usedKeys must be a table")

    const obsolete = {}
    for key in entries do
        if not usedKeys[key] then
            table.insert(obsolete, key)
        end
    end
    table.sort(obsolete)

    return obsolete
end

--[[
    Derives the snapshot file path from the source of a spec function, which is the path
    of the spec file when the runtime reports one. The snapshot file sits in a
    "__snapshots__" directory beside the spec.

    @param source - The source reported by debug.info for the spec function
    @return The snapshot file path, or nil if the source is not a Luau file path
]]
function SnapshotLogic.pathFromSource(source: string): string?
    assert(type(source) == "string", "source must be a string")

    const unified = source:gsub("\\", "/")
    const fileName = unified:match("([^/]+%.luau?)$")
    if fileName == nil then
        return nil
    end

    const directory = unified:sub(1, #unified - #fileName)
    return `{directory}{SNAPSHOT_DIRECTORY}/{fileName}{SNAPSHOT_EXTENSION}`
end

--[[
    Builds a snapshot file path from the names leading to a spec. This is the fallback for
    specs that have no file, such as Roblox instances.

    @param names - The names from the outermost describe block down to the spec
    @return The snapshot file path
]]
function SnapshotLogic.pathFromNames(names: { string }): string
    assert(type(names) == "table", "names must be a table")
    return `{SNAPSHOT_DIRECTORY}/{table.concat(names, "/")}{SNAPSHOT_EXTENSION}`
end

return SnapshotLogic
