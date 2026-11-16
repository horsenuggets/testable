--[[

RequireGraphTest.spec

Tests for scanning string requires out of source text, resolving them to files, building
the require graph through an injected filesystem, and inverting it to find the specs
affected by a set of changed files.

--]]

const FakeFileSystem = require("./Helpers/FakeFileSystem")
const RequireGraph = require("../Source/Testable/Discovery/RequireGraph")
const RequireParser = require("../Source/Testable/Discovery/RequireParser")

const LONG_OPEN = "[" .. "["
const LONG_CLOSE = "]" .. "]"
const FILES = {
    ["/root/.luaurc"] = [[{ "aliases": {
        "home": "~/Modules",
        "Lune": "~/.lune/typedefs/",
        "packages": "./Packages",
        "source": "Source"
    } }]],
    ["/root/Packages/Dependency.luau"] = "return {}",
    ["/root/Source/Library/Child.luau"] = 'return require("@source/Shared")',
    ["/root/Source/Library/init.luau"] = 'const Child = require("@self/Child")\nreturn require("./Sibling")',
    ["/root/Source/Shared.luau"] = 'const fs = require("@lune/fs")\nreturn require("@packages/Dependency")',
    ["/root/Source/Sibling.luau"] = "return {}",
    ["/root/Source/Unused.luau"] = "return {}",
    ["/root/Tests/Cycle.spec.luau"] = 'return require("./Helpers/Loop")',
    ["/root/Tests/Helpers/Loop.luau"] = 'return require("../Cycle.spec")',
    ["/root/Tests/Library.spec.luau"] = 'return require("../Source/Library")',
    ["/root/Tests/Missing.spec.luau"] = 'return require("../Source/NotYet")',
    ["/root/Tests/Nested/.luaurc"] = '{ "aliases": { "source": "./Local" } }',
    ["/root/Tests/Nested/Local/Shared.luau"] = "return {}",
    ["/root/Tests/Nested/Override.spec.luau"] = 'return require("@source/Shared"), require("@packages/Dependency")',
    ["/root/Tests/Standalone.spec.luau"] = "return function() end",
}
const SPECS = {
    "/root/Tests/Cycle.spec.luau",
    "/root/Tests/Library.spec.luau",
    "/root/Tests/Missing.spec.luau",
    "/root/Tests/Nested/Override.spec.luau",
    "/root/Tests/Standalone.spec.luau",
}

const function parse(source: string): string
    return table.concat(RequireParser.parse(source), ",")
end

const function resolve(fromFile: string, requirePath: string): string?
    return (RequireGraph.resolve(FakeFileSystem.new(FILES), fromFile, requirePath))
end

const function affected(changed: { string }): string
    const graph = RequireGraph.build(FakeFileSystem.new(FILES), SPECS)
    const names = {}
    for _, spec in RequireGraph.findAffected(graph, SPECS, changed) do
        table.insert(names, (string.gsub(spec, "^/root/Tests/", "")))
    end
    return table.concat(names, ",")
end

