--[[

Config

Central configuration module for Testable. Stores all configurable options with their
default values.

--]]

const PathUtil = require("./Discovery/PathUtil")
const SuiteOrder = require("./SuiteOrder")
const TestEnum = require("./TestEnum")
const TestTimeout = require("./TestTimeout")
const ToolError = require("./ToolError")

-- How coverage report rows are ordered, by coverage percentage or by hit lines.
export type CoverageSort = "HitLines" | "Percentage"

-- A report that a run produces. "Text" is the tree printed to standard output, and the
-- others are machine-readable.
export type Reporter = "JUnit" | "Json" | "Lcov" | "Text"

export type ConfigOptions = {
    AlphabeticalSort: boolean?,
    Coverage: boolean?,
    CoverageRoots: any?,
    CoverageRows: number?,
    CoverageSort: CoverageSort?,
    CoverageThreshold: number?,
    Filter: string?,
    ForbidFocus: boolean?,
    Indent: string?,
    InjectGlobals: boolean?,
    MaxConcurrency: number?,
    Parallel: boolean?,
    PrintSkipped: boolean?,
    ReporterOutputs: { [string]: string }?,
    Reporters: { Reporter }?,
    SlowestTests: number?,
    SnapshotStore: SnapshotStore?,
    SuiteOrder: { string }?,
    Timeout: number?,
    UpdateSnapshots: boolean?,
    Verbose: boolean?,
    WorkerGroups: { { string } }?,
    WorkerSetup: string?,
    Workers: number?,
}

-- Where snapshot files are kept. Lune uses the filesystem when no store is set.
export type SnapshotStore = {
    read: (path: string) -> string?,
    write: (path: string, contents: string) -> (),
}

const Config = {
    AlphabeticalSort = false,
    Coverage = false,
    CoverageRoots = nil :: any?,
    CoverageRows = 20,
    CoverageSort = "Percentage" :: CoverageSort,
    CoverageThreshold = 0,
    Filter = nil :: string?,
    ForbidFocus = false,
    Indent = "   ",
    InjectGlobals = true,
    MaxConcurrency = 4,
    Parallel = true,
    PrintSkipped = false,
    ReporterOutputs = {} :: { [string]: string },
    Reporters = { TestEnum.Reporter.Text } :: { Reporter },
    SlowestTests = 0,
    SnapshotStore = nil :: SnapshotStore?,
    SuiteOrder = {} :: { string },
    Timeout = nil :: number?,
    UpdateSnapshots = false,
    Verbose = false,
    WorkerGroups = {} :: { { string } },
    WorkerSetup = nil :: string?,
    Workers = 1,
}

--[[
    Throws an "InvalidConfiguration" tool error unless the condition holds. Invalid
    options are a problem with how the run was set up rather than with any test, so
    callers can tell them apart from other errors with ToolError.is.

    @param condition - What has to hold for the options to be valid
    @param problem - What is wrong when it doesn't, without a period at the end
]]
const function check(condition: any, problem: string)
    if not condition then
        error(ToolError.new(ToolError.Kind.InvalidConfiguration, `The configuration is not valid. {problem}.`), 0)
    end
end

--[[
    Checks every key and index explicitly, since the length operator can hide holes in
    sparse arrays. Returns the number of elements after validating the dense layout.
]]
const function denseLength(value: any, label: string): number
    check(type(value) == "table" and getmetatable(value) == nil, `{label} must be a dense array`)
    local count = 0
    for key in pairs(value) do
        check(type(key) == "number" and key > 0 and key < math.huge and key % 1 == 0, `{label} must be a dense array`)
        count += 1
    end
    for index = 1, count do
        check(rawget(value, index) ~= nil, `{label} must be a dense array`)
    end
    return count
end

const function normalizePath(value: any, label: string): string
    check(type(value) == "string" and string.find(value, "%S") ~= nil, `{label} must be a nonblank path`)
    return PathUtil.normalize(value)
end

