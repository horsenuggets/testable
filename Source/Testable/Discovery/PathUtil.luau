--[[

PathUtil

Pure, lexical helpers for the forward-slash paths that spec discovery works with. Nothing
here touches the filesystem, so every function behaves the same on any platform.

--]]

const PathUtil = {}

--[[
    Splits a normalized path into its root ("/", "C:/", or "" for relative paths) and the
    segments that follow it.

    @param path - The path to split, using forward slashes
    @return root - The root prefix of the path
    @return segments - The segments after the root
]]
const function split(path: string): (string, { string })
    local root = ""
    local rest = path

    const drive = string.match(path, "^(%a:)/") or string.match(path, "^(%a:)$")
    if drive ~= nil then
        root = `{string.upper(drive)}/`
        rest = string.sub(path, #drive + 1)
    elseif string.sub(path, 1, 1) == "/" then
        root = "/"
    end

    -- A "." segment names the directory it is already in, so it is never a real segment.
    -- This also covers the "." that stands for an empty relative path.
    const segments = {}
    for segment in string.gmatch(rest, "[^/]+") do
        if segment ~= "." then
            table.insert(segments, segment)
        end
    end

    return root, segments
end

--[[
    Normalizes a path by converting backslashes to forward slashes, collapsing "." and
    ".." segments, and removing duplicate and trailing slashes. A relative path keeps any
    leading ".." segments, and an empty result becomes ".".

    @param path - The path to normalize
    @return The normalized path
]]
function PathUtil.normalize(path: string): string
    assert(type(path) == "string", "path must be a string")

    -- Windows reports some absolute paths with a verbatim prefix, which no other path
    -- in a run carries, so it is dropped to keep paths comparable.
    const slashed = string.gsub(string.gsub(path, "\\", "/"), "^//%?/", "")
    const root, segments = split(slashed)

    const resolved = {}
    for _, segment in segments do
        if segment == ".." then
            if #resolved > 0 and resolved[#resolved] ~= ".." then
                table.remove(resolved)
            elseif root == "" then
                table.insert(resolved, "..")
            end
        else
            table.insert(resolved, segment)
        end
    end

    const joined = table.concat(resolved, "/")
    if root ~= "" then
        return if joined == "" then root else `{root}{joined}`
    end
    return if joined == "" then "." else joined
end

--[[
    Reports whether a path is absolute, meaning it starts at a filesystem root or a
    Windows drive.

    @param path - The path to check
    @return True if the path is absolute
]]
function PathUtil.isAbsolute(path: string): boolean
    assert(type(path) == "string", "path must be a string")

    const slashed = string.gsub(path, "\\", "/")
    return string.sub(slashed, 1, 1) == "/"
        or string.match(slashed, "^%a:/") ~= nil
        or string.match(slashed, "^%a:$") ~= nil
end

--[[
    Joins a path onto a base directory and normalizes the result. An absolute path
    replaces the base entirely.

    @param base - The directory to resolve against
    @param path - The path to append
    @return The normalized, joined path
]]
function PathUtil.join(base: string, path: string): string
    assert(type(base) == "string", "base must be a string")
    assert(type(path) == "string", "path must be a string")

    if PathUtil.isAbsolute(path) then
        return PathUtil.normalize(path)
    end
    return PathUtil.normalize(`{base}/{path}`)
end

--[[
    Returns the directory that contains a path. The directory of a root is the root
    itself, and the directory of a bare name is ".".

    @param path - The path to get the directory of
    @return The normalized parent directory
]]
function PathUtil.dirname(path: string): string
    assert(type(path) == "string", "path must be a string")

    const root, segments = split(PathUtil.normalize(path))
    if #segments == 0 then
        return if root == "" then "." else root
    end

    if root == "" and segments[#segments] == ".." then
        table.insert(segments, "..")
    else
        table.remove(segments)
    end

    const joined = table.concat(segments, "/")
    if root ~= "" then
        return `{root}{joined}`
    end
    return if joined == "" then "." else joined
end

--[[
    Returns the last segment of a path.

    @param path - The path to get the name of
    @return The final segment, or an empty string for a root
]]
function PathUtil.basename(path: string): string
    assert(type(path) == "string", "path must be a string")

    const _, segments = split(PathUtil.normalize(path))
    return segments[#segments] or ""
end

--[[
    Computes the relative path that leads from one directory to another path. Both must
    be absolute, or both relative to the same place. Returns nil when no relative path
    exists, which happens when the two sit on different roots or drives.

    @param from - The directory to start from
    @param to - The path to reach
    @return The relative path, "." when both are the same, or nil if there is none
]]
function PathUtil.relative(from: string, to: string): string?
    assert(type(from) == "string", "from must be a string")
    assert(type(to) == "string", "to must be a string")

    const fromRoot, fromSegments = split(PathUtil.normalize(from))
    const toRoot, toSegments = split(PathUtil.normalize(to))
    if fromRoot ~= toRoot then
        return nil
    end

    local shared = 0
    while shared < #fromSegments and shared < #toSegments and fromSegments[shared + 1] == toSegments[shared + 1] do
        shared += 1
    end

    const parts = {}
    for index = shared + 1, #fromSegments do
        if fromSegments[index] == ".." then
            -- There is no way to name the directory that a leading ".." climbed out of.
            return nil
        end
        table.insert(parts, "..")
    end
    for index = shared + 1, #toSegments do
        table.insert(parts, toSegments[index])
    end

    return if #parts == 0 then "." else table.concat(parts, "/")
end

--[[
    Removes a trailing ".luau" or ".lua" extension from a path.

    @param path - The path to strip
    @return The path without its Luau extension
]]
function PathUtil.stripLuauExtension(path: string): string
    assert(type(path) == "string", "path must be a string")

    const stripped = string.gsub(path, "%.luau$", "")
    if stripped ~= path then
        return stripped
    end
    return (string.gsub(path, "%.lua$", ""))
end

return PathUtil
