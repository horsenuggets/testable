--[[

Coverage

Collects code coverage data from instrumented Luau files using
debug.getcoverage. Accepts a script instance pointing to a source
directory and recursively discovers all modules, passing each to
debug.getcoverage for full-file coverage including local functions.
Coverage is enabled by default in Lune; set LUNE_COVERAGE=0 to
disable.

Modules that no test required have no runtime coverage data, so they are compiled
without running to count their executable lines, and every line counts as missed. A
module that fails to compile counts as zero lines.

Chunks loaded outside of require (e.g., with luau.load in a sandbox) can be registered
with Coverage.track. Every tracked chunk for a file merges with its runtime coverage, so
a line counts as hit when any load of the file ran it.

--]]

const IS_LUNE = pcall(function()
    require("@lune/fs")
end)

const EXCLUDED_SUFFIXES = {
    "%.legacy$",
    "%.server$",
    "%.client$",
    "%.plugin$",
    "%.spec$",
    "%.story$",
    "%.storybook$",
}

export type RawEntry = {
    Depth: number,
    Function: string,
    Hits: { [number]: number },
    LineDefined: number,
}

export type RawFile = {
    Entries: { RawEntry },
    Loaded: boolean,
    Name: string,
    Path: string,
}

export type RawSnapshot = {
    Files: { RawFile },
    Version: number,
}

export type FunctionCoverage = {
    Name: string,
    ExecutableLines: number,
    HitLines: number,
    Percentage: number,
}

export type FileCoverage = {
    Name: string,
    Path: string,
    Functions: { FunctionCoverage },
    ExecutableLines: number,
    HitLines: number,
    -- Hit count of every executable line, keyed by line number. Coverage.collect always
    -- sets it, and it's optional so that reports built by hand stay valid without it.
    LineHits: { [number]: number }?,
    Loaded: boolean,
    Percentage: number,
}

export type CoverageReport = {
    Files: { FileCoverage },
    TotalExecutableLines: number,
    TotalHitLines: number,
    TotalPercentage: number,
}

-- The verdict of comparing a coverage report against a threshold. "Unmeasured" means a
-- threshold was set but there was nothing to hold it against.
export type GateResult = "Failed" | "Passed" | "Unmeasured"

const Coverage = {}

-- Chunks registered with Coverage.track, keyed by normalized file path. Lives outside of
-- Config so that Config.reset doesn't discard coverage recorded earlier in the session.
const trackedChunks: { [string]: { (...any) -> ...any } } = {}

--[[
    Splits a path that already uses forward slashes into its root and the rest. The root
    is a network share like "//server/share", a drive like "C:/" with its letter
    uppercased since drive letters are case-insensitive, "/", or "" for a relative path.
]]
const function splitRoot(path: string): (string, string)
    -- Exactly two leading slashes start a share, and repeated slashes between the server
    -- and share names still name the same share.
    const server, share, afterShare = path:match("^//([^/]+)/+([^/]+)(.*)$")
    if server then
        return `//{server}/{share}/`, afterShare :: string
    end
    const drive, afterDrive = path:match("^(%a):/(.*)$")
    if drive then
        return `{string.upper(drive)}:/`, afterDrive :: string
    end
    if path:sub(1, 1) == "/" then
        return "/", path:sub(2)
    end
    return "", path
end

