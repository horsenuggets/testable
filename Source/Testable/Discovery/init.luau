--[[

Discovery

Finds, selects, and re-runs spec files on Lune. Specs are discovered from include globs,
narrowed to the ones affected by a set of changes through the require graph, and watched
for changes. This module needs Lune's filesystem and process libraries, so Testable only
requires it on first use and the package still loads on Roblox.

--]]

const ChangeTracker = require("@self/ChangeTracker")
const Config = require("@self/../Config")
const Git = require("@self/Git")
const Glob = require("@self/Glob")
const Loader = require("@self/Loader")
const PathUtil = require("@self/PathUtil")
const RequireGraph = require("@self/RequireGraph")
const RequireParser = require("@self/RequireParser")
const SpecNames = require("@self/SpecNames")
const fs = require("@lune/fs")
const process = require("@lune/process")
const task = require("@lune/task")

export type Options = {
    Exclude: { string }?,
    Include: { string },
    Root: string?,
    WorkerSetup: string?
}
export type DiscoverOptions = Options & {
    Files: { string }?
}
export type AffectedOptions = Options & {
    Changed: { string }
}
export type ChangedOptions = Options & {
    Ref: string
}
export type WatchOptions = Options & {
    Debounce: number?,
    Interval: number?,
    Log: ((message: string) -> ())?,
    Run: (specFiles: { string }, changedFiles: { string }) -> (),
    RunOnStart: boolean?
}
export type ChildOptions = {
    Arguments: { string }?,
    Files: { string },
    Root: string?,
    Script: string
}
export type TestRoot = {
    Func: any,
    Name: string
}
export type WatchHandle = {
    Stop: () -> ()
}

const DEFAULT_DEBOUNCE = 0.2
const DEFAULT_INTERVAL = 0.25
const FILE_SYSTEM: Glob.FileSystem = {
    IsDir = fs.isDir,
    IsFile = fs.isFile,
    ReadDir = fs.readDir,
    ReadFile = fs.readFile
}

const Discovery = {}

const function assertOptions(options: Options)
    assert(type(options) == "table", "options must be a table")
    assert(type(options.Include) == "table", "options.Include must be an array of globs")
    assert(options.Exclude == nil or type(options.Exclude) == "table", "options.Exclude must be an array of globs")
    assert(options.Root == nil or type(options.Root) == "string", "options.Root must be a string")
    assert(options.WorkerSetup == nil or type(options.WorkerSetup) == "string", "options.WorkerSetup must be a string")
end

--[[
    Resolves the root of a set of options to an absolute path. The working directory is
    the root when none is given.

    @param root - The root from the options, absolute or relative to the working directory
    @return The absolute, normalized root
]]
const function resolveRoot(root: string?): string
    return PathUtil.join(process.cwd, root or ".")
end

const function quoteList(values: { string }): string
    const quoted = {}
    for _, value in values do
        table.insert(quoted, `"{value}"`)
    end
    return table.concat(quoted, ", ")
end

--[[
    Converts file paths that are absolute or relative to the root into normalized,
    root-relative paths.

    @param root - The absolute root
    @param files - The paths to convert
    @return The root-relative paths, in the same order
]]
const function toRootRelative(root: string, files: { string }): { string }
    const relativeFiles = {}
    for _, file in files do
        const absolute = PathUtil.join(root, file)
        table.insert(relativeFiles, PathUtil.relative(root, absolute) or absolute)
    end
    return relativeFiles
end

const function toAbsolute(root: string, files: { string }): { string }
    const absoluteFiles = {}
    for _, file in files do
        table.insert(absoluteFiles, PathUtil.join(root, file))
    end
    return absoluteFiles
end

--[[
    Rewrites absolute globs as root-relative ones, since matching is always done against
    root-relative paths. An absolute glob outside the root keeps its leading ".."
    segments and therefore matches nothing.

    @param root - The absolute root
    @param globs - The globs to rewrite
    @return The globs, all relative to the root
]]
const function toRootRelativeGlobs(root: string, globs: { string }): { string }
    const relativeGlobs = {}
    for _, glob in globs do
        const relativeGlob = if PathUtil.isAbsolute(glob) then PathUtil.relative(root, glob) else nil
        table.insert(relativeGlobs, relativeGlob or glob)
    end
    return relativeGlobs
end

--[[
    Finds the spec files that match the include globs, without raising an error when
    there are none.

    @param root - The absolute root
    @param options - The discovery options
    @return Sorted, root-relative spec file paths
]]
const function findMatching(root: string, options: Options): { string }
    const exclude: { string } = options.Exclude or {}
    return Glob.find(FILE_SYSTEM, root, toRootRelativeGlobs(root, options.Include), toRootRelativeGlobs(root, exclude))
end

