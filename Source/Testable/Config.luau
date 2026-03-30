--[[

Config

Central configuration module for Testable. Stores all configurable options with their
default values.

--]]

export type ConfigOptions = {
    AlphabeticalSort: boolean?,
    Coverage: boolean?,
    CoverageRoots: any?,
    CoverageThreshold: number?,
    Indent: string?,
    MaxConcurrency: number?,
    Parallel: boolean?,
    PrintSkipped: boolean?,
    Verbose: boolean?,
}

local Config = {
    AlphabeticalSort = false,
    Coverage = false,
    CoverageRoots = nil :: any?,
    CoverageThreshold = 0,
    Indent = "   ",
    MaxConcurrency = 4,
    Parallel = true,
    PrintSkipped = false,
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
        if options.Coverage and not debug.iscoverageenabled() then
            error(
                "Cannot enable coverage because LUNE_COVERAGE is disabled. "
                    .. "Coverage is enabled by default. Set LUNE_COVERAGE=1 or "
                    .. "remove LUNE_COVERAGE=0 from your environment."
            )
        end
        Config.Coverage = options.Coverage
    end

    if options.CoverageRoots ~= nil then
        Config.CoverageRoots = options.CoverageRoots
    end

    if options.CoverageThreshold ~= nil then
        assert(type(options.CoverageThreshold) == "number", "CoverageThreshold must be a number")
        assert(
            options.CoverageThreshold >= 0 and options.CoverageThreshold <= 100,
            "CoverageThreshold must be between 0 and 100"
        )
        Config.CoverageThreshold = options.CoverageThreshold
    end

    if options.Indent ~= nil then
        assert(type(options.Indent) == "string", "Indent must be a string")
        Config.Indent = options.Indent
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
    Config.CoverageThreshold = 0
    Config.Indent = "   "
    Config.MaxConcurrency = 4
    Config.Parallel = true
    Config.PrintSkipped = false
    Config.Verbose = false
end

return Config