--[[
    Validates the given options one by one and stores each valid one. It throws at the
    first option that is not valid, which can leave earlier ones stored, so Config.set
    undoes those.

    @param options - Table of configuration options to set
]]
const function apply(options: ConfigOptions)
    check(type(options) == "table", "options must be a table")

    if options.AlphabeticalSort ~= nil then
        check(type(options.AlphabeticalSort) == "boolean", "AlphabeticalSort must be a boolean")
        Config.AlphabeticalSort = options.AlphabeticalSort
    end

    if options.Coverage ~= nil then
        check(type(options.Coverage) == "boolean", "Coverage must be a boolean")
        if options.Coverage then
            check(
                type(debug.iscoverageenabled) == "function",
                "Cannot enable coverage because debug.iscoverageenabled "
                    .. "is not available. Coverage requires Lune "
                    .. "0.10.4-horse.14.2 or later"
            )
            check(
                debug.iscoverageenabled(),
                "Cannot enable coverage because LUNE_COVERAGE is disabled. "
                    .. "Coverage is enabled by default. Set LUNE_COVERAGE=1 or "
                    .. "remove LUNE_COVERAGE=0 from your environment"
            )
        end
        Config.Coverage = options.Coverage
    end

    if options.CoverageRoots ~= nil then
        Config.CoverageRoots = options.CoverageRoots
    end

    if options.CoverageRows ~= nil then
        check(type(options.CoverageRows) == "number", "CoverageRows must be a number")
        check(options.CoverageRows >= 1 and options.CoverageRows % 1 == 0, "CoverageRows must be a positive integer")
        Config.CoverageRows = options.CoverageRows
    end

    if options.CoverageSort ~= nil then
        check(
            options.CoverageSort == "HitLines" or options.CoverageSort == "Percentage",
            'CoverageSort must be "HitLines" or "Percentage"'
        )
        Config.CoverageSort = options.CoverageSort
    end

    if options.CoverageThreshold ~= nil then
        check(type(options.CoverageThreshold) == "number", "CoverageThreshold must be a number")
        check(
            options.CoverageThreshold >= 0 and options.CoverageThreshold <= 100,
            "CoverageThreshold must be between 0 and 100"
        )
        Config.CoverageThreshold = options.CoverageThreshold
    end

    if options.Filter ~= nil then
        check(type(options.Filter) == "string", "Filter must be a string")
        -- An empty string clears the filter, since set() can't be passed nil for a key
        Config.Filter = if options.Filter == "" then nil else options.Filter
    end

    if options.ForbidFocus ~= nil then
        check(type(options.ForbidFocus) == "boolean", "ForbidFocus must be a boolean")
        Config.ForbidFocus = options.ForbidFocus
    end

    if options.Indent ~= nil then
        check(type(options.Indent) == "string", "Indent must be a string")
        Config.Indent = options.Indent
    end

    if options.InjectGlobals ~= nil then
        check(type(options.InjectGlobals) == "boolean", "InjectGlobals must be a boolean")
        Config.InjectGlobals = options.InjectGlobals
    end

    if options.MaxConcurrency ~= nil then
        check(type(options.MaxConcurrency) == "number", "MaxConcurrency must be a number")
        check(options.MaxConcurrency >= 1, "MaxConcurrency must be at least 1")
        Config.MaxConcurrency = options.MaxConcurrency
    end

    if options.Parallel ~= nil then
        check(type(options.Parallel) == "boolean", "Parallel must be a boolean")
        Config.Parallel = options.Parallel
    end

    if options.PrintSkipped ~= nil then
        check(type(options.PrintSkipped) == "boolean", "PrintSkipped must be a boolean")
        Config.PrintSkipped = options.PrintSkipped
    end

    if options.ReporterOutputs ~= nil then
        check(type(options.ReporterOutputs) == "table", "ReporterOutputs must be a table")
        for name, path in options.ReporterOutputs do
            check(
                TestEnum.Reporter[name] ~= nil and name ~= TestEnum.Reporter.Text,
                'ReporterOutputs keys must be "JUnit", "Json", or "Lcov"'
            )
            check(type(path) == "string" and path ~= "", "ReporterOutputs paths must be non-empty strings")
        end
        -- Copied so that later changes to the caller's table don't change the config.
        Config.ReporterOutputs = table.clone(options.ReporterOutputs)
    end

    if options.Reporters ~= nil then
        check(type(options.Reporters) == "table", "Reporters must be an array")
        for _, name in options.Reporters do
            check(
                type(name) == "string" and TestEnum.Reporter[name] ~= nil,
                'Reporters must only contain "JUnit", "Json", "Lcov", or "Text"'
            )
        end
        Config.Reporters = table.clone(options.Reporters)
    end

    if options.SlowestTests ~= nil then
        check(type(options.SlowestTests) == "number", "SlowestTests must be a number")
        check(
            options.SlowestTests >= 0 and options.SlowestTests % 1 == 0,
            "SlowestTests must be a non-negative integer"
        )
        Config.SlowestTests = options.SlowestTests
    end

    if options.SnapshotStore ~= nil then
        const store = options.SnapshotStore
        check(
            type(store) == "table" and type(store.read) == "function" and type(store.write) == "function",
            "SnapshotStore must be a table with read and write functions"
        )
        Config.SnapshotStore = store
    end

    if options.SuiteOrder ~= nil then
        const problem = SuiteOrder.problem(options.SuiteOrder)
        check(problem == nil, problem or "")
        Config.SuiteOrder = table.clone(options.SuiteOrder)
    end

    if options.Timeout ~= nil then
        check(TestTimeout.isValid(options.Timeout), "Timeout must be a positive number of seconds")
        Config.Timeout = options.Timeout
    end

    if options.UpdateSnapshots ~= nil then
        check(type(options.UpdateSnapshots) == "boolean", "UpdateSnapshots must be a boolean")
        Config.UpdateSnapshots = options.UpdateSnapshots
    end

    if options.Verbose ~= nil then
        check(type(options.Verbose) == "boolean", "Verbose must be a boolean")
        Config.Verbose = options.Verbose
    end

    if options.WorkerGroups ~= nil then
        const groups = {}
        for groupIndex = 1, denseLength(options.WorkerGroups, "WorkerGroups") do
            const label = `WorkerGroups[{groupIndex}]`
            const group = options.WorkerGroups[groupIndex]
            const count = denseLength(group, label)
            check(count > 0, `{label} must not be empty`)
            const paths = {}
            for pathIndex = 1, count do
                table.insert(paths, normalizePath(group[pathIndex], `{label}[{pathIndex}]`))
            end
            table.insert(groups, paths)
        end
        -- Overlaps are intentional. Scheduling unions all groups before selecting files,
        -- including transitive links through files that are not part of this run.
        Config.WorkerGroups = groups
    end

    if options.WorkerSetup ~= nil then
        Config.WorkerSetup = normalizePath(options.WorkerSetup, "WorkerSetup")
    end

    if options.Workers ~= nil then
        check(
            type(options.Workers) == "number"
                and options.Workers > 0
                and options.Workers < math.huge
                and options.Workers % 1 == 0,
            "Workers must be a finite positive integer"
        )
        Config.Workers = options.Workers
    end
