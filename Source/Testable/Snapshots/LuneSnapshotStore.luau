--[[

LuneSnapshotStore

Stores snapshot files on the filesystem through Lune. This module only loads on Lune, so
SnapshotManager requires it lazily, and the package still loads on Roblox.

--]]

const fs = require("@lune/fs")

const LuneSnapshotStore = {}

--[[
    Reads a snapshot file.

    @param path - The path of the snapshot file
    @return The file contents, or nil if the file does not exist
]]
function LuneSnapshotStore.read(path: string): string?
    assert(type(path) == "string", "path must be a string")

    if not fs.isFile(path) then
        return nil
    end
    return fs.readFile(path)
end

--[[
    Writes a snapshot file, creating its directory when needed.

    @param path - The path of the snapshot file
    @param contents - The file contents
]]
function LuneSnapshotStore.write(path: string, contents: string)
    assert(type(path) == "string", "path must be a string")
    assert(type(contents) == "string", "contents must be a string")

    const directory = path:gsub("\\", "/"):match("^(.*)/[^/]*$")
    if directory ~= nil and directory ~= "" and not fs.isDir(directory) then
        fs.writeDir(directory)
    end
    fs.writeFile(path, contents)
end

return LuneSnapshotStore
