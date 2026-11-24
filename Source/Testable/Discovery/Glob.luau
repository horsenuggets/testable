--[[

Glob

Matches root-relative paths against include globs and walks an injected filesystem to
find the files that match. A "*" stops at a directory boundary, a "**" segment spans any
depth, and "?" matches one character. Hidden files and directories are always skipped.

--]]

const PathUtil = require("./PathUtil")

export type FileSystem = {
    IsDir: (path: string) -> boolean,
    IsFile: (path: string) -> boolean,
    ReadDir: (path: string) -> { string },
    ReadFile: (path: string) -> string
}

const Glob = {}

const function splitSegments(path: string): { string }
    const segments = {}
    for segment in string.gmatch(string.gsub(path, "\\", "/"), "[^/]+") do
        if segment ~= "." then
            table.insert(segments, segment)
        end
    end
    return segments
end

const function hasWildcard(segment: string): boolean
    return string.find(segment, "[%*%?]") ~= nil
end

--[[
    Converts one glob segment into an anchored Luau string pattern.

    @param segment - A glob segment without any slashes
    @return The equivalent string pattern
]]
const function segmentToPattern(segment: string): string
    const escaped = string.gsub(segment, "[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
    const converted = string.gsub(string.gsub(escaped, "%*+", "[^/]*"), "%?", "[^/]")
    return `^{converted}$`
end

const function matchSegments(
    globSegments: { string },
    globIndex: number,
    pathSegments: { string },
    pathIndex: number
): boolean
    if globIndex > #globSegments then
        return pathIndex > #pathSegments
    end

    const globSegment = globSegments[globIndex]
    if globSegment == "**" then
        -- A "**" segment may consume any number of path segments, including none.
        for nextIndex = pathIndex, #pathSegments + 1 do
            if matchSegments(globSegments, globIndex + 1, pathSegments, nextIndex) then
                return true
            end
        end
        return false
    end

    if pathIndex > #pathSegments then
        return false
    end
    if string.match(pathSegments[pathIndex], segmentToPattern(globSegment)) == nil then
        return false
    end
    return matchSegments(globSegments, globIndex + 1, pathSegments, pathIndex + 1)
end

--[[
    Reports whether a root-relative path matches a glob.

    @param glob - The glob, such as "Tests/**/*.spec.luau"
    @param path - The root-relative path to test
    @return True if the whole path matches the glob
]]
function Glob.matches(glob: string, path: string): boolean
    assert(type(glob) == "string", "glob must be a string")
    assert(type(path) == "string", "path must be a string")

    return matchSegments(splitSegments(glob), 1, splitSegments(path), 1)
end

--[[
    Reports whether any segment of a path is hidden, meaning it starts with a dot.
    Segments that only navigate ("." and "..") do not count.

    @param path - The path to check
    @return True if the path is, or sits inside, a hidden file or directory
]]
function Glob.isHidden(path: string): boolean
    assert(type(path) == "string", "path must be a string")

    for _, segment in splitSegments(path) do
        if segment ~= ".." and string.sub(segment, 1, 1) == "." then
            return true
        end
    end
    return false
end

--[[
    Returns the leading directory of a glob that contains no wildcards, which is the
    deepest directory a walk has to start from. The last segment always names a file, so
    it is never part of the prefix.

    @param glob - The glob to inspect
    @return The static directory prefix, or "." when the glob starts with a wildcard
]]
function Glob.staticPrefix(glob: string): string
    assert(type(glob) == "string", "glob must be a string")

    const segments = splitSegments(glob)
    const prefix = {}
    for index = 1, #segments - 1 do
        if hasWildcard(segments[index]) then
            break
        end
        table.insert(prefix, segments[index])
    end

    return if #prefix == 0 then "." else PathUtil.normalize(table.concat(prefix, "/"))
end

--[[
    Finds every file under a root that matches at least one include glob and no exclude
    glob. Hidden files and directories are skipped, and the result is sorted so the
    order never depends on the filesystem.

    @param fileSystem - The filesystem access to walk with
    @param root - The directory that the globs are relative to
    @param include - The globs a file must match at least one of
    @param exclude - Optional globs that remove files from the result
    @return Sorted, root-relative paths of the matching files
]]
function Glob.find(fileSystem: FileSystem, root: string, include: { string }, exclude: { string }?): { string }
    assert(type(fileSystem) == "table", "fileSystem must be a table")
    assert(type(root) == "string", "root must be a string")
    assert(type(include) == "table", "include must be an array of globs")
    assert(exclude == nil or type(exclude) == "table", "exclude must be an array of globs")

    const found: { [string]: boolean } = {}
    const excluded: { string } = exclude or {}
    const visited: { [string]: boolean } = {}

    const function isIncluded(relativePath: string): boolean
        for _, glob in excluded do
            if Glob.matches(glob, relativePath) then
                return false
            end
        end
        for _, glob in include do
            if Glob.matches(glob, relativePath) then
                return true
            end
        end
        return false
    end

    const function walk(relativeDirectory: string)
        if visited[relativeDirectory] then
            return
        end
        visited[relativeDirectory] = true

        const directory = PathUtil.join(root, relativeDirectory)
        if not fileSystem.IsDir(directory) then
            return
        end

        for _, entry in fileSystem.ReadDir(directory) do
            if string.sub(entry, 1, 1) == "." then
                continue
            end

            const relativePath = if relativeDirectory == "." then entry else `{relativeDirectory}/{entry}`
            const fullPath = PathUtil.join(root, relativePath)
            if fileSystem.IsDir(fullPath) then
                walk(relativePath)
            elseif isIncluded(relativePath) then
                found[relativePath] = true
            end
        end
    end

    for _, glob in include do
        const prefix = Glob.staticPrefix(glob)
        if not Glob.isHidden(prefix) and string.sub(prefix, 1, 2) ~= ".." then
            walk(prefix)
        end
    end

    const files = {}
    for relativePath in found do
        table.insert(files, relativePath)
    end
    table.sort(files)

    return files
end

return Glob