end

--[[
    Sets configuration options. Only provided keys will be updated. Throws an
    "InvalidConfiguration" ToolError when an option is not valid, and in that case none
    of the given options is applied.

    @param options - Table of configuration options to set
]]
function Config.set(options: ConfigOptions)
    const previous = table.clone(Config)

    const ok, problem = pcall(apply, options)
    if not ok then
        -- An option that had no value before has no entry to copy back, so it is
        -- cleared first.
        for key in table.clone(Config) do
            (Config :: any)[key] = nil
        end
        for key, value in previous do
            (Config :: any)[key] = value
        end
        error(problem, 0)
    end
end

--[[
    Resets all configuration options to their default values.
]]
function Config.reset()
    Config.AlphabeticalSort = false
    Config.Coverage = false
    Config.CoverageRoots = nil
    Config.CoverageRows = 20
    Config.CoverageSort = "Percentage"
    Config.CoverageThreshold = 0
    Config.Filter = nil
    Config.ForbidFocus = false
    Config.Indent = "   "
    Config.InjectGlobals = true
    Config.MaxConcurrency = 4
    Config.Parallel = true
    Config.PrintSkipped = false
    Config.ReporterOutputs = {}
    Config.Reporters = { TestEnum.Reporter.Text }
    Config.SlowestTests = 0
    Config.SnapshotStore = nil
    Config.SuiteOrder = {}
    Config.Timeout = nil
    Config.UpdateSnapshots = false
    Config.Verbose = false
    Config.WorkerGroups = {}
    Config.WorkerSetup = nil
    Config.Workers = 1
end

return Config
