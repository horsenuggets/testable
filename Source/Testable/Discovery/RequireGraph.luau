--[[

RequireGraph

Builds a graph of string requires by scanning source files through an injected
filesystem, and inverts it to answer which specs transitively depend on a set of files.
Paths are resolved the way the Luau runtime resolves them, covering "./" and "../"
paths, "@self", "init.luau" directories, and ".luaurc" aliases.

--]]

const Glob = require("./Glob")
const PathUtil = require("./PathUtil")
const RequireParser = require("./RequireParser")

export type FileSystem = Glob.FileSystem
export type Graph = { [string]: { string } }
type AliasCache = { [string]: { [string]: string } | false }

const CONFIG_FILE_NAME = ".luaurc"
const INIT_NAMES = { ["init.lua"] = true, ["init.luau"] = true }
const MODULE_SUFFIXES = { ".luau", ".lua", "/init.luau", "/init.lua" }

const RequireGraph = {}

--[[
    Extracts the alias table from the text of a ".luaurc" file. Alias names are
    lowercased, since Luau matches them without regard to case.

    @param source - The text of the ".luaurc" file
    @return A map of lowercase alias names to their paths, exactly as written
]]
function RequireGraph.parseAliases(source: string): { [string]: string }
    assert(type(source) == "string", "source must be a string")

    const aliases = {}
    const block = string.match(source, '"aliases"%s*:%s*(%b{})')
    if block ~= nil then
        for name, path in string.gmatch(block, '"([^"]+)"%s*:%s*"([^"]*)"') do
            aliases[string.lower(name)] = path
        end
    end

    return aliases
end

--[[
    Looks an alias up in the ".luaurc" files of a directory and each of its ancestors,
    with the nearest file winning.

    @param fileSystem - The filesystem access to read with
    @param directory - The directory to start searching from
    @param alias - The lowercase alias name
    @param cache - Parsed alias tables by directory, shared across lookups
    @return The directory or file the alias points at, or nil if it can't be followed
]]
const function findAlias(fileSystem: FileSystem, directory: string, alias: string, cache: AliasCache): string?
    local current = directory

    while true do
        local aliases = cache[current]
        if aliases == nil then
            const configPath = PathUtil.join(current, CONFIG_FILE_NAME)
            aliases = if fileSystem.IsFile(configPath)
                then RequireGraph.parseAliases(fileSystem.ReadFile(configPath))
                else false
            cache[current] = aliases
        end

        if aliases then
            const target = aliases[alias]
            if target ~= nil then
                -- A path under the home directory can't be expanded without knowing the
                -- environment, and never points into the project anyway.
                if string.sub(target, 1, 1) == "~" then
                    return nil
                end
                return PathUtil.join(current, target)
            end
        end

        const parent = PathUtil.dirname(current)
        if parent == current or string.sub(PathUtil.basename(parent), 1, 2) == ".." then
            return nil
        end
        current = parent
    end
end

