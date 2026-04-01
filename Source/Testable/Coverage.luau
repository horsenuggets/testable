--[[

Coverage

Collects code coverage data from instrumented Luau files using
debug.getcoverage. Accepts script instances in CoverageRoots and passes
them directly to debug.getcoverage for full-file coverage, including
local functions not visible from the module table. Coverage is enabled
by default in Lune; set LUNE_COVERAGE=0 to disable.

--]]

local IS_LUNE = pcall(function()
    require("@lune/fs")
end)

local EXCLUDED_SUFFIXES = {
    "%.legacy$",
    "%.server$",
    "%.client$",
    "%.plugin$",
    "%.spec$",
}

export type FunctionCoverage = {
    Name: string,
    ExecutableLines: number,
    HitLines: number,
    Percentage: number,
}

export type FileCoverage = {
    Name: string,
    Functions: { FunctionCoverage },
    ExecutableLines: number,
    HitLines: number,
    Percentage: number,
}

export type CoverageReport = {
    Files: { FileCoverage },
    TotalExecutableLines: number,
    TotalHitLines: number,
    TotalPercentage: number,
}

local Coverage = {}

--[[
    Checks if a module name should be excluded based on its suffix.

    @param name - The module name to check
    @return True if the name matches an excluded suffix
]]
local function isExcluded(name: string): boolean
    for _, suffix in EXCLUDED_SUFFIXES do
        if name:match(suffix) then
            return true
        end
    end
    return false
end

--[[
    Gets the display name of a script instance, stripping the .luau
    extension if present.

    @param scriptInstance - The script instance
    @return The cleaned module name
]]
local function getDisplayName(scriptInstance: any): string
    local name = scriptInstance.Name
    return name:gsub("%.luau$", ""):gsub("%.lua$", "")
end

--[[
    Discovers all Luau files under a directory using the filesystem API.
    Only available in Lune. Returns an array of child script references.

    @param dirScript - The script instance representing a directory
    @return Array of child script references
]]
local function discoverFromDirectory(dirScript: any): { any }
    if not IS_LUNE then
        return {}
    end

    local fs = require("@lune/fs")
    local results = {}
    local dirPath = tostring(dirScript)

    local function walk(currentPath: string, parentScript: any)
        local ok, entries = pcall(fs.readDir, currentPath)
        if not ok then
            return
        end

        for _, entry in entries do
            local fullPath = currentPath .. "/" .. entry
            local isDir = fs.isDir(fullPath)

            if isDir then
                -- Check for init.luau inside directory
                local initPath = fullPath .. "/init.luau"
                if fs.isFile(initPath) then
                    local childScript = parentScript[entry]
                    local name = getDisplayName(childScript)
                    if not isExcluded(name) then
                        table.insert(results, childScript)
                    end
                end
                -- Recurse into subdirectory
                walk(fullPath, parentScript[entry])
            elseif entry:match("%.luau$") or entry:match("%.lua$") then
                local baseName = entry:gsub("%.luau$", ""):gsub("%.lua$", "")
                if baseName == "init" then
                    continue
                end
                if not isExcluded(baseName) then
                    local childScript = parentScript[baseName]
                    table.insert(results, childScript)
                end
            end
        end
    end

    walk(dirPath, dirScript)
    return results
end

--[[
    Collects coverage data for a single file by passing its script
    instance to debug.getcoverage. Returns per-function coverage
    entries for ALL functions in the file, including local ones.

    @param scriptInstance - The script instance to collect coverage for
    @return fileFunctions - Array of FunctionCoverage entries
    @return fileHit - Total hit lines across all functions
    @return fileExecutable - Total executable lines across all functions
]]
local function collectFileCoverage(scriptInstance: any): ({ FunctionCoverage }, number, number)
    local ok, entries = pcall(debug.getcoverage, scriptInstance)
    if not ok or type(entries) ~= "table" then
        return {}, 0, 0
    end

    local fileFunctions: { FunctionCoverage } = {}
    local fileHit = 0
    local fileExecutable = 0

    for _, entry in entries do
        local funcHit = 0
        local funcExecutable = 0

        for _, hitCount in entry.Hits do
            if hitCount >= 0 then
                funcExecutable += 1
                if hitCount > 0 then
                    funcHit += 1
                end
            end
        end

        fileHit += funcHit
        fileExecutable += funcExecutable

        local pct = if funcExecutable > 0 then math.floor((funcHit / funcExecutable) * 100) else 0

        local funcName = entry.Function
        if funcName == "" then
            funcName = "(top-level)"
        end

        table.insert(fileFunctions, {
            Name = funcName,
            ExecutableLines = funcExecutable,
            HitLines = funcHit,
            Percentage = pct,
        })
    end

    return fileFunctions, fileHit, fileExecutable
