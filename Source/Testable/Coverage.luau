--[[

Coverage

Collects code coverage data from instrumented Luau files using
debug.getcoverage. Accepts a script instance pointing to a source
directory and recursively discovers all modules, passing each to
debug.getcoverage for full-file coverage including local functions.
Coverage is enabled by default in Lune; set LUNE_COVERAGE=0 to
disable.

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
    "%.story$",
    "%.storybook$",
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
    Recursively discovers all Luau modules under a directory using the
    filesystem API. Handles both regular .luau files and directories
    with init.luau (which represent a single module). Only available
    in Lune.

    @param dirScript - The script instance representing a directory
    @param results - Array to accumulate { Name, Script } entries
    @param seen - Set of already-processed paths for deduplication
]]
local function discoverModules(dirScript: any, results: { { Name: string, Script: any } }, seen: { [string]: boolean })
    if not IS_LUNE then
        return
    end

    local fs = require("@lune/fs")
    local dirPath = tostring(dirScript)

    local ok, entries = pcall(fs.readDir, dirPath)
    if not ok then
        return
    end

    for _, entry in entries do
        local fullPath = dirPath .. "/" .. entry
        local isDir = fs.isDir(fullPath)

        if isDir then
            local initPath = fullPath .. "/init.luau"
            if fs.isFile(initPath) then
                -- Directory with init.luau is a module
                local childScript = dirScript[entry]
                local scriptPath = tostring(childScript)
                if not seen[scriptPath] and not isExcluded(entry) then
                    seen[scriptPath] = true
                    table.insert(results, {
                        Name = entry,
                        Script = childScript,
                    })
                end
            end
            -- Recurse into subdirectory regardless (may contain
            -- more modules alongside or inside the init module)
            discoverModules(dirScript[entry], results, seen)
        elseif entry:match("%.luau$") or entry:match("%.lua$") then
            local baseName = entry:gsub("%.luau$", ""):gsub("%.lua$", "")
            -- Skip init files (handled as directory modules above)
            if baseName == "init" then
                continue
            end
            if not isExcluded(baseName) then
                local childScript = dirScript[baseName]
                local scriptPath = tostring(childScript)
                if not seen[scriptPath] then
                    seen[scriptPath] = true
                    table.insert(results, {
                        Name = baseName,
                        Script = childScript,
                    })
                end
            end
        end
    end
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
    Resolves a CoverageRoots script instance into a flat list of
    modules. CoverageRoots is a single script instance pointing to a
    source directory (e.g., script.Parent.Source). All .luau modules
    under the directory are discovered recursively.

    @param root - Script instance pointing to the source directory
    @return scripts - Array of { Name, Script } entries
]]
function Coverage.resolveRoots(root: any): { { Name: string, Script: any } }
    local results: { { Name: string, Script: any } } = {}
    local seen: { [string]: boolean } = {}
    local rootPath = tostring(root)

    if not IS_LUNE then
        return results
    end

    local fs = require("@lune/fs")

    if fs.isDir(rootPath) then
        -- Check if the root itself is a module (has init.luau)
        local initPath = rootPath .. "/init.luau"
        if fs.isFile(initPath) then
            if not isExcluded(getDisplayName(root)) then
                seen[rootPath] = true
                table.insert(results, {
                    Name = getDisplayName(root),
                    Script = root,
                })
            end
        end

        -- Discover child modules
        discoverModules(root, results, seen)
    elseif fs.isFile(rootPath) or fs.isFile(rootPath .. ".luau") or fs.isFile(rootPath .. ".lua") then
        -- Individual file
        if not isExcluded(getDisplayName(root)) then
            seen[rootPath] = true
            table.insert(results, {
                Name = getDisplayName(root),
                Script = root,
            })
        end
    end

    return results
end

--[[
    Collects coverage data for all resolved modules. Returns nil when
    coverage is not enabled (LUNE_COVERAGE=0).

    @param root - CoverageRoots script instance from config
    @return report - The coverage report, or nil if coverage is disabled
]]
function Coverage.collect(root: any): CoverageReport?
    local hasApi = type(debug.iscoverageenabled) == "function"
    if not hasApi or not debug.iscoverageenabled() then
        return nil
    end

    local scripts = Coverage.resolveRoots(root)
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
