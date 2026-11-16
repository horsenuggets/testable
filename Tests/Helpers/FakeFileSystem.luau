--[[

FakeFileSystem

Builds an in-memory filesystem from a table of file paths and contents. Discovery tests
inject it in place of real disk access, so glob matching and require resolution are
exercised without touching disk.

--]]

const FakeFileSystem = {}

--[[
    Creates a fake filesystem. Directories are implied by the paths of the files, and
    entries are listed in reverse order to prove that callers sort their results.

    @param files - A map of forward-slash file paths to their contents
    @return An object with the IsDir, IsFile, ReadDir, and ReadFile functions that
        discovery expects
]]
function FakeFileSystem.new(files: { [string]: string })
    assert(type(files) == "table", "files must be a table")

    const directories: { [string]: { [string]: boolean } } = {}
    for path in files do
        local child = path
        while true do
            const parent = string.match(child, "^(.*)/[^/]+$") or (if string.sub(child, 1, 1) == "/" then "/" else ".")
            const name = string.match(child, "([^/]+)$") :: string
            directories[parent] = directories[parent] or {}
            directories[parent][name] = true
            if parent == "." or parent == "/" or parent == "" then
                break
            end
            child = parent
        end
    end

    return {
        IsDir = function(path: string): boolean
            return directories[path] ~= nil
        end,
        IsFile = function(path: string): boolean
            return files[path] ~= nil
        end,
        ReadDir = function(path: string): { string }
            const entries = {}
            const names: { [string]: boolean } = directories[path] or {}
            for name in names do
                table.insert(entries, name)
            end
            table.sort(entries, function(a, b)
                return a > b
            end)
            return entries
        end,
        ReadFile = function(path: string): string
            const content = files[path]
            if content == nil then
                error(`"{path}" does not exist in the fake filesystem.`)
            end
            return content
        end,
    }
end

return FakeFileSystem
