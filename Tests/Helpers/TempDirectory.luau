--[[

TempDirectory

Creates and removes uniquely named scratch directories in the system's temporary
directory. Discovery tests use them when they need real files, a real git repository, or
a directory that is certain to be outside any repository.

--]]

const fs = require("@lune/fs")
const process = require("@lune/process")

const TempDirectory = {}

local counter = 0

--[[
    Creates a new, empty scratch directory.

    @param label - A short name that makes the directory recognizable
    @return The absolute, forward-slash path of the directory
]]
function TempDirectory.create(label: string): string
    assert(type(label) == "string", "label must be a string")

    const base = process.env.RUNNER_TEMP or process.env.TMPDIR or process.env.TEMP or "/tmp"
    counter += 1

    const name = `testable_{label}_{os.time()}_{counter}_{math.random(100000, 999999)}`
    const path = `{string.gsub(string.gsub(base, "\\", "/"), "/+$", "")}/{name}`
    fs.writeDir(path)

    return path
end

--[[
    Writes a file inside a scratch directory, creating its parent directories.

    @param directory - The scratch directory
    @param relativePath - The forward-slash path of the file inside the directory
    @param content - The content to write
]]
function TempDirectory.write(directory: string, relativePath: string, content: string)
    assert(type(directory) == "string", "directory must be a string")
    assert(type(relativePath) == "string", "relativePath must be a string")
    assert(type(content) == "string", "content must be a string")

    const path = `{directory}/{relativePath}`
    const parent = string.match(path, "^(.*)/[^/]+$")
    if parent ~= nil and not fs.isDir(parent) then
        fs.writeDir(parent)
    end
    fs.writeFile(path, content)
end

--[[
    Removes a scratch directory and everything in it.

    @param directory - The scratch directory to remove
]]
function TempDirectory.remove(directory: string)
    assert(type(directory) == "string", "directory must be a string")

    if fs.isDir(directory) then
        fs.removeDir(directory)
    end
end

return TempDirectory