--[[
    Resolves a required path to the file it loads.

    @param fileSystem - The filesystem access to probe with
    @param fromFile - The file that contains the require
    @param requirePath - The required path, exactly as written
    @param cache - Optional parsed alias tables to share across calls
    @return resolved - The file the require loads, or nil if there is none
    @return candidates - Every file the require could load, in order of preference. This
        is empty for paths that never name a file, such as runtime built-ins.
]]
function RequireGraph.resolve(
    fileSystem: FileSystem,
    fromFile: string,
    requirePath: string,
    cache: AliasCache?
): (string?, { string })
    assert(type(fileSystem) == "table", "fileSystem must be a table")
    assert(type(fromFile) == "string", "fromFile must be a string")
    assert(type(requirePath) == "string", "requirePath must be a string")

    const file = PathUtil.normalize(fromFile)
    const directory = PathUtil.dirname(file)
    const isInit = INIT_NAMES[PathUtil.basename(file)] == true
    const path = string.gsub(requirePath, "\\", "/")

    local target: string? = nil
    if string.sub(path, 1, 2) == "./" or string.sub(path, 1, 3) == "../" then
        -- An "init.luau" file stands in for its directory, so its relative requires
        -- start from where that directory lives.
        target = PathUtil.join(if isInit then PathUtil.dirname(directory) else directory, path)
    elseif string.sub(path, 1, 1) == "@" then
        const alias = string.lower(string.match(path, "^@([^/]*)") :: string)
        const rest = string.sub(path, #alias + 3)

        local base: string? = nil
        if alias == "self" then
            base = if isInit then directory else nil
        elseif alias ~= "lune" then
            base = findAlias(fileSystem, directory, alias, cache or {})
        end
        if base ~= nil then
            target = PathUtil.join(base, rest)
        end
    end

    if target == nil then
        return nil, {}
    end

    const candidates = {}
    for _, suffix in MODULE_SUFFIXES do
        table.insert(candidates, `{target}{suffix}`)
    end
    for _, candidate in candidates do
        if fileSystem.IsFile(candidate) then
            return candidate, candidates
        end
    end

    return nil, candidates
end

--[[
    Builds the require graph reachable from a set of entry files. Each file maps to the
    sorted files its requires could load, which is the file each require resolves to and
    every other candidate for it. Creating or deleting a candidate changes what the
    require loads, so it has to count as a change to the requiring file. Only the files
    that requires actually resolve to are scanned further.

    @param fileSystem - The filesystem access to read with
    @param entryFiles - The files to start from, usually the specs
    @return The graph, keyed by normalized file path
]]
function RequireGraph.build(fileSystem: FileSystem, entryFiles: { string }): Graph
    assert(type(fileSystem) == "table", "fileSystem must be a table")
    assert(type(entryFiles) == "table", "entryFiles must be an array of paths")

    const graph: Graph = {}
    const cache: AliasCache = {}
    const queue = {}
    for _, entryFile in entryFiles do
        table.insert(queue, PathUtil.normalize(entryFile))
    end

    local index = 1
    while index <= #queue do
        const file = queue[index]
        index += 1
        if graph[file] ~= nil then
            continue
        end

        const dependencies: { string } = {}
        const seen: { [string]: boolean } = {}
        graph[file] = dependencies
        if not fileSystem.IsFile(file) then
            continue
        end

        for _, requirePath in RequireParser.parse(fileSystem.ReadFile(file)) do
            const resolved, candidates = RequireGraph.resolve(fileSystem, file, requirePath, cache)
            for _, dependency in candidates do
                if not seen[dependency] then
                    seen[dependency] = true
                    table.insert(dependencies, dependency)
                end
            end
            if resolved ~= nil then
                table.insert(queue, resolved)
            end
        end
        table.sort(dependencies)
    end

    return graph
end

--[[
    Inverts a require graph, mapping each file to the sorted files that require it
    directly.

    @param graph - The graph to invert
    @return A graph of direct dependents
]]
function RequireGraph.invert(graph: Graph): Graph
    assert(type(graph) == "table", "graph must be a table")

    const dependents: Graph = {}
    for file, dependencies in graph do
        for _, dependency in dependencies do
            dependents[dependency] = dependents[dependency] or {}
            table.insert(dependents[dependency], file)
        end
    end
    for _, files in dependents do
        table.sort(files)
    end

    return dependents
end

--[[
    Returns every file that appears in a graph, either as a file that was scanned or as
    something a scanned file requires.

    @param graph - The graph to list
    @return Sorted file paths
]]
function RequireGraph.files(graph: Graph): { string }
    assert(type(graph) == "table", "graph must be a table")

    const seen: { [string]: boolean } = {}
    for file, dependencies in graph do
        seen[file] = true
        for _, dependency in dependencies do
            seen[dependency] = true
        end
    end

    const files = {}
    for file in seen do
        table.insert(files, file)
    end
    table.sort(files)

    return files
end

--[[
    Finds the specs that are affected by a set of changed files, meaning the spec itself
    changed or it transitively requires something that did. A changed ".luaurc" affects
    every spec, since it can redirect any aliased require.

    @param graph - The require graph that was built from the specs
    @param specFiles - The spec files to choose from
    @param changedFiles - The files that changed
    @return The affected specs, in the order they were given
]]
function RequireGraph.findAffected(graph: Graph, specFiles: { string }, changedFiles: { string }): { string }
    assert(type(graph) == "table", "graph must be a table")
    assert(type(specFiles) == "table", "specFiles must be an array of paths")
    assert(type(changedFiles) == "table", "changedFiles must be an array of paths")

    const dependents = RequireGraph.invert(graph)
    const reached: { [string]: boolean } = {}
    const queue = {}
    local configChanged = false

    for _, changedFile in changedFiles do
        const file = PathUtil.normalize(changedFile)
        if PathUtil.basename(file) == CONFIG_FILE_NAME then
            configChanged = true
        end
        if not reached[file] then
            reached[file] = true
            table.insert(queue, file)
        end
    end

    local index = 1
    while index <= #queue do
        for _, dependent in dependents[queue[index]] or {} do
            if not reached[dependent] then
                reached[dependent] = true
                table.insert(queue, dependent)
            end
        end
        index += 1
    end

    const affected = {}
    for _, specFile in specFiles do
        if configChanged or reached[PathUtil.normalize(specFile)] then
            table.insert(affected, specFile)
        end
    end

    return affected
end

return RequireGraph