return function()
    describe("RequireParser.parse()", function()
        it("should find requires written with every kind of string literal", function()
            expect(parse('const A = require("./A")')).to.equal("./A")
            expect(parse("const A = require('./A')")).to.equal("./A")
            expect(parse("const A = require(`./A`)")).to.equal("./A")
            expect(parse(`const A = require({LONG_OPEN}./A{LONG_CLOSE})`)).to.equal("./A")
        end)

        it("should find requires without parentheses or with extra spacing", function()
            expect(parse('const A = require "./A"')).to.equal("./A")
            expect(parse('const A = require  (  "./A"  )')).to.equal("./A")
        end)

        it("should keep the order of first appearance without duplicates", function()
            expect(parse('require("./B")\nrequire("@self/A")\nrequire("./B")\nrequire("../C")')).to.equal(
                "./B,@self/A,../C"
            )
        end)

        it("should find requires nested inside expressions", function()
            expect(parse('const value = (require("./A") :: any).Field + require("./B").Count')).to.equal("./A,./B")
        end)

        it("should ignore requires inside comments", function()
            expect(parse('-- require("./A")\nrequire("./B")')).to.equal("./B")
            expect(parse(`--{LONG_OPEN}\nrequire("./A")\n{LONG_CLOSE}\nrequire("./B")`)).to.equal("./B")
            expect(parse('--[==[\nrequire("./A")\n]==]\nrequire("./B")')).to.equal("./B")
        end)

        it("should ignore requires mentioned inside strings", function()
            expect(parse([[const text = "require('./A')"]])).to.equal("")
            expect(parse([[const text = 'require("./A")']])).to.equal("")
            expect(parse('const text = `require("./A")`')).to.equal("")
            expect(parse(`const text = {LONG_OPEN}require("./A"){LONG_CLOSE}`)).to.equal("")
            expect(parse([[const text = "escaped \" quote require('./A')"]])).to.equal("")
        end)

        it("should not treat a quote inside a comment as the start of a string", function()
            expect(parse('-- it\'s here\nrequire("./A")')).to.equal("./A")
        end)

        it("should ignore requires whose argument is not a plain string", function()
            expect(parse("require(path)")).to.equal("")
            expect(parse('require("./A" .. suffix)')).to.equal("")
            expect(parse("require(`./{name}`)")).to.equal("")
            expect(parse("require(script.Parent.Module)")).to.equal("")
        end)

        it("should ignore other identifiers that merely contain the word", function()
            expect(parse('requireModule("./A")')).to.equal("")
            expect(parse('my_require("./A")')).to.equal("")
            expect(parse('loader.require("./A")')).to.equal("")
            expect(parse('loader:require("./A")')).to.equal("")
        end)

        it("should return the same result when called twice", function()
            const source = 'require("./A")\n-- require("./B")\nrequire("./C")'
            expect(parse(source)).to.equal(parse(source))
        end)
    end)

    describe("RequireGraph.parseAliases()", function()
        it("should read aliases with lowercase names", function()
            const aliases = RequireGraph.parseAliases(FILES["/root/.luaurc"])
            expect(aliases.lune).to.equal("~/.lune/typedefs/")
            expect(aliases.packages).to.equal("./Packages")
            expect(aliases.source).to.equal("Source")
        end)

        it("should return nothing when there is no alias table", function()
            expect(next(RequireGraph.parseAliases('{ "languageMode": "strict" }'))).to.equal(nil)
            expect(next(RequireGraph.parseAliases(""))).to.equal(nil)
        end)

        it("should not read keys outside the alias table", function()
            const aliases = RequireGraph.parseAliases('{ "aliases": { "a": "./A" }, "other": { "b": "./B" } }')
            expect(aliases.a).to.equal("./A")
            expect(aliases.b).to.equal(nil)
        end)
    end)

    describe("RequireGraph.resolve()", function()
        it("should resolve sibling and parent paths from an ordinary file", function()
            expect(resolve("/root/Tests/Cycle.spec.luau", "./Helpers/Loop")).to.equal("/root/Tests/Helpers/Loop.luau")
            expect(resolve("/root/Tests/Helpers/Loop.luau", "../Cycle.spec")).to.equal("/root/Tests/Cycle.spec.luau")
        end)

        it("should resolve a directory to its init file", function()
            expect(resolve("/root/Tests/Library.spec.luau", "../Source/Library")).to.equal(
                "/root/Source/Library/init.luau"
            )
        end)

        it("should resolve relative paths in an init file from the parent directory", function()
            expect(resolve("/root/Source/Library/init.luau", "./Sibling")).to.equal("/root/Source/Sibling.luau")
            expect(resolve("/root/Source/Library/init.luau", "../Tests/Standalone.spec")).to.equal(
                "/root/Tests/Standalone.spec.luau"
            )
        end)

        it("should resolve @self only inside an init file", function()
            expect(resolve("/root/Source/Library/init.luau", "@self/Child")).to.equal("/root/Source/Library/Child.luau")
            expect(resolve("/root/Source/Shared.luau", "@self/Sibling")).to.equal(nil)
        end)

        it("should resolve aliases from the nearest configuration file", function()
            expect(resolve("/root/Source/Library/Child.luau", "@source/Shared")).to.equal("/root/Source/Shared.luau")
            expect(resolve("/root/Tests/Nested/Override.spec.luau", "@source/Shared")).to.equal(
                "/root/Tests/Nested/Local/Shared.luau"
            )
        end)

        it("should fall back to an outer configuration file for other aliases", function()
            expect(resolve("/root/Tests/Nested/Override.spec.luau", "@packages/Dependency")).to.equal(
                "/root/Packages/Dependency.luau"
            )
        end)

        it("should match alias names without regard to case", function()
            expect(resolve("/root/Source/Shared.luau", "@Packages/Dependency")).to.equal(
                "/root/Packages/Dependency.luau"
            )
        end)

        it("should not resolve built-ins, home paths, unknown aliases, or bare names", function()
            for _, requirePath in { "@lune/fs", "@home/Module", "@unknown/Module", "Module" } do
                const resolved, candidates =
                    RequireGraph.resolve(FakeFileSystem.new(FILES), "/root/Source/Shared.luau", requirePath)
                expect(resolved).to.equal(nil)
                expect(#candidates).to.equal(0)
            end
        end)

        it("should list every candidate when a path resolves to nothing", function()
            const resolved, candidates =
                RequireGraph.resolve(FakeFileSystem.new(FILES), "/root/Tests/Missing.spec.luau", "../Source/NotYet")
            expect(resolved).to.equal(nil)
            expect(table.concat(candidates, ",")).to.equal(
                "/root/Source/NotYet.luau,/root/Source/NotYet.lua,"
                    .. "/root/Source/NotYet/init.luau,/root/Source/NotYet/init.lua"
            )
        end)

        it("should prefer a file over a directory of the same name", function()
            const fileSystem = FakeFileSystem.new({
                ["/root/A.luau"] = "",
                ["/root/A/init.luau"] = "",
                ["/root/Main.luau"] = "",
            })
            expect((RequireGraph.resolve(fileSystem, "/root/Main.luau", "./A"))).to.equal("/root/A.luau")
        end)
    end)

    describe("RequireGraph.build()", function()
        it("should follow requires transitively from the entry files", function()
            const graph = RequireGraph.build(FakeFileSystem.new(FILES), { "/root/Tests/Library.spec.luau" })
            expect(table.concat(RequireGraph.files(graph), ",")).to.equal(
                "/root/Packages/Dependency.luau,/root/Source/Library/Child.luau,/root/Source/Library/init.luau,"
                    .. "/root/Source/Shared.luau,/root/Source/Sibling.luau,/root/Tests/Library.spec.luau"
            )
        end)

        it("should sort the dependencies of each file", function()
            const graph = RequireGraph.build(FakeFileSystem.new(FILES), { "/root/Tests/Library.spec.luau" })
            expect(table.concat(graph["/root/Source/Library/init.luau"], ",")).to.equal(
                "/root/Source/Library/Child.luau,/root/Source/Sibling.luau"
            )
        end)

        it("should leave out files that nothing reachable requires", function()
            const graph = RequireGraph.build(FakeFileSystem.new(FILES), SPECS)
            expect(graph["/root/Source/Unused.luau"]).to.equal(nil)
        end)

        it("should finish when requires form a cycle", function()
            const graph = RequireGraph.build(FakeFileSystem.new(FILES), { "/root/Tests/Cycle.spec.luau" })
            expect(table.concat(graph["/root/Tests/Helpers/Loop.luau"], ",")).to.equal("/root/Tests/Cycle.spec.luau")
        end)

        it("should keep an entry file that does not exist", function()
            const graph = RequireGraph.build(FakeFileSystem.new(FILES), { "/root/Tests/Gone.spec.luau" })
            expect(#graph["/root/Tests/Gone.spec.luau"]).to.equal(0)
        end)
    end)

    describe("RequireGraph.invert()", function()
        it("should map each file to its sorted direct dependents", function()
            const dependents = RequireGraph.invert({
                ["A"] = { "C" },
                ["B"] = { "C", "D" },
                ["C"] = {},
            })
            expect(table.concat(dependents["C"], ",")).to.equal("A,B")
            expect(table.concat(dependents["D"], ",")).to.equal("B")
            expect(dependents["A"]).to.equal(nil)
        end)
    end)

    describe("RequireGraph.findAffected()", function()
        it("should select a spec that changed itself", function()
            expect(affected({ "/root/Tests/Standalone.spec.luau" })).to.equal("Standalone.spec.luau")
        end)

        it("should select specs that require a changed file directly", function()
            expect(affected({ "/root/Source/Library/init.luau" })).to.equal("Library.spec.luau")
        end)

        it("should select specs that depend on a changed file transitively", function()
            expect(affected({ "/root/Source/Shared.luau" })).to.equal("Library.spec.luau")
            expect(affected({ "/root/Packages/Dependency.luau" })).to.equal(
                "Library.spec.luau,Nested/Override.spec.luau"
            )
        end)

        it("should select nothing for files that no spec depends on", function()
            expect(affected({ "/root/Source/Unused.luau" })).to.equal("")
            expect(affected({ "/root/README.md" })).to.equal("")
            expect(affected({})).to.equal("")
        end)

        it("should select specs whose missing require was created or deleted", function()
            expect(affected({ "/root/Source/NotYet.luau" })).to.equal("Missing.spec.luau")
            expect(affected({ "/root/Source/NotYet/init.luau" })).to.equal("Missing.spec.luau")
        end)

        it("should select every spec when a configuration file changes", function()
            expect(affected({ "/root/Tests/Nested/.luaurc" })).to.equal(
                "Cycle.spec.luau,Library.spec.luau,Missing.spec.luau,Nested/Override.spec.luau,Standalone.spec.luau"
            )
        end)

        it("should handle cycles and several changes at once", function()
            expect(affected({ "/root/Tests/Helpers/Loop.luau", "/root/Source/Sibling.luau" })).to.equal(
                "Cycle.spec.luau,Library.spec.luau"
            )
        end)

        it("should normalize the changed paths before matching", function()
            expect(affected({ "/root/Tests/../Source/./Sibling.luau" })).to.equal("Library.spec.luau")
        end)
    end)
end
