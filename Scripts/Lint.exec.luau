#!/usr/bin/env -S lune run

--[[

Lint.exec

Runs luau-lsp analyze over the whole repository to report type errors and lint warnings,
and exits with 1 when it finds any. The static analysis jobs in CI run this same script,
so a passing run here means the same thing as a passing run there.

[Usage] ./Scripts/Lint.exec.luau

--]]

const HasAnalysisIssues = require("@submodules/luau-cicd/Scripts/Helpers/HasAnalysisIssues.func")
const LintAnalysis = require("./Helpers/LintAnalysis")
const fs = require("@lune/fs")
const process = require("@lune/process")

const Lint = {}

--[[
    Writes the extra type definitions to a scratch directory, since luau-lsp only reads
    definitions from a file.

    @return directory - The scratch directory to remove afterwards
    @return path - The path of the definitions file inside it
]]
const function writeDefinitions(): (string, string)
    const base = process.env.RUNNER_TEMP or process.env.TMPDIR or process.env.TEMP or "/tmp"
    const root = string.gsub(string.gsub(base, "\\", "/"), "/+$", "")
    const directory = `{root}/testable_lint_{os.time()}_{math.random(100000, 999999)}`
    const path = `{directory}/{LintAnalysis.DefinitionsFileName}`

    fs.writeDir(directory)
    fs.writeFile(path, LintAnalysis.Definitions)

    return directory, path
end

function Lint.exec()
    print("Running static analysis...")

    const directory, definitionsPath = writeDefinitions()
    const result = process.exec("luau-lsp", LintAnalysis.buildArguments(definitionsPath))
    fs.removeDir(directory)

    if result.stdout ~= "" then
        print(result.stdout)
    end
    if result.stderr ~= "" then
        print(result.stderr)
    end

    if HasAnalysisIssues(result.ok, result.stdout, result.stderr) then
        print("Static analysis found problems.")
        process.exit(1)
    end

    print("Static analysis passed.")
end

Lint.exec()
