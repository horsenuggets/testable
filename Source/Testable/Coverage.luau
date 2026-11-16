--[[

Coverage

Collects code coverage data from instrumented Luau files using
debug.getcoverage. Accepts a script instance pointing to a source
directory and recursively discovers all modules, passing each to
debug.getcoverage for full-file coverage including local functions.
Coverage is enabled by default in Lune; set LUNE_COVERAGE=0 to
disable.

Modules that no test required have no runtime coverage data, so they are compiled
without running to count their executable lines, and every line counts as missed. A
module that fails to compile counts as zero lines.

--]]

const IS_LUNE = pcall(function()
    require("@lune/fs")
end)

const EXCLUDED_SUFFIXES = {
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
    Path: string,
    Functions: { FunctionCoverage },
    ExecutableLines: number,
    HitLines: number,
    Loaded: boolean,
    Percentage: number,
}

export type CoverageReport = {
    Files: { FileCoverage },
    TotalExecutableLines: number,
    TotalHitLines: number,
    TotalPercentage: number,
}

const Coverage = {}

--[[
    Checks if a module name should be excluded based on its suffix.

    @param name - The module name to check
    @return True if the name matches an excluded suffix
]]
const function isExcluded(name: string): boolean
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
const function getDisplayName(scriptInstance: any): string
    const name = scriptInstance.Name
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
const function discoverModules(dirScript: any, results: { { Name: string, Script: any } }, seen: { [string]: boolean })
    if not IS_LUNE then
        return
    end

    const fs = require("@lune/fs")
    const dirPath = tostring(dirScript)

    const ok, entries = pcall(fs.readDir, dirPath)
    if not ok then
        return
    end

    for _, entry in entries do
        const fullPath = dirPath .. "/" .. entry
        const isDir = fs.isDir(fullPath)

        if isDir then
            const initPath = fullPath .. "/init.luau"
            if fs.isFile(initPath) then
                -- Directory with init.luau is a module
                const childScript = dirScript[entry]
                const scriptPath = tostring(childScript)
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
            const baseName = entry:gsub("%.luau$", ""):gsub("%.lua$", "")
            -- Skip init files (handled as directory modules above)
            if baseName == "init" then
                continue
            end
            if not isExcluded(baseName) then
                const childScript = dirScript[baseName]
                const scriptPath = tostring(childScript)
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
    Returns the share of hit lines as a percentage floored to two decimals, so small
    totals like 0.09% don't round away to zero. Zero executable lines yields 0.
]]
function Coverage.percentage(hit: number, executable: number): number
    assert(type(hit) == "number")
    assert(type(executable) == "number")
    return if executable > 0 then math.floor(hit / executable * 10000) / 100 else 0
end

--[[
    Compiles a module that never ran and returns its coverage entries without executing
    it. Returns nil when the file can't be read or compiled.

    @param path - The filesystem path of the module source
    @return entries - The debug.getcoverage entries, or nil
]]
const function compileCoverageEntries(path: string): { any }?
    const fs = require("@lune/fs")
    const luau = require("@lune/luau")
    const ok, entries = pcall(function()
        const bytecode = luau.compile(fs.readFile(path), { coverageLevel = 1 })
        return debug.getcoverage(luau.load(bytecode, { debugName = path }))
    end)
    return if ok and type(entries) == "table" then entries else nil
end

--[[
    Collects coverage data for a single file by passing its script
    instance to debug.getcoverage. Returns per-function coverage
    entries for ALL functions in the file, including local ones.
    Modules that were never required are compiled instead, with
    every executable line counted as missed.

    @param scriptInstance - The script instance to collect coverage for
    @param path - The filesystem path of the module source
    @return fileFunctions - Array of FunctionCoverage entries
    @return fileHit - Total hit lines across all functions
    @return fileExecutable - Total executable lines across all functions
    @return loaded - Whether the module ran during the test session
]]
const function collectFileCoverage(scriptInstance: any, path: string): ({ FunctionCoverage }, number, number, boolean)
    local ok, entries = pcall(debug.getcoverage, scriptInstance)
    const loaded = ok and type(entries) == "table"
    if not loaded then
        entries = compileCoverageEntries(path)
        if entries == nil then
            return {}, 0, 0, false
        end
    end

    const fileFunctions: { FunctionCoverage } = {}
    local fileHit = 0
    local fileExecutable = 0

    for _, entry in entries do
        local funcHit = 0
        local funcExecutable = 0

        for _, hitCount in entry.Hits do
            if hitCount >= 0 then
                funcExecutable += 1
                if loaded and hitCount > 0 then
                    funcHit += 1
                end
            end
        end

        fileHit += funcHit
        fileExecutable += funcExecutable

        const pct = Coverage.percentage(funcHit, funcExecutable)

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

    return fileFunctions, fileHit, fileExecutable, loaded
