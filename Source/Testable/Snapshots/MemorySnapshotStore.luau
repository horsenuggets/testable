--[[

MemorySnapshotStore

Creates snapshot stores that keep their files in a table instead of on disk. This is
useful on Roblox, where there is no filesystem, and in tests. The files are exposed so the
caller can seed them before a run and persist them however it likes afterward.

--]]

const MemorySnapshotStore = {}

export type MemorySnapshotStore = {
    Files: { [string]: string },
    read: (path: string) -> string?,
    write: (path: string, contents: string) -> ()
}

--[[
    Creates a store backed by the given table of file contents by path.

    @param files - The initial files, which the store reads and changes in place
    @return The new store
]]
function MemorySnapshotStore.new(files: { [string]: string }?): MemorySnapshotStore
    assert(files == nil or type(files) == "table", "files must be a table or nil")

    const storedFiles: { [string]: string } = files or {}

    return {
        Files = storedFiles,
        read = function(path: string): string?
            return storedFiles[path]
        end,
        write = function(path: string, contents: string)
            storedFiles[path] = contents
        end
    }
end

return MemorySnapshotStore
