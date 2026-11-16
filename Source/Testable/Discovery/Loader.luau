--[[

Loader

Requires a spec file by its absolute path. Lune resolves a dynamic require relative to
the file that calls it, not the working directory, and it rejects absolute paths. The
target is therefore rewritten as a path relative to this module before it is required.

--]]

const PathUtil = require("./PathUtil")
const process = require("@lune/process")

const Loader = {}

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
    const requirePath = Loader.requirePath(moduleDirectory, file)

    return (require :: any)(requirePath)
end

return Loader