end

--[[
    Resolves a single script instance into discovered modules. Handles
    directories (recursively discovers .luau files), directories with
    init.luau (treated as a module), and individual file scripts.

    @param scriptInstance - Script instance to resolve
    @param results - Array to accumulate { Name, Script } entries
    @param seen - Set of already-processed paths for deduplication
]]
const function resolveScript(
    scriptInstance: any,
    name: string,
    results: { { Name: string, Script: any } },
    seen: { [string]: boolean }
)
    if not IS_LUNE then
        return
    end

    const fs = require("@lune/fs")
    const scriptPath = tostring(scriptInstance)

    if fs.isDir(scriptPath) then
        -- Check if the directory itself is a module (has init.luau)
        const initPath = scriptPath .. "/init.luau"
        if fs.isFile(initPath) then
            if not seen[scriptPath] and not isExcluded(name) then
                seen[scriptPath] = true
                table.insert(results, {
                    Name = name,
                    Script = scriptInstance,
                })
            end
        end

        -- Discover child modules
        discoverModules(scriptInstance, results, seen)
    elseif fs.isFile(scriptPath) or fs.isFile(scriptPath .. ".luau") or fs.isFile(scriptPath .. ".lua") then
        -- Individual file
        if not seen[scriptPath] and not isExcluded(name) then
            seen[scriptPath] = true
            table.insert(results, {
                Name = name,
                Script = scriptInstance,
            })
        end
    end
end

--[[
    Resolves CoverageRoots into a flat list of modules. Accepts either
    a single script instance or a dictionary of script instances.

    Single script: script.Parent.Source
    Dictionary:    { Chalk = script.Parent.Source.Chalk, Utils = ... }

    @param roots - Script instance or dictionary of script instances
    @return scripts - Array of { Name, Script } entries
]]
function Coverage.resolveRoots(roots: any): { { Name: string, Script: any } }
    const results: { { Name: string, Script: any } } = {}
    const seen: { [string]: boolean } = {}

    -- Detect if roots is a dictionary (table with string keys) or
    -- a single script instance (userdata with Name/Parent)
    if type(roots) == "table" then
        -- Dictionary format: { Name = scriptInstance, ... }
        const keys = {}
        for key in pairs(roots) do
            table.insert(keys, key)
        end
        table.sort(keys)

        for _, name in keys do
            resolveScript(roots[name], name, results, seen)
        end
    else
        -- Single script instance
        resolveScript(roots, getDisplayName(roots), results, seen)
    end

    return results
end

--[[
    Collects coverage data for all resolved modules. Returns nil when
    coverage is not enabled (LUNE_COVERAGE=0).

    @param roots - Script instance or dictionary of script instances
    @return report - The coverage report, or nil if coverage is disabled
]]
function Coverage.collect(roots: any): CoverageReport?
    const hasApi = type(debug.iscoverageenabled) == "function"
    if not hasApi or not debug.iscoverageenabled() then
        return nil
    end

    const fs = require("@lune/fs")
    const cwd = require("@lune/process").cwd
    const scripts = Coverage.resolveRoots(roots)
    const files: { FileCoverage } = {}
    local grandTotalHit = 0
    local grandTotalExecutable = 0

    for _, entry in scripts do
        local path = tostring(entry.Script)
        if fs.isDir(path) then
            path = `{path}/init.luau`
        elseif not fs.isFile(path) then
            path = if fs.isFile(`{path}.luau`) then `{path}.luau` else `{path}.lua`
        end

        const fileFunctions, fileHit, fileExecutable, loaded = collectFileCoverage(entry.Script, path)

        grandTotalHit += fileHit
        grandTotalExecutable += fileExecutable

        table.insert(files, {
            Name = entry.Name,
            Path = if path:sub(1, #cwd) == cwd then path:sub(#cwd + 1) else path,
            Functions = fileFunctions,
            ExecutableLines = fileExecutable,
            HitLines = fileHit,
            Loaded = loaded,
            Percentage = Coverage.percentage(fileHit, fileExecutable),
        })
    end

    return {
        Files = files,
        TotalExecutableLines = grandTotalExecutable,
        TotalHitLines = grandTotalHit,
        TotalPercentage = Coverage.percentage(grandTotalHit, grandTotalExecutable),
    }
end

return Coverage
