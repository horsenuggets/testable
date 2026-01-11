--[[

TestBootstrap

Provides an interface to quickly run and report tests from a given object.

--]]

local IS_ROBLOX = game ~= nil
local IS_LUNE = pcall(function()
    require("@lune/fs")
end)

local TestPlanner = require("./TestPlanner")
local TestRunner = require("./TestRunner")
local TextReporter = require("./Reporters/TextReporter")

local tick = if IS_LUNE then os.clock else tick

local TestBootstrap = {}

--[[
    Removes the ".spec" suffix from a module name.

    @param name - The module name to process
    @return The name without the ".spec" suffix
]]
local function stripSpecSuffix(name: string): string
    return (name:gsub("%.spec$", ""))
end

--[[
    Checks if a script is a test specification module.

    @param aScript - The script instance to check
    @return True if the script is a ModuleScript with a ".spec" suffix
]]
local function isSpecScript(aScript: any): boolean
    return aScript:IsA("ModuleScript") and aScript.Name:match("%.spec$")
end

--[[
    Constructs the path from a module to its root.

    @param module - The module to get the path for
    @param root - The root instance to stop at (defaults to game)
    @return Array of path elements from root to module
]]
local function getPath(module: any, root: any?): { string }
    root = root or game

    local path = {}
    local last = module

    if last.Name == "init.spec" then
        -- Use the directory's node for init.spec files.
        last = last.Parent
    end

    while last ~= nil and last ~= root do
        table.insert(path, stripSpecSuffix(last.Name))
        last = last.Parent
    end
    table.insert(path, stripSpecSuffix(root.Name))

    return path
end

--[[
    Converts a table path to a space-separated string representation.

    @param tablePath - Array of path elements
    @return Space-separated string of path elements in reverse order
]]
local function toStringPath(tablePath: { string }): string
    local stringPath = ""
    local first = true
    for _, element in ipairs(tablePath) do
        if first then
            stringPath = element
            first = false
        else
            stringPath = element .. " " .. stringPath
        end
    end
    return stringPath
end

--[[
    Internal recursive implementation for finding test modules.

    @param root - The root instance to search from
    @param modules - Array to accumulate found modules
    @param current - Current instance being checked (defaults to root)
]]
local function getModulesImplRoblox(root: any, modules: { any }?, current: any?): ()
    modules = modules or {}
    current = current or root

    if isSpecScript(current) then
        local method = require(current)
        local path = getPath(current, root)
        local pathString = toStringPath(path)

        table.insert(modules, {
            method = method,
            path = path,
            pathStringForSorting = pathString:lower(),
        })
    end
end

--[[
    Find all the ModuleScripts in this tree that are tests.

    @param root - The root instance to search from (or a module function for Lune)
    @return Array of module descriptors with method, path, and pathStringForSorting fields
]]
function TestBootstrap:getModules(root: Instance | { Name: string, Func: () -> () }): { any }
    local modules = {}

    if IS_ROBLOX then
        assert(typeof(root) == "Instance", "Expected root to be an Instance.")

        getModulesImplRoblox(root, modules)

        for _, child in ipairs(root:GetDescendants()) do
            getModulesImplRoblox(root, modules, child)
        end
    elseif IS_LUNE then
        assert(
            typeof(root) == "table" and typeof(root.Name) == "string" and typeof(root.Func) == "function",
            "Expected root to be a module descriptor table."
        )

        table.insert(modules, {
            method = root.Func,
            path = { root.Name },
            pathStringForSorting = root.Name:lower(),
        })
    end

    return modules
end

--[[
    Gathers test modules from multiple root locations.

    @param roots - Array of root instances to search
    @return Combined array of all module descriptors found
]]
function TestBootstrap:getModulesFromMultipleRoots(roots: { any }): { any }
    local modules = {}

    for _, root in ipairs(roots) do
        local newModules = self:getModules(root)

        for _, newModule in ipairs(newModules) do
            table.insert(modules, newModule)
        end
    end

    return modules
end

--[[
    Runs all tests and reports the results using the given test reporter.

    If no reporter is specified, a reasonable default is provided.

    This function demonstrates the expected workflow with this testing system:
    1. Locate test modules
    2. Generate test plan
    3. Run test plan
    4. Report test results

    This means we could hypothetically present a GUI to the developer that shows
    the test plan before we execute it, allowing them to toggle specific tests
    before they're run, but after they've been identified!

    @param roots - Array of root instances or module descriptors containing test modules
    @param reporter - Optional reporter module with a report function (defaults to TextReporter)
    @param otherOptions - Optional table of options: showTimingInfo, testNamePattern, extraEnvironment
    @return TestResults object and boolean indicating if all tests passed
]]
function TestBootstrap:run(roots: { any }, reporter: any?, otherOptions: { [string]: any }?): (any, boolean)
    reporter = reporter or TextReporter

    otherOptions = otherOptions or {}
    local showTimingInfo = otherOptions["showTimingInfo"] or false
    local testNamePattern = otherOptions["testNamePattern"]
    local extraEnvironment = otherOptions["extraEnvironment"] or {}

    if type(roots) ~= "table" then
        error(("Bad argument #1 to TestBootstrap:run. Expected table, got %s"):format(typeof(roots)), 2)
    end

    local startTime = tick()
    local modules = self:getModulesFromMultipleRoots(roots)
    local afterModules = tick()

    local plan = TestPlanner.createPlan(modules, testNamePattern, extraEnvironment)
    local afterPlan = tick()

    local results = TestRunner.runPlan(plan)
    local afterRun = tick()

    reporter.report(results)
    local afterReport = tick()

    if showTimingInfo then
        local timing = {
            ("Took %f seconds to locate test modules"):format(afterModules - startTime),
            ("Took %f seconds to create test plan"):format(afterPlan - afterModules),
            ("Took %f seconds to run tests"):format(afterRun - afterPlan),
            ("Took %f seconds to report tests"):format(afterReport - afterRun),
        }

        print(table.concat(timing, "\n"))
    end

    return results, results.failureCount == 0
end

return TestBootstrap
