--[[

SnapshotManager

Tracks the snapshots of one test run. Each snapshot file is loaded from the store once,
changes are buffered in memory while tests run concurrently, and everything is flushed
back to the store when the run finishes. The store is a small interface, so the same logic
works on the filesystem through Lune and anywhere else through a custom store.

--]]

const Ansi = require("../Ansi")
const SnapshotDiff = require("./SnapshotDiff")
const SnapshotFormat = require("./SnapshotFormat")
const SnapshotLogic = require("./SnapshotLogic")
const SnapshotSerializer = require("./SnapshotSerializer")
const TestEnum = require("../TestEnum")

const NO_STORE_MESSAGE = "Snapshots need a store, and no filesystem is available in this runtime. "
    .. "Set one with Testable.configure({ SnapshotStore = store })."
const UPDATE_HINT = "If the change is intended, run again with snapshot updates enabled."

const SnapshotManager = {}
SnapshotManager.__index = SnapshotManager

-- Where snapshot files are kept. Functions may yield, and "read" returns nil for a file
-- that does not exist.
export type Store = {
    read: (path: string) -> string?,
    write: (path: string, contents: string) -> (),
}

export type Options = {
    -- Whether the Lune filesystem store may be used when no store is set. This is
    -- detected from the runtime when left out.
    HasFilesystem: boolean?,
    Store: Store?,
    Update: boolean?,
}

-- Identifies the running test to the matcher and numbers its snapshots.
export type Scope = {
    Count: number,
    Manager: SnapshotManager,
    PlanNode: any,
}

export type ObsoleteSnapshot = {
    Key: string,
    Path: string,
}

export type Summary = {
    Failed: number,
    Matched: number,
    Obsolete: { ObsoleteSnapshot },
    Removed: number,
    Updated: number,
    Written: number,
}

type File = {
    Entries: SnapshotFormat.Entries,
    Error: string?,
    IsDirty: boolean,
    -- Set when a run that used the file skipped or failed tests that belong to it.
    IsIncomplete: boolean,
    Path: string,
    UsedKeys: { [string]: boolean },
    -- How many unfinished runs are using the file.
    Users: number,
}

