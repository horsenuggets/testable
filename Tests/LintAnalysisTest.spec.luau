--[[

LintAnalysisTest.spec

Tests for the static analysis run that contributors and CI share. They pin the luau-lsp
arguments, because a difference between a local run and a CI run is what lets a type
error pass in one place and fail in the other.

--]]

const LintAnalysis = require("../Scripts/Helpers/LintAnalysis")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const CI_WORKFLOW_PATHS = { ".github/workflows/main.ci.yml", ".github/workflows/release.ci.yml" }
const LINT_SCRIPT_PATH = "Scripts/Lint.exec.luau"

const function contains(values: { string }, expected: string): boolean
    return table.find(values, expected) ~= nil
end

return function()
    describe("buildArguments", function()
        it("should analyze the whole repository on the Lune platform", function()
            const arguments = LintAnalysis.buildArguments("/scratch/definitions.d.luau")

            expect(arguments[1]).to.equal("analyze")
            expect(arguments[#arguments]).to.equal(".")
            expect(contains(arguments, "--platform=lune")).to.equal(true)
            expect(contains(arguments, "--no-flags-enabled")).to.equal(true)
        end)

        it("should load the definitions file it is given", function()
            const arguments = LintAnalysis.buildArguments("/scratch/definitions.d.luau")

            expect(contains(arguments, "--definitions=/scratch/definitions.d.luau")).to.equal(true)
        end)

        it("should not turn on the new solver, which stays silent in non-strict files", function()
            for _, argument in LintAnalysis.buildArguments("/scratch/definitions.d.luau") do
                expect(string.find(argument, "solver", 1, true)).to.equal(nil)
                expect(string.find(argument, "LuauSolverV2", 1, true)).to.equal(nil)
            end
        end)

        it("should only ignore dependencies, submodules, and dotfolders", function()
            const ignored = {}
            for _, argument in LintAnalysis.buildArguments("/scratch/definitions.d.luau") do
                const pattern = string.match(argument, "^%-%-ignore=(.+)$")
                if pattern ~= nil then
                    table.insert(ignored, pattern)
                end
            end

            expect(table.concat(ignored, " ")).to.equal(
                ".*/** DevPackages/** Packages/** ServerPackages/** Submodules/**"
            )
        end)

        it("should be pure", function()
            const first = LintAnalysis.buildArguments("/scratch/definitions.d.luau")
            const second = LintAnalysis.buildArguments("/scratch/definitions.d.luau")

            expect(table.concat(first, "\n")).to.equal(table.concat(second, "\n"))
        end)

        it("should reject a missing definitions path", function()
            expect(pcall(LintAnalysis.buildArguments, "")).to.equal(false)
            expect(pcall(LintAnalysis.buildArguments, nil :: any)).to.equal(false)
        end)
    end)

    describe("Definitions", function()
        it("should declare the coverage functions of the debug library", function()
            expect(string.find(LintAnalysis.Definitions, "getcoverage", 1, true)).never.to.equal(nil)
            expect(string.find(LintAnalysis.Definitions, "iscoverageenabled", 1, true)).never.to.equal(nil)
        end)
    end)

    describe("CI", function()
        it("should run the lint script instead of calling luau-lsp itself", function()
            for _, path in CI_WORKFLOW_PATHS do
                const workflow = fs.readFile(path)

                expect(string.find(workflow, `run: ./{LINT_SCRIPT_PATH}`, 1, true)).never.to.equal(nil)
                expect(string.find(workflow, "luau-lsp analyze", 1, true)).to.equal(nil)
            end
        end)
    end)
end
