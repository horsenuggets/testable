--[[

FileWriter

Writes reporter output to a file. This is the only reporter module that touches the
filesystem, so it only works in Lune and is required lazily, when a reporter has an output
path.

--]]

const fs = require("@lune/fs")

const FileWriter = {}

--[[
    Writes the contents to the file at the given path, replacing any existing file and
    creating the folders leading to it.
]]
function FileWriter.write(path: string, contents: string)
    assert(type(path) == "string" and path ~= "")
    assert(type(contents) == "string")
    const parent = path:gsub("\\", "/"):match("^(.+)/[^/]*$")
    if parent ~= nil and not fs.isDir(parent) then
        fs.writeDir(parent)
    end
    fs.writeFile(path, contents)
end

return FileWriter
