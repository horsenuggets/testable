--[[

GlobTest.spec

Tests for glob matching and for finding files in an injected filesystem. Covers single
and double star wildcards, hidden files and directories, exclude globs, and the
deterministic order of the results.

--]]

const FakeFileSystem = require("./Helpers/FakeFileSystem")
const Glob = require("../Source/Testable/Discovery/Glob")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const FILES = {
    ["/root/.hidden/Hidden.spec.luau"] = "",
    ["/root/Source/Module.luau"] = "",
    ["/root/Tests/.Dot.spec.luau"] = "",
    ["/root/Tests/A.spec.luau"] = "",
    ["/root/Tests/B.spec.luau"] = "",
    ["/root/Tests/Helpers/Helper.luau"] = "",
    ["/root/Tests/Nested/.git/E.spec.luau"] = "",
    ["/root/Tests/Nested/C.spec.luau"] = "",
    ["/root/Tests/Nested/Deep/D.spec.luau"] = "",
    ["/root/Top.spec.luau"] = ""
}

const function find(include: { string }, exclude: { string }?): string
    return table.concat(Glob.find(FakeFileSystem.new(FILES), "/root", include, exclude), ",")
end

return function()
    describe("Glob.matches()", function()
        it("should match a literal path exactly", function()
            expect(Glob.matches("Tests/A.spec.luau", "Tests/A.spec.luau")).to.equal(true)
            expect(Glob.matches("Tests/A.spec.luau", "Tests/B.spec.luau")).to.equal(false)
        end)

        it("should stop a single star at a directory boundary", function()
            expect(Glob.matches("Tests/*.spec.luau", "Tests/A.spec.luau")).to.equal(true)
            expect(Glob.matches("Tests/*.spec.luau", "Tests/Nested/C.spec.luau")).to.equal(false)
            expect(Glob.matches("*/A.spec.luau", "Tests/Nested/A.spec.luau")).to.equal(false)
        end)

        it("should let a double star span any depth, including none", function()
            expect(Glob.matches("Tests/**/*.spec.luau", "Tests/A.spec.luau")).to.equal(true)
            expect(Glob.matches("Tests/**/*.spec.luau", "Tests/Nested/C.spec.luau")).to.equal(true)
            expect(Glob.matches("Tests/**/*.spec.luau", "Tests/Nested/Deep/D.spec.luau")).to.equal(true)
            expect(Glob.matches("**/*.spec.luau", "Top.spec.luau")).to.equal(true)
            expect(Glob.matches("Tests/**", "Tests/Nested/Deep/D.spec.luau")).to.equal(true)
        end)

        it("should not let a double star escape its prefix", function()
            expect(Glob.matches("Tests/**/*.spec.luau", "Source/A.spec.luau")).to.equal(false)
            expect(Glob.matches("Tests/**/*.spec.luau", "Tests/Helpers/Helper.luau")).to.equal(false)
        end)

        it("should match one character with a question mark", function()
            expect(Glob.matches("Tests/?.spec.luau", "Tests/A.spec.luau")).to.equal(true)
            expect(Glob.matches("Tests/?.spec.luau", "Tests/AB.spec.luau")).to.equal(false)
            expect(Glob.matches("Tests/?.spec.luau", "Tests/.spec.luau")).to.equal(false)
        end)

        it("should treat pattern characters in a glob literally", function()
            expect(Glob.matches("Tests/*.spec.luau", "Tests/AxspecXluau")).to.equal(false)
            expect(Glob.matches("a-b/(c)+%d.luau", "a-b/(c)+%d.luau")).to.equal(true)
            expect(Glob.matches("a-b/(c)+%d.luau", "a-b/c5.luau")).to.equal(false)
        end)

        it("should require the whole path to match", function()
            expect(Glob.matches("Tests/*.spec", "Tests/A.spec.luau")).to.equal(false)
            expect(Glob.matches("*.spec.luau", "Tests/A.spec.luau")).to.equal(false)
        end)
    end)

    describe("Glob.isHidden()", function()
        it("should detect a hidden segment anywhere in the path", function()
            expect(Glob.isHidden(".luaurc")).to.equal(true)
            expect(Glob.isHidden("Tests/.git/A.luau")).to.equal(true)
            expect(Glob.isHidden(".wt/feature/A.luau")).to.equal(true)
        end)

        it("should not count navigation segments or inner dots", function()
            expect(Glob.isHidden("Tests/A.spec.luau")).to.equal(false)
            expect(Glob.isHidden("./Tests/../A.luau")).to.equal(false)
        end)
    end)

    describe("Glob.staticPrefix()", function()
        it("should return the directories before the first wildcard", function()
            expect(Glob.staticPrefix("Tests/**/*.spec.luau")).to.equal("Tests")
            expect(Glob.staticPrefix("Tests/Nested/*.spec.luau")).to.equal("Tests/Nested")
            expect(Glob.staticPrefix("Tests/Nested/A.spec.luau")).to.equal("Tests/Nested")
        end)

        it("should return a dot when the glob starts with a wildcard or a file", function()
            expect(Glob.staticPrefix("**/*.spec.luau")).to.equal(".")
            expect(Glob.staticPrefix("*.spec.luau")).to.equal(".")
            expect(Glob.staticPrefix("Top.spec.luau")).to.equal(".")
        end)
    end)

    describe("Glob.find()", function()
        it("should find specs at any depth in sorted order", function()
            expect(find({ "Tests/**/*.spec.luau" })).to.equal(
                "Tests/A.spec.luau,Tests/B.spec.luau,Tests/Nested/C.spec.luau,Tests/Nested/Deep/D.spec.luau"
            )
        end)

        it("should only find direct children with a single star", function()
            expect(find({ "Tests/*.spec.luau" })).to.equal("Tests/A.spec.luau,Tests/B.spec.luau")
        end)

        it("should skip hidden files and directories even when a glob names them", function()
            expect(find({ "**/*.spec.luau" })).to.equal(
                "Tests/A.spec.luau,Tests/B.spec.luau,Tests/Nested/C.spec.luau,Tests/Nested/Deep/D.spec.luau,Top.spec.luau"
            )
            expect(find({ ".hidden/*.spec.luau" })).to.equal("")
            expect(find({ "Tests/.Dot.spec.luau" })).to.equal("")
        end)

        it("should merge several globs without duplicates", function()
            expect(find({ "Tests/*.spec.luau", "Tests/A.spec.luau", "Top.spec.luau" })).to.equal(
                "Tests/A.spec.luau,Tests/B.spec.luau,Top.spec.luau"
            )
        end)

        it("should remove files that match an exclude glob", function()
            expect(find({ "Tests/**/*.spec.luau" }, { "Tests/Nested/**" })).to.equal(
                "Tests/A.spec.luau,Tests/B.spec.luau"
            )
        end)

        it("should return nothing when no file matches or the directory is missing", function()
            expect(find({ "Tests/**/*.story.luau" })).to.equal("")
            expect(find({ "Missing/**/*.spec.luau" })).to.equal("")
        end)

        it("should never leave the root", function()
            expect(find({ "../**/*.spec.luau" })).to.equal("")
        end)

        it("should return the same result every time", function()
            expect(find({ "**/*.luau" })).to.equal(find({ "**/*.luau" }))
        end)
    end)
end
