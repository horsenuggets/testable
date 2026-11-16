--[[

LintAnalysis

Describes the one static analysis run that both contributors and CI use, so a type error
is reported the same way everywhere. Building the luau-lsp arguments is pure, so it never
touches the file system or starts a process itself.

The analysis uses the old type solver. The specs and sources here are not marked strict,
and the new solver reports almost nothing for non-strict files, so analyzing with it
would let type errors through.

--]]

const DEFINITIONS_FILE_NAME = "TestableLintDefinitions.d.luau"
-- Types for the coverage functions that the Lune fork adds to the debug library, which
-- the built-in definitions don't know about.
const DEFINITIONS = [[
export type CoverageEntry = { Function: string, LineDefined: number, Depth: number, Hits: {number} }
declare debug: {
    info: (...any) -> ...any,
    traceback: ((string?, number?) -> string) & ((thread, string?, number?) -> string),
    getcoverage: (fn: (...any) -> ...any) -> {CoverageEntry},
    iscoverageenabled: () -> boolean,
}
]]
-- Dotfolders are ignored so that worktrees nested in the checkout aren't analyzed twice.
const IGNORE_PATTERNS = table.freeze({
    ".*/**",
    "DevPackages/**",
    "Packages/**",
    "ServerPackages/**",
    "Submodules/**",
})
const PLATFORM = "lune"
const TARGET = "."

const LintAnalysis = {}

LintAnalysis.Definitions = DEFINITIONS
LintAnalysis.DefinitionsFileName = DEFINITIONS_FILE_NAME

--[[
    Builds the arguments for the luau-lsp process that analyzes the whole repository.

    @param definitionsPath - The path of a file containing LintAnalysis.Definitions
    @return The arguments to start luau-lsp with
]]
function LintAnalysis.buildArguments(definitionsPath: string): { string }
    assert(type(definitionsPath) == "string", "definitionsPath must be a string")
    assert(definitionsPath ~= "", "definitionsPath must not be empty")

    const arguments = {
        "analyze",
        `--platform={PLATFORM}`,
        "--no-flags-enabled",
        `--definitions={definitionsPath}`,
    }
    for _, pattern in IGNORE_PATTERNS do
        table.insert(arguments, `--ignore={pattern}`)
    end
    table.insert(arguments, TARGET)

    return arguments
end

return LintAnalysis