end

--[[
    Checks if a script instance points to a directory by trying to
    read it as a directory with the filesystem API.

    @param scriptInstance - The script instance to check
    @return True if the script points to a directory
]]
local function isDirectory(scriptInstance: any): boolean
    if not IS_LUNE then
        return false
    end
    local fs = require("@lune/fs")
    local path = tostring(scriptInstance)
    return fs.isDir(path)
end

--[[
    Resolves CoverageRoots into a flat list of script instances.
    CoverageRoots uses dictionary syntax: { Name = scriptInstance, ... }
    where each root is a script instance pointing to either a file or
    a directory.

    For directory roots, recursively discovers all .luau files using the
    filesystem API. For file roots, uses the script directly.

    @param roots - Dictionary of { Name = scriptInstance } entries
    @return scripts - Array of { Name, Script } entries
]]
function Coverage.resolveRoots(roots: { [string]: any }): { { Name: string, Script: any } }
    local results: { { Name: string, Script: any } } = {}
    local seen: { [string]: boolean } = {}

    -- Sort keys alphabetically for deterministic order
    local keys = {}
    for key in pairs(roots) do
        table.insert(keys, key)
    end
    table.sort(keys)

    for _, name in keys do
        local root = roots[name]
        local rootPath = tostring(root)

        if isDirectory(root) then
            -- Directory: recursively discover all .luau files
            local scripts = discoverFromDirectory(root)
            for _, scriptInstance in scripts do
                local scriptPath = tostring(scriptInstance)
                if not seen[scriptPath] then
                    seen[scriptPath] = true
                    table.insert(results, {
                        Name = getDisplayName(scriptInstance),
                        Script = scriptInstance,
                    })
                end
            end
        else
            -- Individual file
            if not seen[rootPath] and not isExcluded(getDisplayName(root)) then
                seen[rootPath] = true
                table.insert(results, {
                    Name = getDisplayName(root),
                    Script = root,
                })
            end
        end
    end

    return results
end

--[[
    Collects coverage data for all resolved modules. Returns nil when
    coverage is not enabled (LUNE_COVERAGE=0).

    @param roots - CoverageRoots value from config
    @return report - The coverage report, or nil if coverage is disabled
]]
function Coverage.collect(roots: any): CoverageReport?
    local hasApi = type(debug.iscoverageenabled) == "function"
    if not hasApi or not debug.iscoverageenabled() then
        return nil
    end

    local scripts = Coverage.resolveRoots(roots)
    local files: { FileCoverage } = {}
    local grandTotalHit = 0
    local grandTotalExecutable = 0

    for _, entry in scripts do
        local fileFunctions, fileHit, fileExecutable = collectFileCoverage(entry.Script)

        grandTotalHit += fileHit
        grandTotalExecutable += fileExecutable

        local filePct = if fileExecutable > 0 then math.floor((fileHit / fileExecutable) * 100) else 0

        table.insert(files, {
            Name = entry.Name,
            Functions = fileFunctions,
            ExecutableLines = fileExecutable,
            HitLines = fileHit,
            Percentage = filePct,
        })
    end

    local totalPct = if grandTotalExecutable > 0 then math.floor((grandTotalHit / grandTotalExecutable) * 100) else 0

    return {
        Files = files,
        TotalExecutableLines = grandTotalExecutable,
        TotalHitLines = grandTotalHit,
        TotalPercentage = totalPct,
    }
end

return Coverage