--[[
    Finds the spec files that match the include globs. Hidden files and directories are
    skipped, and the result is sorted. Matching nothing is an error, since it almost
    always means the globs or the root are wrong.

    Specific Files narrow the matching paths without requiring any spec. Every selected
    file must match the globs, and an explicitly empty selection returns an empty list.

    @param options - The include globs, optional exclude globs, optional root, and an
        optional list of spec files to narrow the run to
    @return Sorted, root-relative spec file paths
]]
function Discovery.findSpecs(options: DiscoverOptions): { string }
    assertOptions(options)
    assert(options.Files == nil or type(options.Files) == "table", "options.Files must be an array of paths")

    const root = resolveRoot(options.Root)
    const files = findMatching(root, options)
    if #files == 0 then
        error(`No spec files in "{root}" match {quoteList(options.Include)}.`, 0)
    end

    if options.Files == nil then
        return files
    end

    const known: { [string]: boolean } = {}
    for _, file in files do
        known[file] = true
    end

    const selected: { [string]: boolean } = {}
    for _, file in toRootRelative(root, options.Files) do
        if not known[file] then
            error(`"{file}" is not a spec file matched by {quoteList(options.Include)}.`, 0)
        end
        selected[file] = true
    end

    const narrowed = {}
    for _, file in files do
        if selected[file] then
            table.insert(narrowed, file)
        end
    end
    return narrowed
end

--[[
    Requires spec files and returns them as test roots that are ready to be passed to
    Testable.run.

    @param files - Spec file paths, absolute or relative to the root
    @param root - The root the paths are relative to, which defaults to the working
        directory
    @return One test root per file, in the same order
]]
function Discovery.load(files: { string }, root: string?): { TestRoot }
    assert(type(files) == "table", "files must be an array of paths")
    assert(root == nil or type(root) == "string", "root must be a string")

    const absoluteRoot = resolveRoot(root)
    const names = SpecNames.assign(files)
    const testRoots = {}

    for _, file in files do
        const absolute = PathUtil.join(absoluteRoot, file)
        if not fs.isFile(absolute) then
            error(`The spec file "{file}" does not exist.`, 0)
        end

        const func = Loader.load(absolute)
        if type(func) ~= "function" then
            error(`The spec file "{file}" must return a function, but it returned a value of type "{type(func)}".`, 0)
        end
        table.insert(testRoots, { Func = func, Name = names[file] })
    end

    return testRoots
end

--[[
    Discovers spec files from include globs and returns them as test roots that are
    ready to be passed to Testable.run. When specific files are given, only those are
    loaded, and each of them must be matched by the globs.

    @param options - The include globs, optional exclude globs, optional root, and an
        optional list of spec files to narrow the run to
    @return One test root per spec file, sorted by path
]]
function Discovery.discover(options: DiscoverOptions): { TestRoot }
    const files = Discovery.findSpecs(options)
    return Discovery.load(files, options.Root)
end

--[[
    Scans specs and shared execution dependencies without loading any of them. Setup
    resolves like Loader.load, including extension stripping and init directories. Every
    resolution candidate is retained so creation, deletion, and priority changes count.
    The package actor entry is shared even for local runs because specs can start actors.

    @param fileSystem - The filesystem access to scan with
    @param specs - Absolute selected spec paths, in selection order
    @param options - Discovery options, with setup falling back to current configuration
    @return graph - The require graph with explicit shared execution edges
    @return watched - Sorted paths to poll, including absent candidates and alias configs
]]
function Discovery.buildGraph(
    fileSystem: RequireGraph.FileSystem,
    specs: { string },
    options: Options
): (RequireGraph.Graph, { string })
    assert(type(fileSystem) == "table", "fileSystem must be a table")
    assert(type(specs) == "table", "specs must be an array of paths")
    assertOptions(options)

    const root = resolveRoot(options.Root)
    const moduleDirectory = Loader.moduleDirectory(debug.info(Loader.load, "s"), process.cwd)
    const execution = { PathUtil.join(moduleDirectory, "../Workers/Entry.exec.luau") }
    const entries = table.clone(specs)
    table.insert(entries, execution[1])

    const workerSetup = options.WorkerSetup or Config.WorkerSetup
    if workerSetup ~= nil then
        local target = PathUtil.stripLuauExtension(PathUtil.join(root, workerSetup))
        if PathUtil.basename(target) == "init" then
            target = PathUtil.dirname(target)
        end
        const relative = PathUtil.relative(root, target)
        assert(relative ~= nil, "WorkerSetup must be on the same drive as the root")
        const resolved, candidates =
            RequireGraph.resolve(fileSystem, PathUtil.join(root, "ExecutionDependencies.luau"), `./{relative}`)
        for _, candidate in candidates do
            table.insert(execution, candidate)
        end
        if resolved ~= nil then
            table.insert(entries, resolved)
        end
    end

    const graph = RequireGraph.build(fileSystem, entries)
    const shared = table.clone(execution)
    -- Collect execution paths before attaching specs, so their ordinary hidden-file
    -- filtering is preserved. Installed packages can themselves be in hidden directories.
    const executionFiles: { [string]: boolean } = {}
    local index = 1
    while index <= #execution do
        const file = execution[index]
        index += 1
        if executionFiles[file] then
            continue
        end
        executionFiles[file] = true
        for _, dependency in graph[file] or {} do
            table.insert(execution, dependency)
        end
    end

    for _, spec in specs do
        const dependencies = graph[spec]
        const seen: { [string]: boolean } = {}
        for _, dependency in dependencies do
            seen[dependency] = true
        end
        for _, file in shared do
            if not seen[file] then
                seen[file] = true
                table.insert(dependencies, file)
            end
        end
        table.sort(dependencies)
    end

    const watchedSet: { [string]: boolean } = {}
    for _, file in ChangeTracker.watchList(root, RequireGraph.files(graph)) do
        watchedSet[file] = true
    end
    for file in executionFiles do
        watchedSet[file] = true
        -- Explicit execution dependencies must still be polled when a package lives
        -- outside Root or under a hidden install directory.
        for _, path in ChangeTracker.watchList(PathUtil.dirname(file), { file }) do
            watchedSet[path] = true
        end
    end
    const watched = {}
    for file in watchedSet do
        table.insert(watched, file)
    end
    table.sort(watched)
    return graph, watched
