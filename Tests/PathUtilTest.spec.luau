--[[

PathUtilTest.spec

Tests for the lexical path helpers that spec discovery builds on, covering normalization,
joining, directory and base names, relative paths, and extension stripping.

--]]

const PathUtil = require("../Source/Testable/Discovery/PathUtil")

return function()
    describe("PathUtil.normalize()", function()
        it("should collapse dot segments and duplicate slashes", function()
            expect(PathUtil.normalize("a/./b//c/")).to.equal("a/b/c")
            expect(PathUtil.normalize("a/b/../c")).to.equal("a/c")
            expect(PathUtil.normalize("./a")).to.equal("a")
        end)

        it("should keep leading parent segments of a relative path", function()
            expect(PathUtil.normalize("../a")).to.equal("../a")
            expect(PathUtil.normalize("a/../../b")).to.equal("../b")
        end)

        it("should never climb above an absolute root", function()
            expect(PathUtil.normalize("/a/../../b")).to.equal("/b")
            expect(PathUtil.normalize("/")).to.equal("/")
        end)

        it("should turn an empty result into a dot", function()
            expect(PathUtil.normalize("")).to.equal(".")
            expect(PathUtil.normalize("a/..")).to.equal(".")
        end)

        it("should convert backslashes, drives, and verbatim prefixes", function()
            expect(PathUtil.normalize("c:\\Project\\Tests")).to.equal("C:/Project/Tests")
            expect(PathUtil.normalize("\\\\?\\C:\\Project")).to.equal("C:/Project")
            expect(PathUtil.normalize("C:")).to.equal("C:/")
        end)

        it("should return the same result when called twice", function()
            const once = PathUtil.normalize("a//b/../c/./d")
            expect(PathUtil.normalize(once)).to.equal(once)
        end)
    end)

    describe("PathUtil.isAbsolute()", function()
        it("should recognize roots and drives", function()
            expect(PathUtil.isAbsolute("/a")).to.equal(true)
            expect(PathUtil.isAbsolute("C:/a")).to.equal(true)
            expect(PathUtil.isAbsolute("C:\\a")).to.equal(true)
        end)

        it("should reject relative paths", function()
            expect(PathUtil.isAbsolute("a/b")).to.equal(false)
            expect(PathUtil.isAbsolute("./a")).to.equal(false)
            expect(PathUtil.isAbsolute("../a")).to.equal(false)
        end)
    end)

    describe("PathUtil.join()", function()
        it("should append a relative path to the base", function()
            expect(PathUtil.join("/root", "Tests/A.luau")).to.equal("/root/Tests/A.luau")
            expect(PathUtil.join("/root/Tests", "../Source")).to.equal("/root/Source")
            expect(PathUtil.join("/root", ".")).to.equal("/root")
        end)

        it("should let an absolute path replace the base", function()
            expect(PathUtil.join("/root", "/other/A.luau")).to.equal("/other/A.luau")
        end)
    end)

    describe("PathUtil.dirname() and PathUtil.basename()", function()
        it("should split a path into its directory and name", function()
            expect(PathUtil.dirname("/a/b/c.luau")).to.equal("/a/b")
            expect(PathUtil.basename("/a/b/c.luau")).to.equal("c.luau")
            expect(PathUtil.dirname("a/b")).to.equal("a")
        end)

        it("should stop at the root or the current directory", function()
            expect(PathUtil.dirname("/a")).to.equal("/")
            expect(PathUtil.dirname("/")).to.equal("/")
            expect(PathUtil.dirname("a")).to.equal(".")
            expect(PathUtil.dirname(".")).to.equal(".")
            expect(PathUtil.basename("/")).to.equal("")
        end)
    end)

    describe("PathUtil.relative()", function()
        it("should descend into a child path", function()
            expect(PathUtil.relative("/root", "/root/Tests/A.luau")).to.equal("Tests/A.luau")
        end)

        it("should climb out of unrelated directories", function()
            expect(PathUtil.relative("/root/Packages/Testable", "/root/Tests/A")).to.equal("../../Tests/A")
        end)

        it("should return a dot for the same path", function()
            expect(PathUtil.relative("/root/a", "/root/a")).to.equal(".")
        end)

        it("should return nil across different roots or drives", function()
            expect(PathUtil.relative("C:/a", "D:/a")).to.equal(nil)
            expect(PathUtil.relative("/a", "a")).to.equal(nil)
        end)

        it("should lead back to the target when joined onto the start", function()
            const from = "/root/Source/Testable/Discovery"
            for _, to in { "/root/Tests/A", "/root/Source/Testable/B", "/elsewhere/C", "/root" } do
                const relativePath = PathUtil.relative(from, to) :: string
                expect(PathUtil.join(from, relativePath)).to.equal(to)
            end
        end)
    end)

    describe("PathUtil.stripLuauExtension()", function()
        it("should remove a Luau extension and keep everything else", function()
            expect(PathUtil.stripLuauExtension("Tests/A.spec.luau")).to.equal("Tests/A.spec")
            expect(PathUtil.stripLuauExtension("Tests/A.lua")).to.equal("Tests/A")
            expect(PathUtil.stripLuauExtension("Tests/A.txt")).to.equal("Tests/A.txt")
            expect(PathUtil.stripLuauExtension("Tests/luau")).to.equal("Tests/luau")
        end)
    end)
end
