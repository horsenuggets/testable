--[[

Coverage

Collects code coverage data from instrumented Luau functions using
debug.getcoverage. Recursively discovers modules from CoverageRoots,
which can be script instances (directories) or require results (module
tables). Coverage is enabled by default in Lune; set LUNE_COVERAGE=0
to disable.

--]]

local IS_ROBLOX = game ~= nil

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
    Checks if a value is a script Instance (Roblox or Lune filesystem).

    @param value - The value to check
    @return True if the value is a script-like Instance
]]
local function isInstance(value: any): boolean
    if IS_ROBLOX then
        return typeof(value) == "Instance"
    end
    return typeof(value) == "userdata"
        and pcall(function()
            local _ = value.Name
            local _ = value.Parent
        end)
end

--[[
    Gets the name of a module without the .luau extension.

    @param instance - The script instance
    @return The cleaned module name
]]
local function getModuleName(instance: any): string
    local name = instance.Name
    return name:gsub("%.luau$", "")
end

--[[
    Recursively discovers all requirable modules from a script Instance
    root. Filters out excluded suffixes and caches by identity to avoid
    duplicates.

    @param root - The script instance to search from
    @param results - Array to accumulate { Name, Module } entries
    @param seen - Set of already-processed instances for deduplication
]]
local function discoverFromInstance(
    root: any,
    results: { { Name: string, Module: { [string]: any } } },
    seen: { [any]: boolean }
)
    if seen[root] then
        return
    end
    seen[root] = true

    local children
    if IS_ROBLOX then
        children = root:GetDescendants()
    else
        local ok, result = pcall(function()
            return root:GetChildren()
        end)
        if not ok then
            return
        end
        children = result

        -- Recursively get descendants by walking children
        local allDescendants = {}
        local function walkChildren(parent: any)
            local childOk, childResult = pcall(function()
                return parent:GetChildren()
            end)
            if not childOk then
                return
            end
            for _, child in childResult do
                table.insert(allDescendants, child)
                walkChildren(child)
            end
        end
        walkChildren(root)
        children = allDescendants
    end

    for _, child in children do
        if seen[child] then
            continue
        end
        seen[child] = true

        local isModule = if IS_ROBLOX then child:IsA("ModuleScript") else child.Name:match("%.luau$") ~= nil

        if not isModule then
            continue
        end

        local name = getModuleName(child)
        if isExcluded(name) then
            continue
        end

        local ok, result = pcall(require, child)
        if ok and type(result) == "table" then
            table.insert(results, {
                Name = name,
                Module = result,
            })
        end
    end
end

--[[
    Collects coverage data for a single function.

    @param fn - The function to collect coverage for
    @return hitLines - Number of lines that were executed
    @return executableLines - Number of executable lines
]]
local function collectFunctionCoverage(fn: (...any) -> ...any): (number, number)
    local coverage = debug.getcoverage(fn)
    local totalExecutable = 0
    local totalHit = 0

    for _, entry in coverage do
        for _, hitCount in entry.Hits do
            if hitCount >= 0 then
                totalExecutable += 1
                if hitCount > 0 then
                    totalHit += 1
                end
            end
        end
    end

    return totalHit, totalExecutable
end

--[[
    Extracts all functions from a module table, sorted alphabetically.

    @param mod - The module table to extract functions from
    @return functions - Array of { name, fn } pairs
]]
local function getFunctionsFromModule(mod: { [string]: any }): { { name: string, fn: (...any) -> ...any } }
    local result = {}

    for name, value in mod do
        if type(value) == "function" then
            table.insert(result, { name = name, fn = value })
        end
    end

    table.sort(result, function(a, b)
        return a.name < b.name
    end)

    return result
end

--[[
    Resolves CoverageRoots into a flat list of { Name, Module } entries.
    CoverageRoots uses dictionary syntax: { Name = root, ... } where each
    root is either a script instance (recursively discovered) or a require
    result (module table used directly).

    @param roots - Dictionary of { name = root } entries
    @return modules - Array of { Name, Module } entries
]]
function Coverage.resolveRoots(roots: { [string]: any }): { { Name: string, Module: { [string]: any } } }
    local results = {}
    local seen: { [any]: boolean } = {}

    -- Sort keys alphabetically for deterministic order
    local keys = {}
    for key in roots do
        table.insert(keys, key)
    end
    table.sort(keys)

    for _, name in keys do
        local root = roots[name]

        if isInstance(root) then
            discoverFromInstance(root, results, seen)
        elseif type(root) == "table" then
            if not seen[root] then
                seen[root] = true
                table.insert(results, {
                    Name = name,
                    Module = root,
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

    local modules = Coverage.resolveRoots(roots)
    local files: { FileCoverage } = {}
    local grandTotalHit = 0
    local grandTotalExecutable = 0

    for _, entry in modules do
        local funcs = getFunctionsFromModule(entry.Module)
        local fileFunctions: { FunctionCoverage } = {}
        local fileHit = 0
        local fileExecutable = 0

        for _, funcInfo in funcs do
            local hit, executable = collectFunctionCoverage(funcInfo.fn)
            fileHit += hit
            fileExecutable += executable

            local pct = if executable > 0 then math.floor((hit / executable) * 100) else 0

            table.insert(fileFunctions, {
                Name = funcInfo.name,
                ExecutableLines = executable,
                HitLines = hit,
                Percentage = pct,
            })
        end

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