end

--[[
    Finds the specs affected by a set of changed files, meaning the spec changed or it
    transitively requires a file that did, including shared execution dependencies.

    @param options - The discovery options, plus the changed files as paths that are
        absolute or relative to the root
    @return Sorted, root-relative paths of the affected specs, which may be empty
]]
function Discovery.findAffected(options: AffectedOptions): { string }
    assertOptions(options)
    assert(type(options.Changed) == "table", "options.Changed must be an array of paths")

    const root = resolveRoot(options.Root)
    const specs = toAbsolute(
        root,
        Discovery.findSpecs({
            Exclude = options.Exclude,
            Include = options.Include,
            Root = root
        })
    )
    const changed = toAbsolute(root, options.Changed)
    const graph = Discovery.buildGraph(FILE_SYSTEM, specs, options)

    return toRootRelative(root, RequireGraph.findAffected(graph, specs, changed))
end

--[[
    Finds the specs affected by everything that changed since a git ref, including
    changes that are not committed yet and files that are not tracked yet. A root
    outside a git repository and an unknown ref are both errors.

    @param options - The discovery options, plus the git ref to compare against
    @return Sorted, root-relative paths of the affected specs, which may be empty
]]
function Discovery.findChanged(options: ChangedOptions): { string }
    assertOptions(options)
    assert(type(options.Ref) == "string", "options.Ref must be a string")

    const root = resolveRoot(options.Root)
    const function exec(arguments: { string }, workingDirectory: string): Git.ExecResult
        const ok, result = pcall(process.exec, "git", arguments, { cwd = workingDirectory })
        if not ok then
            error(`Git could not be run. {tostring(result)}`, 0)
        end
        return { Ok = result.ok, Stderr = result.stderr, Stdout = result.stdout }
    end

    if not fs.isDir(root) then
        error(`The root "{root}" is not a directory.`, 0)
    end

    return Discovery.findAffected({
        Changed = toAbsolute(root, Git.changedFiles(exec, root, options.Ref)),
        Exclude = options.Exclude,
        Include = options.Include,
        Root = root,
        WorkerSetup = options.WorkerSetup
    })
end

--[[
    Runs a script in a child Lune process, passing the given spec files as trailing
    arguments and sharing this process's output streams. Each child starts with an empty
    module cache, so it always sees the code that is currently on disk.

    @param options - The script to run, the spec files to pass to it, optional leading
        arguments, and the optional root to run in
    @return True if the child exited successfully
]]
function Discovery.runInChild(options: ChildOptions): boolean
    assert(type(options) == "table", "options must be a table")
    assert(type(options.Script) == "string", "options.Script must be a string")
    assert(type(options.Files) == "table", "options.Files must be an array of paths")
    assert(options.Arguments == nil or type(options.Arguments) == "table", "options.Arguments must be an array")
    assert(options.Root == nil or type(options.Root) == "string", "options.Root must be a string")

    const arguments = { "run", options.Script }
    const leadingArguments: { string } = options.Arguments or {}
    for _, argument in leadingArguments do
        table.insert(arguments, argument)
    end
    for _, file in options.Files do
        table.insert(arguments, file)
    end

    const result = process.exec("lune", arguments, {
        cwd = resolveRoot(options.Root),
        stdio = "forward"
    })

    return result.ok
end

