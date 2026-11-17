--[[

ChangeTracker

Pure pieces of watch mode. Decides which files are worth watching, compares two
snapshots of file signatures, and debounces bursts of changes into a single batch.
The clock is always passed in, so none of this depends on real time.

--]]

const Glob = require("./Glob")
const PathUtil = require("./PathUtil")

export type Snapshot = { [string]: string }
export type Batch = {
    new: (debounce: number) -> Batch,
    Add: (self: Batch, paths: { string }, now: number) -> (),
    Take: (self: Batch, now: number) -> { string }?,
    _debounce: number,
    _lastChange: number?,
    _paths: { [string]: boolean },
}

const CONFIG_FILE_NAME = ".luaurc"

const ChangeTracker = {}

const Batch = {} :: Batch
(Batch :: any).__index = Batch

--[[
    Reports whether a file should be watched. Hidden files and anything inside a hidden
    directory are ignored, except for ".luaurc" files in visible directories. The check
    is made relative to the root, so a project that itself lives inside a hidden
    directory is still watched.

    @param root - The project root
    @param path - The file to check
    @return True if changes to the file should trigger a run
]]
function ChangeTracker.isWatchable(root: string, path: string): boolean
    assert(type(root) == "string", "root must be a string")
    assert(type(path) == "string", "path must be a string")

    const relativePath = PathUtil.relative(root, path) or PathUtil.normalize(path)
    if PathUtil.basename(relativePath) == CONFIG_FILE_NAME then
        return not Glob.isHidden(PathUtil.dirname(relativePath))
    end
    return not Glob.isHidden(relativePath)
end

--[[
    Builds the list of files to watch for a set of source files. This is every watchable
    source file, plus the ".luaurc" of the root, of each file's directory, and of every
    directory above those, whether or not the file exists yet. Alias resolution consults
    all of them, including the ones above the root.

    @param root - The project root
    @param files - The source files that matter, usually every file in the require graph
    @return Sorted paths to watch
]]
function ChangeTracker.watchList(root: string, files: { string }): { string }
    assert(type(root) == "string", "root must be a string")
    assert(type(files) == "table", "files must be an array of paths")

    const normalizedRoot = PathUtil.normalize(root)
    const seen: { [string]: boolean } = {}

    const function addConfigFiles(startDirectory: string)
        local directory = startDirectory
        while true do
            const configPath = PathUtil.join(directory, CONFIG_FILE_NAME)
            if seen[configPath] then
                -- Everything above this directory was added along with it.
                return
            end
            if ChangeTracker.isWatchable(normalizedRoot, configPath) then
                seen[configPath] = true
            end

            const parent = PathUtil.dirname(directory)
            if parent == directory or PathUtil.basename(parent) == ".." then
                return
            end
            directory = parent
        end
    end

    addConfigFiles(normalizedRoot)
    for _, file in files do
        const normalized = PathUtil.normalize(file)
        if ChangeTracker.isWatchable(normalizedRoot, normalized) then
            seen[normalized] = true
            addConfigFiles(PathUtil.dirname(normalized))
        end
    end

    const paths = {}
    for path in seen do
        table.insert(paths, path)
    end
    table.sort(paths)

    return paths
end

--[[
    Compares two snapshots and returns the files that were created, modified, or
    removed between them.

    @param previous - The older snapshot, mapping each existing path to a signature that
        changes whenever the file does
    @param current - The newer snapshot
    @return Sorted paths that differ
]]
function ChangeTracker.diff(previous: Snapshot, current: Snapshot): { string }
    assert(type(previous) == "table", "previous must be a table")
    assert(type(current) == "table", "current must be a table")

    const changed = {}
    for path, signature in current do
        if previous[path] ~= signature then
            table.insert(changed, path)
        end
    end
    for path in previous do
        if current[path] == nil then
            table.insert(changed, path)
        end
    end
    table.sort(changed)

    return changed
end

--[[
    Carries a snapshot over to a new watch list. Files that stay watched keep their
    previous signature, so a change made in the meantime is still noticed by the next
    comparison. Files that just joined the list start out unchanged, and files that left
    it are dropped, so they are not mistaken for deleted files later.

    @param previous - The snapshot from before the watch list changed
    @param current - A fresh snapshot of the new watch list
    @param watched - The new watch list
    @return The snapshot to compare the next poll against
]]
function ChangeTracker.rebase(previous: Snapshot, current: Snapshot, watched: { string }): Snapshot
    assert(type(previous) == "table", "previous must be a table")
    assert(type(current) == "table", "current must be a table")
    assert(type(watched) == "table", "watched must be an array of paths")

    const rebased: Snapshot = {}
    for _, path in watched do
        rebased[path] = previous[path] or current[path]
    end

    return rebased
end

--[[
    Creates a batch that collects changed paths until they have been quiet for the
    debounce period.

    @param debounce - Seconds without a new change before the batch is released
    @return The new, empty batch
]]
function Batch.new(debounce: number): Batch
    assert(type(debounce) == "number" and debounce >= 0, "debounce must be a non-negative number")

    return setmetatable({
        _debounce = debounce,
        _lastChange = nil,
        _paths = {},
    }, Batch :: any) :: any
end

--[[
    Adds changed paths to the batch and restarts the debounce period.

    @param paths - The paths that changed
    @param now - The current time in seconds
]]
function Batch.Add(self: Batch, paths: { string }, now: number)
    assert(type(paths) == "table", "paths must be an array of paths")
    assert(type(now) == "number", "now must be a number")

    if #paths == 0 then
        return
    end
    for _, path in paths do
        self._paths[path] = true
    end
    self._lastChange = now
end

--[[
    Releases the collected paths once the debounce period has passed since the last
    change, and empties the batch.

    @param now - The current time in seconds
    @return Sorted changed paths, or nil while there is nothing to release yet
]]
function Batch.Take(self: Batch, now: number): { string }?
    assert(type(now) == "number", "now must be a number")

    const lastChange = self._lastChange
    if lastChange == nil or now - lastChange < self._debounce then
        return nil
    end

    const paths = {}
    for path in self._paths do
        table.insert(paths, path)
    end
    table.sort(paths)

    self._paths = {}
    self._lastChange = nil

    return paths
end

ChangeTracker.Batch = Batch

return ChangeTracker
