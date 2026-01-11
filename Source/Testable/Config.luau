--[[

Config

Central configuration module for Testable. Stores all configurable options with their
default values.

--]]

export type ConfigOptions = {
    AlphabeticalSort: boolean?,
    Indent: string?,
    MaxConcurrency: number?,
    Parallel: boolean?,
    PrintSkipped: boolean?,
    Verbose: boolean?,
}

local Config = {
    AlphabeticalSort = false,
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
    Config.Indent = "   "
    Config.MaxConcurrency = 4
    Config.Parallel = true
    Config.PrintSkipped = false
    Config.Verbose = false
end

return Config