--[[
    Reads the signature of each file in a list, made of its modification time and its
    size. The size is included because two quick writes can land on the same timestamp
    on filesystems with coarse clocks. Files that do not exist are left out.

    @param paths - The absolute paths to read
    @return A snapshot mapping each existing path to its signature
]]
const function takeSnapshot(paths: { string }): ChangeTracker.Snapshot
    const snapshot = {}
    for _, path in paths do
        const ok, metadata = pcall(fs.metadata, path)
        if ok and metadata.exists and metadata.modifiedAt ~= nil then
            snapshot[path] = `{metadata.modifiedAt.unixTimestampMillis}/{tostring(metadata.size)}`
        end
    end
    return snapshot
end

--[[
    Watches the specs and everything they transitively require, and calls the run
    callback with the affected specs whenever files change. Changes are debounced, and
    hidden files are ignored except for ".luaurc" files.

    Lune caches required modules for the life of a process, so the callback must not run
    the specs in this process. Run them in a child process instead, for example with
    Discovery.runInChild, so each pass loads the code that is currently on disk.

    The watcher polls file modification times and sizes, and keeps the process alive until the returned
    handle is stopped.

    @param options - The discovery options, the run callback, and optional timing. The
        callback receives the affected specs and the changed files, both relative to the
        root. Every spec runs once at the start unless RunOnStart is false. Status
        messages go to Log, which defaults to print.
    @return A handle whose Stop function ends the watch
]]
function Discovery.watch(options: WatchOptions): WatchHandle
    assertOptions(options)
    assert(type(options.Run) == "function", "options.Run must be a function")
    assert(options.Debounce == nil or type(options.Debounce) == "number", "options.Debounce must be a number")
    assert(options.Interval == nil or type(options.Interval) == "number", "options.Interval must be a number")
    assert(options.Log == nil or type(options.Log) == "function", "options.Log must be a function")
    assert(options.RunOnStart == nil or type(options.RunOnStart) == "boolean", "options.RunOnStart must be a boolean")

    const root = resolveRoot(options.Root)
    const batch = ChangeTracker.Batch.new(options.Debounce or DEFAULT_DEBOUNCE)
    const interval = options.Interval or DEFAULT_INTERVAL
    const log = options.Log or print
    const banner = `Watching "{root}" for changes. Press Ctrl+C to quit.`
    local graph: RequireGraph.Graph = {}
    local running = true
    local snapshot: ChangeTracker.Snapshot = {}
    local watched: { string } = {}

    const function findSpecs(): { string }
        return toAbsolute(root, findMatching(root, options))
    end

    --[[
        Lists every file to poll, which is the require graph, any spec that appeared
        since the graph was built, and the ".luaurc" files that apply to them.
    ]]
    const function listWatched(specs: { string }): { string }
        const files = table.clone(watched)
        const seen: { [string]: boolean } = {}
        for _, file in files do
            seen[file] = true
        end
        for _, file in ChangeTracker.watchList(root, specs) do
            if not seen[file] then
                seen[file] = true
                table.insert(files, file)
            end
        end
        table.sort(files)
        return files
    end

    const function run(specs: { string }, changed: { string })
        const ok, message = pcall(options.Run, toRootRelative(root, specs), toRootRelative(root, changed))
        if not ok then
            log(`The watch run failed. {tostring(message)}`)
        end
        if running then
            log(banner)
        end
    end

    const function rebuild(): { string }
        const specs = findSpecs()
        graph, watched = Discovery.buildGraph(FILE_SYSTEM, specs, options)
        snapshot = ChangeTracker.rebase(snapshot, takeSnapshot(watched), watched)

        return specs
    end

    const initialSpecs = rebuild()
    if #initialSpecs == 0 then
        error(`No spec files in "{root}" match {quoteList(options.Include)}.`, 0)
    end

    task.spawn(function()
        if options.RunOnStart ~= false then
            run(initialSpecs, {})
        else
            log(banner)
        end

        while running do
            task.wait(interval)
            if not running then
                break
            end

            const current = takeSnapshot(listWatched(findSpecs()))
            batch:Add(ChangeTracker.diff(snapshot, current), os.clock())
            snapshot = current

            const changed = batch:Take(os.clock())
            if changed == nil then
                continue
            end

            const specs = rebuild()
            const affected = RequireGraph.findAffected(graph, specs, changed)
            if #affected == 0 then
                log("No specs are affected by the changed files.")
            else
                run(affected, changed)
            end
        end
    end)

    return {
        Stop = function()
            running = false
        end
    }
end

Discovery.ChangeTracker = ChangeTracker
Discovery.Git = Git
Discovery.Glob = Glob
Discovery.Loader = Loader
Discovery.PathUtil = PathUtil
Discovery.RequireGraph = RequireGraph
Discovery.RequireParser = RequireParser
Discovery.SpecNames = SpecNames

return Discovery