--[[
    The files that unfinished runs have loaded, by store and then by path. A test can
    start a nested run whose spec shares a snapshot file with the outer one (e.g., a spec
    function defined inside the outer spec's file). Both runs then work on one copy of the
    file, so neither overwrites the other's snapshots with a stale copy, and obsolete
    detection waits until the last of them finishes and every key has had its chance to
    be used. A file leaves this table when its last run finishes.
]]
const openFiles: { [Store]: { [string]: File } } = setmetatable({}, { __mode = "k" }) :: any

export type SnapshotManager = typeof(setmetatable(
    {} :: {
        _displayRoot: string?,
        _files: { [string]: File },
        _hasFilesystem: boolean,
        _isUpdating: boolean,
        _paths: { [any]: string },
        _store: Store?,
        _summary: Summary,
    },
    SnapshotManager
))

--[[
    Creates a manager for one test run.

    @param options - The store to use and whether update mode is on
    @return The new manager
]]
function SnapshotManager.new(options: Options?): SnapshotManager
    assert(options == nil or type(options) == "table", "options must be a table or nil")

    const self = {
        _displayRoot = nil,
        _files = {},
        _hasFilesystem = if options ~= nil and options.HasFilesystem ~= nil
            then options.HasFilesystem
            else Ansi.isLune(),
        _isUpdating = options ~= nil and options.Update == true,
        _paths = {},
        _store = if options then options.Store else nil,
        _summary = { Failed = 0, Matched = 0, Obsolete = {}, Removed = 0, Updated = 0, Written = 0 },
    }

    return setmetatable(self, SnapshotManager)
end

--[[
    Creates the scope that ties snapshot assertions to one test.

    @param planNode - The plan node of the running test
    @return The new scope
]]
function SnapshotManager.CreateScope(self: SnapshotManager, planNode: any): Scope
    assert(type(planNode) == "table", "planNode must be a table")
    return { Count = 0, Manager = self, PlanNode = planNode }
end

--[[
    Returns the configured store, or the filesystem store when running on Lune.
]]
function SnapshotManager._getStore(self: SnapshotManager): Store?
    if self._store == nil and self._hasFilesystem then
        self._store = require("./LuneSnapshotStore") :: any
        self._displayRoot = (require("@lune/process").cwd:gsub("\\", "/"))
    end
    return self._store
end

--[[
    Finds the snapshot file path for the spec that owns a plan node. An explicit path on
    the test root wins, then the file the spec function was defined in, then a path built
    from the spec's names.
]]
function SnapshotManager._resolvePath(self: SnapshotManager, planNode: any): string
    -- The spec is the closest ancestor that TestPlanner tagged as a test root. Plans built
    -- by hand have no tagged roots, so those use the outermost node instead.
    local specNode = planNode
    local module = nil
    local node = planNode
    while node ~= nil do
        specNode = node
        if node.specModule ~= nil then
            module = node.specModule
            break
        end
        node = node.parent
    end

    const cached = self._paths[specNode]
    if cached ~= nil then
        return cached
    end

    local path: string? = if module then module.snapshotPath else nil
    if path == nil and type(specNode.callback) == "function" then
        path = SnapshotLogic.pathFromSource(debug.info(specNode.callback, "s"))
    end
    if path == nil then
        const names = {}
        local current = specNode
        while current ~= nil do
            table.insert(names, 1, current.phrase)
            current = current.parent
        end
        path = SnapshotLogic.pathFromNames(names)
    end

    const resolved = path :: string
    self._paths[specNode] = resolved

    return resolved
end

--[[
    Loads a snapshot file from the store the first time it is needed, or joins the copy
    that another unfinished run already loaded. The store may yield, so another test can
    finish loading the same file first, in which case that copy is the one everybody
    shares.
]]
function SnapshotManager._load(self: SnapshotManager, store: Store, path: string): File
    const existing = self._files[path]
    if existing ~= nil then
        return existing
    end

    local storeFiles = openFiles[store]
    if storeFiles == nil then
        storeFiles = {}
        openFiles[store] = storeFiles
    end

    if storeFiles[path] == nil then
        const file: File = {
            Entries = {},
            Error = nil,
            IsDirty = false,
            IsIncomplete = false,
            Path = path,
            UsedKeys = {},
            Users = 0,
        }
        const ok, contents = pcall(store.read, path)
        if not ok then
            file.Error = `Snapshot file "{self:GetDisplayPath(path)}" could not be read. {tostring(contents)}`
        elseif contents ~= nil then
            const entries, message = SnapshotFormat.parse(contents)
            if entries ~= nil then
                file.Entries = entries
            else
                file.Error = `Snapshot file "{self:GetDisplayPath(path)}" is not valid. {message}`
            end
        end

        const loadedMeanwhile = self._files[path]
        if loadedMeanwhile ~= nil then
            return loadedMeanwhile
        end
        if storeFiles[path] == nil then
            storeFiles[path] = file
        end
    end

    const shared = storeFiles[path]
    shared.Users += 1
    self._files[path] = shared

    return shared
end

--[[
    Returns a snapshot file path as it should be shown to the user, which is relative to
    the working directory when the file is inside it.

    @param path - The snapshot file path
    @return The path to display
]]
function SnapshotManager.GetDisplayPath(self: SnapshotManager, path: string): string
    assert(type(path) == "string", "path must be a string")

    const root = self._displayRoot
    if root ~= nil then
        const prefix = if root:sub(-1) == "/" then root else `{root}/`
        if path:sub(1, #prefix) == prefix then
            return path:sub(#prefix + 1)
        end
    end
    return path
end

--[[
    Checks a value against the stored snapshot for the scope's test. A value with nothing
    stored is recorded and passes, an equal value passes, and a different value fails
    with a line diff unless update mode is on.

    @param scope - The scope of the running test
    @param value - The value to check
    @param hint - An optional label that replaces the snapshot's number in its key
    @return passed - Whether the assertion passed
    @return message - Why the assertion failed, when it did
]]
function SnapshotManager.Match(self: SnapshotManager, scope: Scope, value: any, hint: string?): (boolean, string?)
    assert(type(scope) == "table", "scope must be a table")

    if hint ~= nil and (type(hint) ~= "string" or hint == "") then
        return false, "The snapshot hint must be a non-empty string."
    end

    -- The number is claimed before anything can yield or fail, so it only depends on the
    -- order of the assertions inside the test.
    local label = hint
    if label == nil then
        scope.Count += 1
        label = tostring(scope.Count)
    end

    const store = self:_getStore()
    if store == nil then
        return false, NO_STORE_MESSAGE
    end

    const serializedOk, serialized = pcall(SnapshotSerializer.serialize, value)
    if not serializedOk then
        return false, `The value could not be serialized for a snapshot. {tostring(serialized)}`
    end

    const names = {}
    local node = scope.PlanNode
    while node ~= nil do
        table.insert(names, 1, node.phrase)
        node = node.parent
    end
    const key = SnapshotFormat.makeKey(SnapshotFormat.makeTestName(names), label :: string)

    const file = self:_load(store, self:_resolvePath(scope.PlanNode))
    if file.Error ~= nil then
        return false, file.Error
    end

    const stored = file.Entries[key]
    if file.UsedKeys[key] then
        if stored == serialized then
            return true, nil
        end
        return false,
            `Snapshot "{key}" was already checked in this run with a different value. `
                .. "Give each snapshot in a test its own hint."
    end
    file.UsedKeys[key] = true

    const decision = SnapshotLogic.decide(stored, serialized, self._isUpdating)
    if decision == "Match" then
        self._summary.Matched += 1
        return true, nil
    elseif decision == "Mismatch" then
        self._summary.Failed += 1
        const lines = { `Snapshot "{key}" did not match.`, "- Stored", "+ Received", "" }
        for _, line in SnapshotDiff.lines(stored :: string, serialized) do
            table.insert(lines, line)
        end
        table.insert(lines, "")
        table.insert(lines, UPDATE_HINT)
        return false, table.concat(lines, "\n")
    end

    file.Entries[key] = serialized
    file.IsDirty = true
    if decision == "Update" then
        self._summary.Updated += 1
    else
        self._summary.Written += 1
    end

    return true, nil
end

--[[
    Finishes the run by detecting obsolete snapshots and flushing every changed file to
    the store. Obsolete snapshots are stored keys that no test produced. They are removed
    in update mode and reported otherwise. Detection is skipped for the whole run when it
    was filtered or focused, and for any file whose spec had a test or describe block that
    did not pass, because their tests may not have reached their snapshot assertions. A
    file shared with another unfinished run is left for that run to check.

    @param results - The results of the run, used to find what did not pass
    @param isPartialRun - Whether the run was filtered or focused
    @return A summary of what happened to snapshots during the run
]]
function SnapshotManager.Finish(self: SnapshotManager, results: any?, isPartialRun: boolean): Summary
    assert(results == nil or type(results) == "table", "results must be a table or nil")
    assert(type(isPartialRun) == "boolean", "isPartialRun must be a boolean")

    const paths = {}
    for path in self._files do
        table.insert(paths, path)
    end
    table.sort(paths)

    const incompletePaths: { [string]: boolean } = {}
    if results ~= nil and #paths > 0 and not isPartialRun then
        results:visitAllNodes(function(node)
            const planNode = node.planNode

            -- Hook errors are recorded on placeholder tests that are not part of the
            -- plan. Their describe block fails with them, and it identifies the file.
            const isPlaceholder = planNode.type == TestEnum.NodeType.It and planNode.parent == nil
            if node.status ~= TestEnum.TestStatus.Success and not isPlaceholder then
                incompletePaths[self:_resolvePath(planNode)] = true
            end
        end)
    end

    const store = self._store :: Store
    for _, path in paths do
        const file = self._files[path]
        if isPartialRun or incompletePaths[path] then
            file.IsIncomplete = true
        end

        file.Users -= 1
        const isLastUser = file.Users == 0
        if isLastUser then
            openFiles[store][path] = nil
        end
        if file.Error ~= nil then
            continue
        end

        if isLastUser and not file.IsIncomplete then
            for _, key in SnapshotLogic.findObsolete(file.Entries, file.UsedKeys) do
                if self._isUpdating then
                    file.Entries[key] = nil
                    file.IsDirty = true
                    self._summary.Removed += 1
                else
                    table.insert(self._summary.Obsolete, { Key = key, Path = self:GetDisplayPath(path) })
                end
            end
        end

        -- A loaded file always keeps at least the snapshot that caused it to load, so
        -- there is never an empty file to delete.
        if file.IsDirty then
            store.write(path, SnapshotFormat.render(file.Entries))
            file.IsDirty = false
        end
    end

    -- The files are released, so finishing again does nothing.
    self._files = {}

    return self._summary
end

return SnapshotManager
