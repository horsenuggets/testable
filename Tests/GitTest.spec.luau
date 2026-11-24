--[[

GitTest.spec

Tests for asking git which files changed since a ref, using a fake command runner. Covers
the commands that are run, how their output is read, and the errors for an invalid ref
and for a directory that is not in a repository.

--]]

const Git = require("../Source/Testable/Discovery/Git")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

type FakeOptions = {
    Diff: string?,
    DiffFails: boolean?,
    InRepository: boolean?,
    RefExists: boolean?,
    Untracked: string?
}

--[[
    Creates a fake git runner and the list that records every command it receives.

    @param options - What the fake repository should report
    @return exec - The fake runner
    @return calls - The recorded commands, each joined with spaces
]]
const function createExec(options: FakeOptions): (Git.Exec, { string })
    const calls = {}

    const function exec(arguments: { string }, _workingDirectory: string): Git.ExecResult
        table.insert(calls, table.concat(arguments, " "))

        if arguments[1] == "rev-parse" and arguments[2] == "--is-inside-work-tree" then
            return { Ok = options.InRepository ~= false, Stderr = "", Stdout = "true\n" }
        elseif arguments[1] == "rev-parse" then
            return { Ok = options.RefExists ~= false, Stderr = "", Stdout = "" }
        elseif arguments[1] == "diff" then
            return { Ok = not options.DiffFails, Stderr = "The diff failed.", Stdout = options.Diff or "" }
        end
        return { Ok = true, Stderr = "", Stdout = options.Untracked or "" }
    end

    return exec, calls
end

return function()
    describe("Git.parseNameList()", function()
        it("should split NUL-separated names", function()
            expect(table.concat(Git.parseNameList("a.luau\0dir/b c.luau\0"), "|")).to.equal("a.luau|dir/b c.luau")
        end)

        it("should return nothing for empty output", function()
            expect(#Git.parseNameList("")).to.equal(0)
        end)
    end)

    describe("Git.changedFiles()", function()
        it("should combine tracked and untracked changes in sorted order", function()
            const exec = createExec({ Diff = "Source/B.luau\0Source/A.luau\0", Untracked = "Tests/New.spec.luau\0" })
            expect(table.concat(Git.changedFiles(exec, "/root", "origin/main"), ",")).to.equal(
                "Source/A.luau,Source/B.luau,Tests/New.spec.luau"
            )
        end)

        it("should not repeat a file that both commands report", function()
            const exec = createExec({ Diff = "A.luau\0", Untracked = "A.luau\0" })
            expect(table.concat(Git.changedFiles(exec, "/root", "HEAD"), ",")).to.equal("A.luau")
        end)

        it("should return nothing when nothing changed", function()
            const exec = createExec({})
            expect(#Git.changedFiles(exec, "/root", "HEAD")).to.equal(0)
        end)

        it("should verify the ref as a commit and diff against it", function()
            const exec, calls = createExec({})
            Git.changedFiles(exec, "/root", "HEAD~1")
            expect(table.concat(calls, "\n")).to.equal(table.concat({
                "rev-parse --is-inside-work-tree",
                "rev-parse --verify --quiet HEAD~1^{commit}",
                "diff --name-only --no-renames --relative -z HEAD~1 --",
                "ls-files --others --exclude-standard -z"
            }, "\n"))
        end)

        it("should fail outside a git repository", function()
            const exec = createExec({ InRepository = false })
            expect(function()
                Git.changedFiles(exec, "/root", "HEAD")
            end).to.throw("is not inside a git repository")
        end)

        it("should fail for a ref that does not exist", function()
            const exec = createExec({ RefExists = false })
            expect(function()
                Git.changedFiles(exec, "/root", "missing-branch")
            end).to.throw('"missing-branch" is not a valid git ref')
        end)

        it("should reject an empty ref or one that looks like an option without running git", function()
            for _, ref in { "", "--output=file", "-p" } do
                const exec, calls = createExec({})
                expect(function()
                    Git.changedFiles(exec, "/root", ref)
                end).to.throw("is not a valid git ref")
                expect(#calls).to.equal(0)
            end
        end)

        it("should fail when the diff itself fails", function()
            const exec = createExec({ DiffFails = true })
            expect(function()
                Git.changedFiles(exec, "/root", "HEAD")
            end).to.throw("The diff failed.")
        end)
    end)
end
