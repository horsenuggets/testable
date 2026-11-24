--[[

Loader

Requires a spec file by its absolute path. Lune resolves a dynamic require relative to
the file that calls it, not the working directory, and it rejects absolute paths. The
target is therefore rewritten as a path relative to this module before it is required.

Lune applies that relative path to the name this module was loaded under, one segment at a
time, without consulting the filesystem. When the test script is started through a
symlinked absolute path, that name runs through the symlink, while spec paths come from
the working directory, which the operating system always reports with symlinks resolved.
A relative path between the two would then point at the wrong place, or load the spec
under a second name so that it requires its own copy of Testable. The target is therefore
translated into the names this module was loaded under first.

--]]

const PathUtil = require("./PathUtil")
const process = require("@lune/process")

-- A directory and the same directory with every symlink resolved.
export type Mapping = {
    Logical: string,
    Physical: string
}

const WORKING_DIRECTORY_SCRIPT = 'require("@lune/stdio").write(require("@lune/process").cwd)'

const Loader = {}

local cachedMapping: Mapping? = nil
local hasCachedMapping = false

--[[
    Resolves the symlinks in a directory path. Lune has no call for this, but a process
    started in a directory is told its resolved path by the operating system, so a child
    process is asked to report where it runs.

    @param directory - The absolute directory to resolve
    @return The directory with every symlink resolved, or nil if it could not be resolved
]]
const function resolveSymlinks(directory: string): string?
    const ok, result = pcall(process.exec, "lune", { "run", "-" }, {
        cwd = directory,
        stdio = { stdin = WORKING_DIRECTORY_SCRIPT }
    })
    if not ok or not result.ok or result.stdout == "" then
        return nil
    end

    return PathUtil.normalize(result.stdout)
end

--[[
    Finds the highest directory above a module whose name differs from its resolved
    path, which is where a symlink was followed to reach the module. Returns nil when the
    module directory contains no symlink.

    Two directories with the same trailing segments are only candidates, since a symlink
    may point at a directory with its own name, so every candidate is resolved before it
    is trusted.

    @param moduleDirectory - The absolute directory the module was loaded from
    @param resolve - Resolves the symlinks in a directory, or returns nil if it can't
    @return The symlinked directory and what it resolves to, or nil
]]
function Loader.findMapping(moduleDirectory: string, resolve: (directory: string) -> string?): Mapping?
    assert(type(moduleDirectory) == "string", "moduleDirectory must be a string")
    assert(type(resolve) == "function", "resolve must be a function")

    const logical = PathUtil.normalize(moduleDirectory)
    const physical = resolve(logical)
    if physical == nil or physical == logical then
        return nil
    end

    -- Walks up both paths for as long as their last segments agree, collecting each pair
    -- of ancestors that might be the same directory.
    const candidates: { Mapping } = { { Logical = logical, Physical = physical } }
    while true do
        const last = candidates[#candidates]
        const logicalParent = PathUtil.dirname(last.Logical)
        const physicalParent = PathUtil.dirname(last.Physical)
        if
            PathUtil.basename(last.Logical) ~= PathUtil.basename(last.Physical)
            or logicalParent == last.Logical
            or physicalParent == last.Physical
        then
            break
        end
        table.insert(candidates, { Logical = logicalParent, Physical = physicalParent })
    end

    -- The module directory itself is known to match, so the search always ends there.
    for index = #candidates, 2, -1 do
        const candidate = candidates[index]
        if resolve(candidate.Logical) == candidate.Physical then
            return candidate
        end
    end
    return candidates[1]
end

--[[
    Rewrites a file path so that it runs through the same symlink the module was loaded
    through. A file outside the symlinked directory is returned unchanged.

    @param mapping - The symlinked directory and what it resolves to, if there is one
    @param file - The absolute path of the file
    @return The normalized path to load the file under
]]
function Loader.translate(mapping: Mapping?, file: string): string
    assert(mapping == nil or type(mapping) == "table", "mapping must be a table or nil")
    assert(type(file) == "string", "file must be a string")

    const normalized = PathUtil.normalize(file)
    if mapping == nil then
        return normalized
    end

    const relativePath = PathUtil.relative(mapping.Physical, normalized)
    if relativePath == nil or relativePath == ".." or string.sub(relativePath, 1, 3) == "../" then
        return normalized
    end
    return PathUtil.join(mapping.Logical, relativePath)
end

--[[
    Turns the chunk name that the runtime reports for a module into the directory that
    contains the module.

    @param chunkName - The source name reported by debug.info
    @param workingDirectory - The working directory, used when the name is relative
    @return The absolute directory of the module
]]
function Loader.moduleDirectory(chunkName: string, workingDirectory: string): string
    assert(type(chunkName) == "string", "chunkName must be a string")
    assert(type(workingDirectory) == "string", "workingDirectory must be a string")

    local source = string.match(chunkName, '^%[string "(.*)"%]$') or chunkName
    source = string.gsub(source, "^[@=]", "")

    return PathUtil.dirname(PathUtil.join(workingDirectory, source))
end

--[[
    Computes the path to pass to require so that a module in the given directory loads
    the target file.

    @param moduleDirectory - The absolute directory of the module calling require
    @param file - The absolute path of the file to load
    @return The require path, starting with "./" or "../"
]]
function Loader.requirePath(moduleDirectory: string, file: string): string
    assert(type(moduleDirectory) == "string", "moduleDirectory must be a string")
    assert(type(file) == "string", "file must be a string")

    local target = PathUtil.stripLuauExtension(PathUtil.normalize(file))
    if PathUtil.basename(target) == "init" then
        -- An "init.luau" file is required through the directory it stands in for.
        target = PathUtil.dirname(target)
    end

    const relativePath = PathUtil.relative(moduleDirectory, target)
    if relativePath == nil then
        error(`"{file}" can't be required because it is on a different drive than Testable.`, 0)
    end
    if relativePath == "." then
        error(`"{file}" can't be required because it is the directory that contains Testable.`, 0)
    end

    return if string.sub(relativePath, 1, 2) == ".." then relativePath else `./{relativePath}`
end

--[[
    Requires the file at an absolute path and returns what it returns.

    @param file - The absolute path of the Luau file to load
    @return The value the module returns
]]
function Loader.load(file: string): any
    assert(type(file) == "string", "file must be a string")

    const moduleDirectory = Loader.moduleDirectory(debug.info(1, "s"), process.cwd)
    if not hasCachedMapping then
        -- The module directory can't change while the process lives, so one lookup
        -- serves every spec. Its name alone can't tell whether a symlink was followed,
        -- even when it sits inside the working directory (e.g., a symlink in the
        -- checkout that points back at the checkout), so it is always resolved.
        cachedMapping = Loader.findMapping(moduleDirectory, resolveSymlinks)
        hasCachedMapping = true
    end
    const requirePath = Loader.requirePath(moduleDirectory, Loader.translate(cachedMapping, file))

    return (require :: any)(requirePath)
end

return Loader
