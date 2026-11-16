--[[

SpecNames

Derives the display name of each discovered spec file. A spec is named after its file,
and specs that would share a name are told apart by their root-relative paths instead.

--]]

const PathUtil = require("./PathUtil")

const SpecNames = {}

--[[
    Removes the Luau extension and any ".spec" suffix from a path.

    @param path - The path to strip
    @return The path without its spec suffix and extension
]]
const function stripSpecSuffix(path: string): string
    return (string.gsub(PathUtil.stripLuauExtension(path), "%.[sS]pec$", ""))
end

--[[
    Returns the short name of a spec file. An "init.spec.luau" file is named after the
    directory that contains it.

    @param file - The root-relative spec file path
    @return The short name
]]
function SpecNames.shortName(file: string): string
    assert(type(file) == "string", "file must be a string")

    const name = stripSpecSuffix(PathUtil.basename(file))
    if name == "init" then
        const directory = PathUtil.basename(PathUtil.dirname(file))
        if directory ~= "" and directory ~= "." and directory ~= ".." then
            return directory
        end
    end
    return name
end

--[[
    Assigns a unique name to each spec file. Short names are used wherever they are
    unique, and the root-relative path without its extension is used for the rest.

    @param files - The root-relative spec file paths
    @return A map of each file to its name
]]
function SpecNames.assign(files: { string }): { [string]: string }
    assert(type(files) == "table", "files must be an array of paths")

    const counts: { [string]: number } = {}
    for _, file in files do
        const name = SpecNames.shortName(file)
        counts[name] = (counts[name] or 0) + 1
    end

    const names = {}
    for _, file in files do
        const name = SpecNames.shortName(file)
        names[file] = if counts[name] == 1 then name else stripSpecSuffix(PathUtil.normalize(file))
    end

    return names
end

return SpecNames