--[[
    Normalizes a filesystem path so that different spellings of the same file share one
    key. Converts backslashes to slashes, resolves relative paths against the working
    directory, and collapses empty, "." and "segment/.." parts. Parent segments never
    climb past a root, and normalizing a result again returns it unchanged.

    @param path - The filesystem path to normalize
    @param workingDirectory - The folder relative paths start from, defaulting to the
    process's working directory in Lune
    @return The normalized path
]]
function Coverage.normalizePath(path: string, workingDirectory: string?): string
    assert(type(path) == "string")
    assert(workingDirectory == nil or type(workingDirectory) == "string")
    local root, rest = splitRoot((path:gsub("\\", "/")))
    const base = workingDirectory or (if IS_LUNE then require("@lune/process").cwd else nil)
    if root == "" and base then
        -- The working directory uses backslashes on Windows, so it's unified too. Its
        -- trailing slashes go first, so a root like "/" doesn't join into "//".
        const unifiedBase = base:gsub("\\", "/"):gsub("/+$", "")
        root, rest = splitRoot(`{unifiedBase}/{rest}`)
    end

    const segments: { string } = {}
    for _, segment in string.split(rest, "/") do
        if segment == "" or segment == "." then
            continue
        end
        const previous = segments[#segments]
        if segment ~= ".." then
            table.insert(segments, segment)
        elseif previous ~= nil and previous ~= ".." then
            table.remove(segments)
        elseif root == "" then
            -- A relative path keeps the parent segments it can't resolve, while ".." at
            -- a root stays at the root, like the filesystem.
            table.insert(segments, segment)
        end
    end

    return `{root}{table.concat(segments, "/")}`
end

--[[
    Registers a chunk loaded outside of require so its hits count toward the coverage of
    the file at the given path. The same file can be tracked any number of times.

    @param path - The filesystem path of the chunk's source file
    @param chunk - The compiled chunk function, e.g. the result of luau.load
]]
function Coverage.track(path: string, chunk: (...any) -> ...any)
    assert(type(path) == "string")
    assert(type(chunk) == "function")
    const key = Coverage.normalizePath(path)
    const chunks = trackedChunks[key] or {}
    trackedChunks[key] = chunks
    table.insert(chunks, chunk)
end

-- Strict shapes keep transport data acyclic and reject fields that would otherwise be
-- silently discarded. Numeric keys stay numeric, including negative hit markers.
const function assertFields(value: any, fields: { [string]: boolean }, context: string)
    assert(
        type(value) == "table" and getmetatable(value) == nil,
        `Invalid raw coverage {context}. Expected a plain table.`
    )
    for key in value do
        assert(fields[key] == true, `Invalid raw coverage {context}. Unexpected field "{tostring(key)}".`)
    end
    for key in fields do
        assert(value[key] ~= nil, `Invalid raw coverage {context}. Missing field "{key}".`)
    end
end

const function isInteger(value: any): boolean
    return type(value) == "number" and value > -math.huge and value < math.huge and value % 1 == 0
end

const function assertArray(value: any, context: string)
    assert(type(value) == "table" and getmetatable(value) == nil, `Invalid raw coverage {context}. Expected an array.`)
    local count = 0
    for key in value do
        assert(isInteger(key) and key >= 1, `Invalid raw coverage {context}. Expected dense numeric indices.`)
        count += 1
    end
    for index = 1, count do
        assert(value[index] ~= nil, `Invalid raw coverage {context}. Array contains a hole.`)
    end
end

const function validateSnapshot(snapshot: any)
    assertFields(snapshot, { Files = true, Version = true }, "snapshot")
    assert(snapshot.Version == 1, "Invalid raw coverage version. Expected 1.")
    assertArray(snapshot.Files, "files")
    const seen: { [string]: boolean } = {}
    for _, file in snapshot.Files do
        assertFields(file, { Entries = true, Loaded = true, Name = true, Path = true }, "file")
        assert(type(file.Path) == "string" and file.Path ~= "", "Invalid raw coverage path.")
        assert(
            Coverage.normalizePath(file.Path, "/") == file.Path,
            "Raw coverage paths must be normalized absolute paths."
        )
        assert(not seen[file.Path], `Duplicate raw coverage file "{file.Path}".`)
        seen[file.Path] = true
        assert(type(file.Name) == "string", "Invalid raw coverage display name.")
        assert(type(file.Loaded) == "boolean", "Invalid raw coverage loaded flag.")
        assertArray(file.Entries, `entries for "{file.Path}"`)
        for _, entry in file.Entries do
            assertFields(entry, { Depth = true, Function = true, Hits = true, LineDefined = true }, "entry")
            assert(type(entry.Function) == "string", "Invalid raw coverage function name.")
            assert(isInteger(entry.LineDefined) and entry.LineDefined >= 0, "Invalid raw coverage definition line.")
            assert(isInteger(entry.Depth) and entry.Depth >= 0, "Invalid raw coverage function depth.")
            assert(type(entry.Hits) == "table" and getmetatable(entry.Hits) == nil, "Invalid raw coverage hits.")
            for line, count in entry.Hits do
                assert(isInteger(line) and line >= 0, "Invalid raw coverage numeric line key.")
                assert(isInteger(count), "Invalid raw coverage hit count.")
                assert(file.Loaded or count <= 0, "Unloaded raw coverage cannot contain positive hits.")
            end
        end
    end
end

const function assertLayout(first: { RawEntry }, other: { RawEntry }, path: string)
    const message = `Raw coverage layout mismatch for "{path}".`
    assert(#first == #other, `{message} Function count differs.`)
    for index, entry in first do
        const candidate = other[index]
        assert(
            entry.Function == candidate.Function
                and entry.LineDefined == candidate.LineDefined
                and entry.Depth == candidate.Depth,
            `{message} Function identity differs at entry {index}.`
        )
        for line, count in entry.Hits do
            const otherCount = candidate.Hits[line]
            const hasLine = otherCount ~= nil
            assert(hasLine, if hasLine then nil else `{message} Hits key set differs at entry {index}, line {line}.`)
            const hasSameMask = (count >= 0) == (otherCount >= 0)
            assert(
                hasSameMask,
                if hasSameMask then nil else `{message} Executable mask differs at entry {index}, line {line}.`
            )
        end
        for line in candidate.Hits do
            const hasLine = entry.Hits[line] ~= nil
            assert(hasLine, if hasLine then nil else `{message} Hits key set differs at entry {index}, line {line}.`)
        end
    end
end

-- Every layout is checked before any hit arithmetic. Local tracked loads and imported
-- snapshots use exactly the same function identities, masks, and elementwise maximum.
const function mergeEntries(sources: { { RawEntry } }, path: string): { RawEntry }
    for index = 2, #sources do
        assertLayout(sources[1], sources[index], path)
    end
    const merged: { RawEntry } = {}
    for index, entry in sources[1] do
        merged[index] = {
            Depth = entry.Depth,
            Function = entry.Function,
            Hits = table.clone(entry.Hits),
            LineDefined = entry.LineDefined,
        }
    end
    for sourceIndex = 2, #sources do
        for index, entry in sources[sourceIndex] do
            for line, count in entry.Hits do
                merged[index].Hits[line] = math.max(merged[index].Hits[line], count)
            end
        end
    end
    return merged
end

--[[
    Validates and merges explicit snapshots without reading source or retaining imported
    state. Files sort by normalized absolute path. Aliased display names use the smallest
    name lexically, so merging remains independent of snapshot order.
]]
function Coverage.mergeRaw(snapshots: { RawSnapshot }): RawSnapshot
    assertArray(snapshots, "snapshots")
    const byPath: { [string]: { RawFile } } = {}
    const paths: { string } = {}
    for _, snapshot in snapshots do
        validateSnapshot(snapshot)
        for _, file in snapshot.Files do
            if byPath[file.Path] == nil then
                byPath[file.Path] = {}
                table.insert(paths, file.Path)
            end
            table.insert(byPath[file.Path], file)
        end
    end
    -- Validate every file before merging any file, even when a mismatch is in the last
    -- snapshot or a different path from the one whose hits would be merged first.
    for path, files in byPath do
        for index = 2, #files do
            assertLayout(files[1].Entries, files[index].Entries, path)
        end
    end
    table.sort(paths)
    const files: { RawFile } = {}
    for _, path in paths do
        const sources: { { RawEntry } } = {}
        local loaded = false
        local name = byPath[path][1].Name
        for _, file in byPath[path] do
            loaded = loaded or file.Loaded
            if file.Name < name then
                name = file.Name
            end
            table.insert(sources, file.Entries)
        end
        table.insert(files, { Entries = mergeEntries(sources, path), Loaded = loaded, Name = name, Path = path })
    end
    return { Files = files, Version = 1 }
end

--[[
    Checks if a module name should be excluded based on its suffix.

    @param name - The module name to check
    @return True if the name matches an excluded suffix
]]
const function isExcluded(name: string): boolean
    for _, suffix in EXCLUDED_SUFFIXES do
        if name:match(suffix) then
            return true
        end
    end
    return false
end

--[[
    Gets the display name of a script instance, stripping the .luau
    extension if present.

    @param scriptInstance - The script instance
    @return The cleaned module name
]]
const function getDisplayName(scriptInstance: any): string
    const name = scriptInstance.Name
    return name:gsub("%.luau$", ""):gsub("%.lua$", "")
end

--[[
    Recursively discovers all Luau modules under a directory using the
    filesystem API. Handles both regular .luau files and directories
    with init.luau (which represent a single module). Only available
    in Lune.

    @param dirScript - The script instance representing a directory
    @param results - Array to accumulate { Name, Script } entries
    @param seen - Set of already-processed paths for deduplication
]]
const function discoverModules(dirScript: any, results: { { Name: string, Script: any } }, seen: { [string]: boolean })
    if not IS_LUNE then
        return
    end

    const fs = require("@lune/fs")
    const dirPath = tostring(dirScript)

    const ok, entries = pcall(fs.readDir, dirPath)
    if not ok then
        return
    end

    for _, entry in entries do
        const fullPath = dirPath .. "/" .. entry
        const isDir = fs.isDir(fullPath)

        if isDir then
            const initPath = fullPath .. "/init.luau"
            if fs.isFile(initPath) then
                -- Directory with init.luau is a module
                const childScript = dirScript[entry]
                const scriptPath = tostring(childScript)
                if not seen[scriptPath] and not isExcluded(entry) then
                    seen[scriptPath] = true
                    table.insert(results, {
                        Name = entry,
                        Script = childScript,
                    })
                end
            end
            -- Recurse into subdirectory regardless (may contain
            -- more modules alongside or inside the init module)
            discoverModules(dirScript[entry], results, seen)
        elseif entry:match("%.luau$") or entry:match("%.lua$") then
            const baseName = entry:gsub("%.luau$", ""):gsub("%.lua$", "")
            -- Skip init files (handled as directory modules above)
            if baseName == "init" then
                continue
            end
            if not isExcluded(baseName) then
                const childScript = dirScript[baseName]
                const scriptPath = tostring(childScript)
                if not seen[scriptPath] then
                    seen[scriptPath] = true
                    table.insert(results, {
                        Name = baseName,
                        Script = childScript,
                    })
                end
            end
        end
    end
end

--[[
    Returns the share of hit lines as a percentage floored to two decimals, so small
    totals like 0.09% don't round away to zero. Zero executable lines yields 0.
]]
function Coverage.percentage(hit: number, executable: number): number
    assert(type(hit) == "number")
    assert(type(executable) == "number")
    -- Scale before dividing so exact hundredths like 29 / 10000 don't land just below
    -- their boundary and floor away.
    return if executable > 0 then math.floor(hit * 10000 / executable) / 100 else 0
end

--[[
    Compiles a module that never ran and returns its coverage entries without executing
    it. Returns nil when the file can't be read or compiled.

    @param path - The filesystem path of the module source
    @return entries - The debug.getcoverage entries, or nil
]]
const function compileCoverageEntries(path: string): { any }?
    const fs = require("@lune/fs")
    const luau = require("@lune/luau")
    const ok, entries = pcall(function()
        const bytecode = luau.compile(fs.readFile(path), { coverageLevel = 1 })
        return debug.getcoverage(luau.load(bytecode, { debugName = path }))
    end)
    return if ok and type(entries) == "table" then entries else nil
end

-- Gathers actual runtime entries, including tracked loads. Only never-loaded sources
-- are compiled, without execution, to retain zero-hit executable lines.
const function gatherEntries(scriptInstances: { any }, path: string): ({ RawEntry }, boolean)
    const sources: { { RawEntry } } = {}
    for _, scriptInstance in ipairs(scriptInstances) do
        const ok, runtimeEntries = pcall(debug.getcoverage, scriptInstance)
        if ok and type(runtimeEntries) == "table" then
            table.insert(sources, runtimeEntries)
        end
    end
    const chunks: { (...any) -> ...any } = trackedChunks[Coverage.normalizePath(path)] or {}
    for _, chunk in chunks do
        table.insert(sources, debug.getcoverage(chunk))
    end

    if #sources > 0 then
        return mergeEntries(sources, path), true
    end
    return compileCoverageEntries(path) or {}, false
end

-- Reports function totals separately, while overlapping source lines use a maximum.
const function reportEntries(
    entries: { RawEntry },
    loaded: boolean
): ({ FunctionCoverage }, number, number, { [number]: number })
    const fileFunctions: { FunctionCoverage } = {}
    const lineHits: { [number]: number } = {}
    local fileHit = 0
    local fileExecutable = 0

    for _, entry in entries do
        local funcHit = 0
        local funcExecutable = 0

        for line, hitCount in entry.Hits do
            if hitCount >= 0 then
                funcExecutable += 1
                if loaded and hitCount > 0 then
                    funcHit += 1
                end
                -- A module that was only compiled never ran, so its lines have no hits.
                lineHits[line] = math.max(lineHits[line] or 0, if loaded then hitCount else 0)
            end
        end

        fileHit += funcHit
        fileExecutable += funcExecutable

        const pct = Coverage.percentage(funcHit, funcExecutable)

        local funcName = entry.Function
        if funcName == "" then
            funcName = "(top-level)"
        end

        table.insert(fileFunctions, {
            Name = funcName,
            ExecutableLines = funcExecutable,
            HitLines = funcHit,
            Percentage = pct,
        })
    end

    return fileFunctions, fileHit, fileExecutable, lineHits
end

--[[
    Resolves a single script instance into discovered modules. Handles
    directories (recursively discovers .luau files), directories with
    init.luau (treated as a module), and individual file scripts.

    @param scriptInstance - Script instance to resolve
    @param results - Array to accumulate { Name, Script } entries
    @param seen - Set of already-processed paths for deduplication
]]
const function resolveScript(
    scriptInstance: any,
    name: string,
    results: { { Name: string, Script: any } },
    seen: { [string]: boolean }
)
    if not IS_LUNE then
        return
    end

    const fs = require("@lune/fs")
    const scriptPath = tostring(scriptInstance)

    if fs.isDir(scriptPath) then
        -- Check if the directory itself is a module (has init.luau)
        const initPath = scriptPath .. "/init.luau"
        if fs.isFile(initPath) then
            if not seen[scriptPath] and not isExcluded(name) then
                seen[scriptPath] = true
                table.insert(results, {
                    Name = name,
                    Script = scriptInstance,
                })
            end
        end

        -- Discover child modules
        discoverModules(scriptInstance, results, seen)
    elseif fs.isFile(scriptPath) or fs.isFile(scriptPath .. ".luau") or fs.isFile(scriptPath .. ".lua") then
        -- Individual file
        if not seen[scriptPath] and not isExcluded(name) then
            seen[scriptPath] = true
            table.insert(results, {
                Name = name,
                Script = scriptInstance,
            })
        end
    end
end

--[[
    Resolves CoverageRoots into a flat list of modules. Accepts a script reference,
    filesystem path, or dictionary of named references or paths. Relative paths use the
    working directory and reconstruct VM-local references without requiring source.

    Single script: script.Parent.Source
    Dictionary:    { Chalk = script.Parent.Source.Chalk, Utils = ... }

    @param roots - Script instance or dictionary of script instances
    @return scripts - Array of { Name, Script } entries
]]
function Coverage.resolveRoots(roots: any): { { Name: string, Script: any } }
    const function resolveValue(value: any): any
        if type(value) ~= "string" then
            return value
        end
        assert(IS_LUNE, "Filesystem coverage paths require Lune.")
        assert(value:find("%S") ~= nil, "Coverage paths must not be blank.")
        -- ScriptReference child lookup accepts absolute paths without requiring the
        -- source. The worker constructs its own reference; userdata never crosses VMs.
        const path = Coverage.normalizePath(value)
        return script[path]
    end
    const results: { { Name: string, Script: any } } = {}
    const seen: { [string]: boolean } = {}

    -- Detect if roots is a dictionary (table with string keys) or
    -- a single script instance (userdata with Name/Parent)
    if type(roots) == "table" then
        -- Dictionary format: { Name = scriptInstance, ... }
        const keys = {}
        for key in pairs(roots) do
            table.insert(keys, key)
        end
        table.sort(keys)

        for _, name in keys do
            resolveScript(resolveValue(roots[name]), name, results, seen)
        end
    else
        -- A path is resolved locally to the same reference a script root would supply.
        const root = resolveValue(roots)
        resolveScript(root, getDisplayName(root), results, seen)
    end

    return results
end

-- Extension aliases and directory/file roots share one physical source, while every
-- reference contributes its actual runtime entries.
const function groupRoots(roots: any): { [string]: { Name: string, Scripts: { any } } }
    const fs = require("@lune/fs")
    const groups: { [string]: { Name: string, Scripts: { any } } } = {}
    for _, entry in Coverage.resolveRoots(roots) do
        local path = tostring(entry.Script)
        if fs.isDir(path) then
            path = `{path}/init.luau`
        elseif not fs.isFile(path) then
            path = if fs.isFile(`{path}.luau`) then `{path}.luau` else `{path}.lua`
        end
        path = Coverage.normalizePath(path)
        local group = groups[path]
        if group == nil then
            group = { Name = entry.Name, Scripts = {} }
            groups[path] = group
        elseif entry.Name < group.Name then
            group.Name = entry.Name
        end
        table.insert(group.Scripts, entry.Script)
    end
    return groups
end

--[[
    Captures owned, acyclic raw coverage for transport to a coordinator. Returns nil when
    coverage is disabled. Loaded files retain their actual ordered debug.getcoverage
    entries, never a reconstruction from source or report totals.
]]
function Coverage.captureRaw(roots: any): RawSnapshot?
    const hasApi = type(debug.iscoverageenabled) == "function"
    if not hasApi or not debug.iscoverageenabled() then
        return nil
    end

    const files: { RawFile } = {}
    for path, group in pairs(groupRoots(roots)) do
        const entries, loaded = gatherEntries(group.Scripts, path)
        table.insert(files, { Entries = entries, Loaded = loaded, Name = group.Name, Path = path })
    end
    return Coverage.mergeRaw({ { Files = files, Version = 1 } })
end

const function reportFile(file: RawFile): FileCoverage
    const fileFunctions, fileHit, fileExecutable, lineHits = reportEntries(file.Entries, file.Loaded)
    return {
        Name = file.Name,
        Path = file.Path,
        Functions = fileFunctions,
        ExecutableLines = fileExecutable,
        HitLines = fileHit,
        LineHits = lineHits,
        Loaded = file.Loaded,
        Percentage = Coverage.percentage(fileHit, fileExecutable),
    }
end

-- File rows are independently owned and already sorted by absolute path. Convert paths
-- only after sorting, since relative display paths can change their lexical order.
const function reportFiles(files: { FileCoverage }): CoverageReport
    const cwd = if IS_LUNE then Coverage.normalizePath(require("@lune/process").cwd) else ""
    const prefix = if cwd:sub(-1) == "/" then cwd else `{cwd}/`
    local grandTotalHit = 0
    local grandTotalExecutable = 0
    for _, file in files do
        grandTotalHit += file.HitLines
        grandTotalExecutable += file.ExecutableLines
        if cwd ~= "" and file.Path:sub(1, #prefix) == prefix then
            file.Path = file.Path:sub(#prefix + 1)
        end
    end
    return {
        Files = files,
        TotalExecutableLines = grandTotalExecutable,
        TotalHitLines = grandTotalHit,
        TotalPercentage = Coverage.percentage(grandTotalHit, grandTotalExecutable),
    }
end

--[[
    Converts a raw snapshot into the existing report shape without reading or compiling
    source files. Validation and copying also make standalone worker snapshots safe to
    report without requiring a separate merge first.
]]
function Coverage.collectRaw(snapshot: RawSnapshot): CoverageReport
    const owned = Coverage.mergeRaw({ snapshot })
    const files: { FileCoverage } = {}
    for _, file in owned.Files do
        table.insert(files, reportFile(file))
    end
    return reportFiles(files)
end

-- Serial reporting keeps raw entries for one physical file at a time. Public transport
-- snapshots remain independently owned, but need not be materialized for a local report.
function Coverage.collect(roots: any): CoverageReport?
    const hasApi = type(debug.iscoverageenabled) == "function"
    if not hasApi or not debug.iscoverageenabled() then
        return nil
    end

    const files: { FileCoverage } = {}
    local validationProblem: any = nil
    for path, group in pairs(groupRoots(roots)) do
        const entries, loaded = gatherEntries(group.Scripts, path)
        const file = { Entries = entries, Loaded = loaded, Name = group.Name, Path = path }
        if validationProblem == nil then
            const ok, problem = pcall(validateSnapshot, { Files = { file }, Version = 1 })
            if ok then
                table.insert(files, reportFile(file))
            else
                validationProblem = problem
            end
        end
    end
    -- Capture gathers every file before validating its snapshot. A later gathering
    -- failure must still take precedence over an earlier invalid file's raw schema.
    if validationProblem ~= nil then
        error(validationProblem, 0)
    end
    table.sort(files, function(first, second)
        return first.Path < second.Path
    end)
    return reportFiles(files)
end

--[[
    Decides whether a coverage report satisfies a threshold. A threshold of 0 gates
    nothing, so it always passes. A positive threshold with no report, or a report with
    no executable lines, is "Unmeasured" instead of a pass or a failure, because there
    is nothing to compare the threshold against.

    @param report - The coverage report, or nil if none was collected
    @param threshold - The minimum total percentage, from 0 to 100
    @return The gate result
]]
function Coverage.checkGate(report: CoverageReport?, threshold: number): GateResult
    assert(report == nil or type(report) == "table", "report must be a table or nil")
    assert(type(threshold) == "number", "threshold must be a number")

    if threshold <= 0 then
        return "Passed"
    elseif report == nil or report.TotalExecutableLines == 0 then
        return "Unmeasured"
    elseif report.TotalPercentage < threshold then
        return "Failed"
    end
    return "Passed"
end

return Coverage
