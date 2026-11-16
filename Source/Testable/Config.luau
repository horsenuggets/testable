--[[

Config

Central configuration module for Testable. Stores all configurable options with their
default values.

--]]

const TestEnum = require("./TestEnum")
const TestTimeout = require("./TestTimeout")

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
    Timeout: number?,
    UpdateSnapshots: boolean?,
    Verbose: boolean?,
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
    Timeout = nil :: number?,
    UpdateSnapshots = false,
    Verbose = false,
}

--[[
    Sets configuration options. Only provided keys will be updated.

    @param options - Table of configuration options to set
]]
function Config.set(options: ConfigOptions)
    assert(type(options) == "table", "options must be a table")

    if options.AlphabeticalSort ~= nil then
        assert(type(options.AlphabeticalSort) == "boolean", "AlphabeticalSort must be a boolean")
        Config.AlphabeticalSort = options.AlphabeticalSort
    end

    if options.Coverage ~= nil then
        assert(type(options.Coverage) == "boolean", "Coverage must be a boolean")
        if options.Coverage then
            const hasApi = type(debug.iscoverageenabled) == "function"
            if not hasApi then
                error(
                    "Cannot enable coverage because debug.iscoverageenabled "
                        .. "is not available. Coverage requires Lune "
                        .. "0.10.4-horse.14.2 or later."
                )
            end
            if not debug.iscoverageenabled() then
                error(
                    "Cannot enable coverage because LUNE_COVERAGE is disabled. "
                        .. "Coverage is enabled by default. Set LUNE_COVERAGE=1 or "
                        .. "remove LUNE_COVERAGE=0 from your environment."
                )
            end
        end
        Config.Coverage = options.Coverage
    end

    if options.CoverageRoots ~= nil then
        Config.CoverageRoots = options.CoverageRoots
    end

    if options.CoverageRows ~= nil then
        assert(type(options.CoverageRows) == "number", "CoverageRows must be a number")
        assert(options.CoverageRows >= 1 and options.CoverageRows % 1 == 0, "CoverageRows must be a positive integer")
        Config.CoverageRows = options.CoverageRows
    end

    if options.CoverageSort ~= nil then
        assert(
            options.CoverageSort == "HitLines" or options.CoverageSort == "Percentage",
            'CoverageSort must be "HitLines" or "Percentage"'
        )
        Config.CoverageSort = options.CoverageSort
    end

    if options.CoverageThreshold ~= nil then
        assert(type(options.CoverageThreshold) == "number", "CoverageThreshold must be a number")
        assert(
            options.CoverageThreshold >= 0 and options.CoverageThreshold <= 100,
            "CoverageThreshold must be between 0 and 100"
        )
        Config.CoverageThreshold = options.CoverageThreshold
    end

    if options.Filter ~= nil then
        assert(type(options.Filter) == "string", "Filter must be a string")
        -- An empty string clears the filter, since set() can't be passed nil for a key
        Config.Filter = if options.Filter == "" then nil else options.Filter
    end

    if options.ForbidFocus ~= nil then
        assert(type(options.ForbidFocus) == "boolean", "ForbidFocus must be a boolean")
        Config.ForbidFocus = options.ForbidFocus
    end

    if options.Indent ~= nil then
        assert(type(options.Indent) == "string", "Indent must be a string")
        Config.Indent = options.Indent
    end

    if options.InjectGlobals ~= nil then
        assert(type(options.InjectGlobals) == "boolean", "InjectGlobals must be a boolean")
        Config.InjectGlobals = options.InjectGlobals
    end

    if options.MaxConcurrency ~= nil then
        assert(type(options.MaxConcurrency) == "number", "MaxConcurrency must be a number")
        assert(options.MaxConcurrency >= 1, "MaxConcurrency must be at least 1")
        Config.MaxConcurrency = options.MaxConcurrency
    end

    if options.Parallel ~= nil then
        assert(type(options.Parallel) == "boolean", "Parallel must be a boolean")
        Config.Parallel = options.Parallel
    end

    if options.PrintSkipped ~= nil then
        assert(type(options.PrintSkipped) == "boolean", "PrintSkipped must be a boolean")
        Config.PrintSkipped = options.PrintSkipped
    end

    if options.ReporterOutputs ~= nil then
        assert(type(options.ReporterOutputs) == "table", "ReporterOutputs must be a table")
        for name, path in options.ReporterOutputs do
            assert(
                TestEnum.Reporter[name] ~= nil and name ~= TestEnum.Reporter.Text,
                'ReporterOutputs keys must be "JUnit", "Json", or "Lcov"'
            )
            assert(type(path) == "string" and path ~= "", "ReporterOutputs paths must be non-empty strings")
        end
        -- Copied so that later changes to the caller's table don't change the config.
        Config.ReporterOutputs = table.clone(options.ReporterOutputs)
    end

    if options.Reporters ~= nil then
        assert(type(options.Reporters) == "table", "Reporters must be an array")
        for _, name in options.Reporters do
            assert(
                type(name) == "string" and TestEnum.Reporter[name] ~= nil,
                'Reporters must only contain "JUnit", "Json", "Lcov", or "Text"'
            )
        end
        Config.Reporters = table.clone(options.Reporters)
    end

    if options.SlowestTests ~= nil then
        assert(type(options.SlowestTests) == "number", "SlowestTests must be a number")
        assert(
            options.SlowestTests >= 0 and options.SlowestTests % 1 == 0,
            "SlowestTests must be a non-negative integer"
        )
        Config.SlowestTests = options.SlowestTests
    end

    if options.SnapshotStore ~= nil then
        const store = options.SnapshotStore
        assert(
            type(store) == "table" and type(store.read) == "function" and type(store.write) == "function",
            "SnapshotStore must be a table with read and write functions"
        )
        Config.SnapshotStore = store
    end

    if options.Timeout ~= nil then
        assert(TestTimeout.isValid(options.Timeout), "Timeout must be a positive number of seconds")
        Config.Timeout = options.Timeout
    end

    if options.UpdateSnapshots ~= nil then
        assert(type(options.UpdateSnapshots) == "boolean", "UpdateSnapshots must be a boolean")
        Config.UpdateSnapshots = options.UpdateSnapshots
    end

    if options.Verbose ~= nil then
        assert(type(options.Verbose) == "boolean", "Verbose must be a boolean")
        Config.Verbose = options.Verbose
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
    Config.Timeout = nil
    Config.UpdateSnapshots = false
    Config.Verbose = false
end

return Config
