--[[

DiscoveryTest.spec

Tests for spec discovery against real files in scratch directories. Covers naming and
loading discovered specs, selecting the specs affected by changed files or by a git ref,
running a pass in a child process, and watch mode.

--]]

const Config = require("../Source/Testable/Config")
const FakeFileSystem = require("./Helpers/FakeFileSystem")
const TempDirectory = require("./Helpers/TempDirectory")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const process = require("@lune/process")
const task = require("@lune/task")
const afterAll, beforeAll = Testable.afterAll, Testable.beforeAll
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const Discovery = Testable.Discovery
const Loader = Discovery.Loader
const SpecNames = Discovery.SpecNames

const CHILD_SCRIPT = [[
    const fs = require("@lune/fs")
    const process = require("@lune/process")
    const value = require("./Source/Library")
    fs.writeFile("Output.txt", value .. "|" .. table.concat(process.args, ","))
    process.exit(if value == "fail" then 1 else 0)
]]
const INCLUDE = { "Tests/**/*.spec.luau" }
const WAIT_STEP = 0.05
const WAIT_TIMEOUT = 10
const WATCH_DEBOUNCE = 0.1
const WATCH_INTERVAL = 0.05
const WATCH_SETTLE = 0.6

--[[
    Writes a small project with two specs. The first requires a library module, and the
    second requires nothing.

    @param label - A short name for the scratch directory
    @return The absolute path of the project root
]]
const function createProject(label: string): string
    const root = TempDirectory.create(label)
    TempDirectory.write(root, "Source/Library.luau", 'return "first"\n')
    TempDirectory.write(root, "Tests/Library.spec.luau", 'return require("../Source/Library")\n')
    TempDirectory.write(root, "Tests/Standalone.spec.luau", "return function() end\n")
    return root
end

const function git(root: string, arguments: { string })
    const allArguments = {
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.com",
        "-c",
        "commit.gpgsign=false",
    }
    for _, argument in arguments do
        table.insert(allArguments, argument)
    end

    const result = process.exec("git", allArguments, { cwd = root })
    if not result.ok then
        error(`Git failed while preparing a test repository. {result.stderr}`)
    end
end

--[[
    Commits everything in a project, turning it into a git repository first if it is not
    one yet.

    @param root - The project root
]]
const function commitProject(root: string)
    if not fs.isDir(`{root}/.git`) then
        git(root, { "init", "--quiet" })
    end
    git(root, { "add", "--all" })
    git(root, { "commit", "--quiet", "--message", "Update the project" })
end

--[[
    Runs a test body against its own scratch project, and removes the project afterward
    whether or not the body fails. Tests run in parallel, so they never share a project
    that any of them changes.

    @param label - A short name for the scratch directory
    @param body - The test body, which receives the project root
]]
const function withProject(label: string, body: (root: string) -> ())
    const root = createProject(label)
    const ok, message = pcall(body, root)
    TempDirectory.remove(root)

    if not ok then
        error(message, 0)
    end
end

--[[
    Writes the script that child process tests run into a project. The project also gets
    a copy of this repository's tool manifest, since the scratch directory is outside the
    repository and the tool manager picks the Lune version from the nearest manifest.

    @param root - The project root
]]
const function writeChildScript(root: string)
    TempDirectory.write(root, "Run.luau", CHILD_SCRIPT)
    TempDirectory.write(root, "rokit.toml", fs.readFile("rokit.toml"))
end

--[[
    Waits until a condition holds, failing the test if it never does.

    @param condition - Returns true once the awaited state is reached
]]
const function waitFor(condition: () -> boolean)
    const deadline = os.clock() + WAIT_TIMEOUT
    while not condition() do
        if os.clock() > deadline then
            error("The awaited condition was not reached in time.")
        end
        task.wait(WAIT_STEP)
    end
end

--[[
    Starts watching a project, recording every run and every status message.

    @param root - The project root
    @return handle - The watch handle
    @return runs - One entry per run, holding the affected specs joined with commas
    @return messages - Every status message the watcher logged
]]
const function startWatch(root: string, runOnStart: boolean)
    const runs: { string } = {}
    const messages: { string } = {}

    const handle = Discovery.watch({
        Debounce = WATCH_DEBOUNCE,
        Include = INCLUDE,
        Interval = WATCH_INTERVAL,
        Log = function(message: string)
            table.insert(messages, message)
        end,
        Root = root,
        Run = function(specFiles: { string })
            table.insert(runs, table.concat(specFiles, ","))
        end,
        RunOnStart = runOnStart,
    })

    return handle, runs, messages
end

return function()
    describe("SpecNames", function()
        it("should name a spec after its file", function()
            expect(SpecNames.shortName("Tests/ConfigTest.spec.luau")).to.equal("ConfigTest")
            expect(SpecNames.shortName("Tests/Legacy.Spec.lua")).to.equal("Legacy")
            expect(SpecNames.shortName("Tests/Plain.luau")).to.equal("Plain")
        end)

        it("should name an init spec after its directory", function()
            expect(SpecNames.shortName("Tests/Feature/init.spec.luau")).to.equal("Feature")
            expect(SpecNames.shortName("init.spec.luau")).to.equal("init")
        end)

        it("should use short names when they are unique", function()
            const names = SpecNames.assign({ "Tests/A.spec.luau", "Tests/Nested/B.spec.luau" })
            expect(names["Tests/A.spec.luau"]).to.equal("A")
            expect(names["Tests/Nested/B.spec.luau"]).to.equal("B")
        end)

        it("should fall back to paths only for the names that collide", function()
            const names = SpecNames.assign({ "Tests/A.spec.luau", "Tests/Nested/A.spec.luau", "Tests/B.spec.luau" })
            expect(names["Tests/A.spec.luau"]).to.equal("Tests/A")
            expect(names["Tests/Nested/A.spec.luau"]).to.equal("Tests/Nested/A")
            expect(names["Tests/B.spec.luau"]).to.equal("B")
        end)
    end)

    describe("Loader", function()
        it("should read the module directory out of every chunk name format", function()
            expect(Loader.moduleDirectory("/root/Packages/Testable/Loader", "/cwd")).to.equal("/root/Packages/Testable")
            expect(Loader.moduleDirectory("@/root/Packages/Loader", "/cwd")).to.equal("/root/Packages")
            expect(Loader.moduleDirectory('[string "/root/Packages/Loader"]', "/cwd")).to.equal("/root/Packages")
            expect(Loader.moduleDirectory("C:\\Project\\Packages\\Loader", "C:\\Project")).to.equal(
                "C:/Project/Packages"
            )
        end)

        it("should resolve a relative chunk name against the working directory", function()
            expect(Loader.moduleDirectory("Packages/Testable/Loader", "/cwd")).to.equal("/cwd/Packages/Testable")
            expect(Loader.moduleDirectory("@./Packages/Loader", "/cwd")).to.equal("/cwd/Packages")
        end)

        it("should build require paths relative to the module, not the working directory", function()
            const moduleDirectory = "/root/DevPackages/Testable/Discovery"
            expect(Loader.requirePath(moduleDirectory, "/root/Tests/A.spec.luau")).to.equal("../../../Tests/A.spec")
            expect(Loader.requirePath(moduleDirectory, "/root/DevPackages/Testable/Discovery/Sub/B.luau")).to.equal(
                "./Sub/B"
            )
            expect(Loader.requirePath(moduleDirectory, "/elsewhere/C.spec.lua")).to.equal(
                "../../../../elsewhere/C.spec"
            )
        end)

        it("should require an init file through its directory", function()
            expect(Loader.requirePath("/root/Packages", "/root/Tests/Feature/init.luau")).to.equal("../Tests/Feature")
            expect(Loader.requirePath("/root/Packages", "/root/Tests/Feature/init.spec.luau")).to.equal(
                "../Tests/Feature/init.spec"
            )
        end)

        it("should fail for a file on another drive", function()
            expect(function()
                Loader.requirePath("C:/Packages", "D:/Tests/A.spec.luau")
            end).to.throw("different drive")
        end)

        it("should map a symlink beneath the working directory that points back at it", function()
            -- With "/repo/Checkout" linking to "/repo", the module looks like it is inside
            -- the working directory even though its name runs through the symlink.
            const moduleDirectory = "/repo/Checkout/Source/Testable/Discovery"
            const mapping = Loader.findMapping(moduleDirectory, function(directory)
                return (string.gsub(directory, "^/repo/Checkout", "/repo"))
            end)
            const file = Loader.translate(mapping, "/repo/Tests/A.spec.luau")

            expect(mapping).to.deepEqual({ Logical = "/repo/Checkout", Physical = "/repo" })
            expect(file).to.equal("/repo/Checkout/Tests/A.spec.luau")
            expect(Loader.requirePath(moduleDirectory, file)).to.equal("../../../Tests/A.spec")
        end)

        it("should find no mapping for a module that was not reached through a symlink", function()
            const moduleDirectory = "/root/Source/Testable/Discovery"

            expect(Loader.findMapping(moduleDirectory, function(directory)
                return directory
            end)).to.equal(nil)
            expect(Loader.findMapping(moduleDirectory, function()
                return nil
            end)).to.equal(nil)
        end)

        it("should find the symlinked directory above a module", function()
            const mapping = Loader.findMapping("/links/project/Source/Testable/Discovery", function(directory)
                return (string.gsub(directory, "^/links/project", "/real/checkout"))
            end)

            expect(mapping).to.deepEqual({ Logical = "/links/project", Physical = "/real/checkout" })
        end)

        it("should not trust ancestors that only share their names", function()
            -- The symlink points at a directory with its own name, so the parents look
            -- alike without being the same directory.
            const mapping = Loader.findMapping("/links/project/Source", function(directory)
                return (string.gsub(directory, "^/links/project", "/real/project"))
            end)

            expect(mapping).to.deepEqual({ Logical = "/links/project", Physical = "/real/project" })
        end)

        it("should fall back to the module directory when no ancestor can be resolved", function()
            const moduleDirectory = "/links/project/Source"
            const mapping = Loader.findMapping(moduleDirectory, function(directory)
                return if directory == moduleDirectory then "/real/project/Source" else nil
            end)

            expect(mapping).to.deepEqual({ Logical = moduleDirectory, Physical = "/real/project/Source" })
        end)

        it("should translate files inside the symlinked directory and leave others alone", function()
            const mapping = { Logical = "/links/project", Physical = "/real/checkout" }

            expect(Loader.translate(mapping, "/real/checkout/Tests/A.spec.luau")).to.equal(
                "/links/project/Tests/A.spec.luau"
            )
            expect(Loader.translate(mapping, "/real/checkout")).to.equal("/links/project")
            expect(Loader.translate(mapping, "/real/checkout-other/A.spec.luau")).to.equal(
                "/real/checkout-other/A.spec.luau"
            )
            expect(Loader.translate(mapping, "/elsewhere/A.spec.luau")).to.equal("/elsewhere/A.spec.luau")
            expect(Loader.translate(nil, "/real/checkout/Tests/../Tests/A.spec.luau")).to.equal(
                "/real/checkout/Tests/A.spec.luau"
            )
        end)

        it("should build the require path that a symlinked launch needs", function()
            const moduleDirectory = "/links/project/Source/Testable/Discovery"
            const mapping = Loader.findMapping(moduleDirectory, function(directory)
                return (string.gsub(directory, "^/links/project", "/real/deeper/checkout"))
            end)
            const file = Loader.translate(mapping, "/real/deeper/checkout/Tests/A.spec.luau")

            expect(Loader.requirePath(moduleDirectory, file)).to.equal("../../../Tests/A.spec")
        end)

        it("should load specs when the test script is started through a symlinked absolute path", function()
            if process.os == "windows" then
                -- Creating a symlink needs elevated rights there.
                return
            end

            const directory = TempDirectory.create("symlinked_launch")
            const link = `{directory}/Checkout`
            const linked = process.exec("ln", { "-s", process.cwd, link })
            const result = process.exec(
                "lune",
                { "run", `{link}/Scripts/RunTests.exec.luau`, "Tests/ExampleTest.spec.luau" },
                { cwd = process.cwd }
            )
            if linked.ok then
                fs.removeFile(link)
            end
            TempDirectory.remove(directory)

            expect(linked.ok).to.equal(true)
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "1 passed", 1, true)).never.to.equal(nil)
        end)

        it("should load specs when the script runs through a symlink inside the working directory", function()
            if process.os == "windows" then
                -- Creating a symlink needs elevated rights there.
                return
            end

            -- The symlink is hidden so that discovery running elsewhere in this run
            -- never walks into it while it exists.
            const link = `{process.cwd}/.symlinked-checkout-{math.random(1, 1e9)}`
            const linked = process.exec("ln", { "-s", process.cwd, link })
            const result = process.exec(
                "lune",
                { "run", `{link}/Scripts/RunTests.exec.luau`, "Tests/ExampleTest.spec.luau" },
                { cwd = process.cwd }
            )
            if linked.ok then
                fs.removeFile(link)
            end

            expect(linked.ok).to.equal(true)
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "1 passed", 1, true)).never.to.equal(nil)
        end)
    end)

    describe("Discovery.findSpecs() and Discovery.discover()", function()
        local root: string

        beforeAll(function()
            root = createProject("discover")
            TempDirectory.write(root, "Tests/Nested/Deep.spec.luau", "return function() end\n")
            TempDirectory.write(root, "Tests/.Hidden.spec.luau", "return function() end\n")
            TempDirectory.write(root, "Tests/.hidden/Inner.spec.luau", "return function() end\n")
            TempDirectory.write(root, "Broken/NotAFunction.spec.luau", "return 5\n")
            TempDirectory.write(root, "Broken/Throws.spec.luau", 'error("Spec required before execution.")\n')
        end)

        afterAll(function()
            TempDirectory.remove(root)
        end)

        it("should find specs at every depth, sorted and without hidden files", function()
            expect(table.concat(Discovery.findSpecs({ Include = INCLUDE, Root = root }), ",")).to.equal(
                "Tests/Library.spec.luau,Tests/Nested/Deep.spec.luau,Tests/Standalone.spec.luau"
            )
        end)

        it("should accept absolute globs inside the root", function()
            const files = Discovery.findSpecs({ Include = { `{root}/Tests/*.spec.luau` }, Root = root })
            expect(table.concat(files, ",")).to.equal("Tests/Library.spec.luau,Tests/Standalone.spec.luau")

            const excluded = Discovery.findSpecs({
                Exclude = { `{root}/Tests/Library.spec.luau` },
                Include = { `{root}/Tests/*.spec.luau` },
                Root = root,
            })
            expect(table.concat(excluded, ",")).to.equal("Tests/Standalone.spec.luau")
        end)

        it("should honor exclude globs", function()
            const files = Discovery.findSpecs({ Exclude = { "Tests/Nested/**" }, Include = INCLUDE, Root = root })
            expect(table.concat(files, ",")).to.equal("Tests/Library.spec.luau,Tests/Standalone.spec.luau")
        end)

        it("should fail when the globs match nothing", function()
            expect(function()
                Discovery.findSpecs({ Include = { "Tests/**/*.story.luau" }, Root = root })
            end).to.throw('match "Tests/**/*.story.luau"')
            expect(function()
                Discovery.findSpecs({ Include = {}, Root = root })
            end).to.throw("No spec files")
        end)

        it("should narrow paths without loading any spec modules", function()
            expect(Discovery.findSpecs({
                Files = { "Broken/Throws.spec.luau" },
                Include = { "Broken/*.spec.luau" },
                Root = root,
            })).to.deepEqual({ "Broken/Throws.spec.luau" })
        end)

        it("should normalize and deduplicate selected paths in discovery order", function()
            const files = Discovery.findSpecs({
                Files = {
                    `{root}/Tests/Standalone.spec.luau`,
                    ".\\Tests\\Nested\\Deep.spec.luau",
                    "Tests/Nested/../Standalone.spec.luau",
                },
                Include = INCLUDE,
                Root = root,
            })
            expect(files).to.deepEqual({ "Tests/Nested/Deep.spec.luau", "Tests/Standalone.spec.luau" })
        end)

        it("should preserve an explicitly empty selection for both discovery entry points", function()
            expect(Discovery.findSpecs({ Files = {}, Include = INCLUDE, Root = root })).to.deepEqual({})
            expect(Discovery.discover({ Files = {}, Include = INCLUDE, Root = root })).to.deepEqual({})
            expect(function()
                Discovery.findSpecs({ Files = {}, Include = { "Missing/**" }, Root = root })
            end).to.throw("No spec files")
        end)

        it("should reject selected paths outside the include and exclude globs", function()
            for _, file in { "Source/Library.luau", "Tests/Standalone.spec.luau" } do
                expect(function()
                    Discovery.findSpecs({
                        Exclude = { "Tests/Standalone.spec.luau" },
                        Files = { file },
                        Include = INCLUDE,
                        Root = root,
                    })
                end).to.throw("is not a spec file matched by")
            end
        end)

        it("should validate the optional file list before matching globs", function()
            expect(function()
                Discovery.findSpecs({ Files = "Tests/Standalone.spec.luau", Include = INCLUDE, Root = root } :: any)
            end).to.throw("options.Files must be an array of paths")
        end)

        it("should load specs from outside the working directory as test roots", function()
            const testRoots =
                Discovery.discover({ Exclude = { "Tests/Library.spec.luau" }, Include = INCLUDE, Root = root })
            expect(#testRoots).to.equal(2)
            expect(testRoots[1].Name).to.equal("Deep")
            expect(testRoots[2].Name).to.equal("Standalone")
            expect(type(testRoots[1].Func)).to.equal("function")
        end)

        it("should return test roots that Testable can plan", function()
            const testRoots =
                Discovery.discover({ Files = { "Tests/Standalone.spec.luau" }, Include = INCLUDE, Root = root })
            const modules = Testable.TestBootstrap:getModulesFromMultipleRoots(testRoots)
            expect(#modules).to.equal(1)
            expect(modules[1].path[1]).to.equal("Standalone")
        end)

        it("should narrow the run to the given files, in sorted order", function()
            const testRoots = Discovery.discover({
                Files = { `{root}/Tests/Standalone.spec.luau`, "Tests/Nested/Deep.spec.luau" },
                Include = INCLUDE,
                Root = root,
            })
            expect(#testRoots).to.equal(2)
            expect(testRoots[1].Name).to.equal("Deep")
            expect(testRoots[2].Name).to.equal("Standalone")
        end)

        it("should fail for a file that the globs do not match", function()
            expect(function()
                Discovery.discover({ Files = { "Source/Library.luau" }, Include = INCLUDE, Root = root })
            end).to.throw('"Source/Library.luau" is not a spec file matched by')
        end)

        it("should fail for a spec that does not return a function", function()
            expect(function()
                Discovery.discover({ Include = { "Broken/*.spec.luau" }, Root = root })
            end).to.throw("must return a function")
        end)

        it("should fail to load a file that does not exist", function()
            expect(function()
                Discovery.load({ "Tests/Gone.spec.luau" }, root)
            end).to.throw('"Tests/Gone.spec.luau" does not exist')
        end)
    end)

    describe("Discovery.findAffected()", function()
        local root: string

        beforeAll(function()
            root = createProject("affected")
        end)

        afterAll(function()
            TempDirectory.remove(root)
        end)

        it("should select the specs that depend on a changed file", function()
            const affected = Discovery.findAffected({
                Changed = { `{root}/Source/Library.luau` },
                Include = INCLUDE,
                Root = root,
            })
            expect(table.concat(affected, ",")).to.equal("Tests/Library.spec.luau")
        end)

        it("should select nothing for an unrelated file", function()
            const affected = Discovery.findAffected({
                Changed = { `{root}/README.md` },
                Include = INCLUDE,
                Root = root,
            })
            expect(#affected).to.equal(0)
        end)
    end)

    describe("Execution dependencies", function()
        const entry = Discovery.PathUtil.join(
            Loader.moduleDirectory(debug.info(Loader.load, "s"), process.cwd),
            "../Workers/Entry.exec.luau"
        )
        const root = "/consumer/project"
        const specs = { `{root}/Tests/A.spec.luau`, `{root}/Tests/B.spec.luau` }
        const options = { Include = INCLUDE, Root = root, WorkerSetup = "Setup.luau" }

        const function sourceFiles(): { [string]: string }
            return {
                [entry] = 'require("./Runtime")\nerror("Entry loaded.")',
                [Discovery.PathUtil.join(Discovery.PathUtil.dirname(entry), "Runtime.luau")] = 'error("Runtime loaded.")',
                [specs[1]] = 'error("Spec loaded.")',
                [specs[2]] = 'error("Spec loaded.")',
                [`{root}/Setup.luau`] = 'require("./Prepare")\nerror("Setup loaded.")',
                [`{root}/Prepare.luau`] = 'require("./Deep")\nerror("Helper loaded.")',
                [`{root}/Deep.luau`] = 'error("Deep helper loaded.")',
            }
        end

        it("should scan execution graphs and list their watch candidates without loading code", function()
            const files = sourceFiles()
            const graph, watched = Discovery.buildGraph(FakeFileSystem.new(files), specs, options)
            const runtime = Discovery.PathUtil.join(Discovery.PathUtil.dirname(entry), "Runtime.luau")
            for _, changed in { entry, runtime, `{root}/Setup.luau`, `{root}/Prepare.luau`, `{root}/Deep.luau` } do
                expect(Discovery.RequireGraph.findAffected(graph, specs, { changed })).to.deepEqual(specs)
                expect(table.find(watched, changed)).never.to.equal(nil)
            end
            for _, base in { `{root}/Setup`, `{root}/Prepare`, `{root}/Deep` } do
                for _, suffix in { ".luau", ".lua", "/init.luau", "/init.lua" } do
                    const candidate = `{base}{suffix}`
                    expect(table.find(watched, candidate)).never.to.equal(nil)
                    expect(Discovery.RequireGraph.findAffected(graph, specs, { candidate })).to.deepEqual(specs)
                end
            end
            expect(Discovery.RequireGraph.findAffected(graph, specs, { `{root}/Unrelated.luau` })).to.deepEqual({})
            expect(table.find(watched, `{root}/Unrelated.luau`)).to.equal(nil)
            expect(table.find(watched, `{root}/.luaurc`)).never.to.equal(nil)
            const sorted = table.clone(watched)
            table.sort(sorted)
            expect(watched).to.deepEqual(sorted)
            const seen: { [string]: boolean } = {}
            for _, file in watched do
                expect(seen[file]).to.equal(nil)
                seen[file] = true
            end
        end)

        it("should watch explicit hidden execution files without watching ordinary hidden dependencies", function()
            const files = sourceFiles()
            files[`{root}/.Setup.luau`] = 'require("./.Prepare")'
            files[`{root}/.Prepare.luau`] = "return {}"
            files[specs[1]] = 'require("./.Ordinary")'
            files[`{root}/Tests/.Ordinary.luau`] = "return {}"
            const graph, watched = Discovery.buildGraph(FakeFileSystem.new(files), specs, {
                Include = INCLUDE,
                Root = root,
                WorkerSetup = ".Setup.luau",
            })
            for _, file in { entry, `{root}/.Setup.luau`, `{root}/.Prepare.luau` } do
                expect(table.find(watched, file)).never.to.equal(nil)
                expect(Discovery.RequireGraph.findAffected(graph, specs, { file })).to.deepEqual(specs)
            end
            expect(table.find(watched, `{root}/Tests/.Ordinary.luau`)).to.equal(nil)
        end)

        it("should resolve explicit setup extensions and init directories against a custom root", function()
            for _, setup in
                {
                    "Setup.luau",
                    "./Setup",
                    `{root}/Setup.luau`,
                    "Setup.lua",
                    "Bootstrap",
                    "Bootstrap/init.luau",
                    "Bootstrap/init.lua",
                    ".",
                    "init.luau",
                }
            do
                const files = sourceFiles()
                files[`{root}/Setup.luau`] = nil
                const isInit = setup == "." or setup == "init.luau" or string.find(setup, "Bootstrap", 1, true) ~= nil
                const setupFile = if setup == "." or setup == "init.luau"
                    then `{root}/init.luau`
                    elseif isInit then `{root}/Bootstrap/init.luau`
                    elseif setup == "Setup.lua" then `{root}/Setup.lua`
                    else `{root}/Setup.luau`
                files[setupFile] = if isInit
                    then 'require("@self/Prepare")\nerror("Setup loaded.")'
                    else 'require("./Prepare")\nerror("Setup loaded.")'
                const helper = Discovery.PathUtil.join(Discovery.PathUtil.dirname(setupFile), "Prepare.luau")
                files[helper] = 'error("Helper loaded.")'
                const graph, watched = Discovery.buildGraph(FakeFileSystem.new(files), specs, {
                    Include = INCLUDE,
                    Root = root,
                    WorkerSetup = setup,
                })
                expect(Discovery.RequireGraph.findAffected(graph, specs, { setupFile })).to.deepEqual(specs)
                expect(Discovery.RequireGraph.findAffected(graph, specs, { helper })).to.deepEqual(specs)
                expect(table.find(watched, setupFile)).never.to.equal(nil)
                expect(table.find(watched, helper)).never.to.equal(nil)
            end
        end)

        it("should track setup creation deletion and resolution priority without live watch sleeps", function()
            const files = sourceFiles()
            files[`{root}/Setup.luau`] = nil
            files[`{root}/Setup/init.luau`] = 'require("@self/Prepare")'
            files[`{root}/Setup/Prepare.luau`] = "return {}"
            for _, active in { "Setup/init.luau", "Setup.lua", "Setup.luau", "Setup.lua", "Setup/init.luau", "" } do
                files[`{root}/Setup.luau`] = if active == "Setup.luau" then 'require("./Prepare")' else nil
                files[`{root}/Setup.lua`] = if active == "Setup.lua" then 'require("./Prepare")' else nil
                files[`{root}/Setup/init.luau`] = if active ~= "" then 'require("@self/Prepare")' else nil
                const graph, watched = Discovery.buildGraph(FakeFileSystem.new(files), specs, options)
                for _, suffix in { ".luau", ".lua", "/init.luau", "/init.lua" } do
                    const candidate = `{root}/Setup{suffix}`
                    expect(table.find(watched, candidate)).never.to.equal(nil)
                    const changed = Discovery.ChangeTracker.diff({ [candidate] = "old" }, {})
                    expect(Discovery.RequireGraph.findAffected(graph, specs, changed)).to.deepEqual(specs)
                    const created = Discovery.ChangeTracker.diff({}, { [candidate] = "new" })
                    expect(Discovery.RequireGraph.findAffected(graph, specs, created)).to.deepEqual(specs)
                end
                if active ~= "" then
                    const helper = if active == "Setup/init.luau"
                        then `{root}/Setup/Prepare.luau`
                        else `{root}/Prepare.luau`
                    expect(table.find(watched, helper)).never.to.equal(nil)
                    expect(Discovery.RequireGraph.findAffected(graph, specs, { helper })).to.deepEqual(specs)
                    const dormant = if active == "Setup/init.luau"
                        then `{root}/Prepare.luau`
                        else `{root}/Setup/Prepare.luau`
                    expect(Discovery.RequireGraph.findAffected(graph, specs, { dormant })).to.deepEqual({})
                end
            end
        end)

        it("should use current setup configuration unless an explicit option overrides it", function()
            const previous = Config.WorkerSetup
            const ok, problem = pcall(function()
                const files = sourceFiles()
                files[`{root}/Other.luau`] = 'require("./OtherHelper")'
                files[`{root}/OtherHelper.luau`] = "return {}"
                Config.WorkerSetup = "Setup.luau"
                const fallback =
                    Discovery.buildGraph(FakeFileSystem.new(files), specs, { Include = INCLUDE, Root = root })
                expect(Discovery.RequireGraph.findAffected(fallback, specs, { `{root}/Deep.luau` })).to.deepEqual(specs)
                const explicit = Discovery.buildGraph(FakeFileSystem.new(files), specs, {
                    Include = INCLUDE,
                    Root = root,
                    WorkerSetup = "Other.luau",
                })
                expect(Discovery.RequireGraph.findAffected(explicit, specs, { `{root}/OtherHelper.luau` })).to.deepEqual(
                    specs
                )
                expect(Discovery.RequireGraph.findAffected(explicit, specs, { `{root}/Setup.luau` })).to.deepEqual({})
                Config.WorkerSetup = nil
                const cleared =
                    Discovery.buildGraph(FakeFileSystem.new(files), specs, { Include = INCLUDE, Root = root })
                expect(Discovery.RequireGraph.findAffected(cleared, specs, { `{root}/Setup.luau` })).to.deepEqual({})
                expect(Discovery.RequireGraph.findAffected(cleared, specs, { entry })).to.deepEqual(specs)
            end)
            Config.WorkerSetup = previous
            if not ok then
                error(problem, 0)
            end
        end)

        it("should select every spec for setup and transitive helper edits without loading them", function()
            withProject("execution_dependencies", function(root)
                TempDirectory.write(root, "Setup.luau", 'require("./Source/Prepare")\nerror("Setup loaded.")\n')
                TempDirectory.write(root, "Source/Prepare.luau", 'error("Helper loaded.")\n')
                TempDirectory.write(root, "Tests/Standalone.spec.luau", 'error("Spec loaded.")\n')
                for _, changed in { "Setup.luau", "Source/Prepare.luau" } do
                    expect(Discovery.findAffected({
                        Changed = { changed },
                        Include = INCLUDE,
                        Root = root,
                        WorkerSetup = "Setup.luau",
                    })).to.deepEqual({ "Tests/Library.spec.luau", "Tests/Standalone.spec.luau" })
                end
                expect(Discovery.findAffected({
                    Changed = { "Source/Unrelated.luau" },
                    Include = INCLUDE,
                    Root = root,
                    WorkerSetup = "Setup.luau",
                })).to.deepEqual({})
            end)
        end)

        it("should select every spec for the package actor entry even with default workers", function()
            withProject("execution_entry", function(root)
                expect(fs.isFile(entry)).to.equal(true)
                expect(Discovery.findAffected({
                    Changed = { entry },
                    Include = INCLUDE,
                    Root = root,
                })).to.deepEqual({ "Tests/Library.spec.luau", "Tests/Standalone.spec.luau" })
            end)
        end)
    end)

    describe("Discovery.findChanged()", function()
        it("should select nothing when nothing changed since the ref", function()
            withProject("unchanged", function(root)
                commitProject(root)
                expect(#Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = root })).to.equal(0)
            end)
        end)

        it("should select the specs affected by uncommitted and untracked changes", function()
            withProject("changed", function(root)
                commitProject(root)

                TempDirectory.write(root, "Source/Library.luau", 'return "second"\n')
                const afterEdit = Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = root })
                expect(table.concat(afterEdit, ",")).to.equal("Tests/Library.spec.luau")

                TempDirectory.write(root, "Tests/New.spec.luau", "return function() end\n")
                const afterCreate = Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = root })
                expect(table.concat(afterCreate, ",")).to.equal("Tests/Library.spec.luau,Tests/New.spec.luau")
            end)
        end)

        it("should select every spec for changed setup helpers and deleted setup candidates", function()
            withProject("changed_setup", function(root)
                TempDirectory.write(root, "Setup.luau", 'require("./Prepare")\nerror("Setup loaded.")\n')
                TempDirectory.write(root, "Prepare.luau", 'error("Helper loaded.")\n')
                commitProject(root)
                TempDirectory.write(root, "Prepare.luau", 'error("Edited helper loaded.")\n')
                expect(Discovery.findChanged({
                    Include = INCLUDE,
                    Ref = "HEAD",
                    Root = root,
                    WorkerSetup = "Setup.luau",
                })).to.deepEqual({ "Tests/Library.spec.luau", "Tests/Standalone.spec.luau" })
                fs.removeFile(`{root}/Setup.luau`)
                expect(Discovery.findChanged({
                    Include = INCLUDE,
                    Ref = "HEAD",
                    Root = root,
                    WorkerSetup = "Setup.luau",
                })).to.deepEqual({ "Tests/Library.spec.luau", "Tests/Standalone.spec.luau" })
            end)
        end)

        it("should select the specs that still require a renamed file", function()
            withProject("renamed", function(root)
                commitProject(root)
                git(root, { "mv", "Source/Library.luau", "Source/Renamed.luau" })

                const affected = Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = root })
                expect(table.concat(affected, ",")).to.equal("Tests/Library.spec.luau")
            end)
        end)

        it("should compare against an older commit", function()
            withProject("history", function(root)
                commitProject(root)
                TempDirectory.write(root, "Tests/Standalone.spec.luau", "return function() end -- edited\n")
                commitProject(root)

                expect(#Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = root })).to.equal(0)
                const sinceFirst = Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD~1", Root = root })
                expect(table.concat(sinceFirst, ",")).to.equal("Tests/Standalone.spec.luau")
            end)
        end)

        it("should fail for a ref that does not exist", function()
            withProject("invalid_ref", function(root)
                commitProject(root)
                expect(function()
                    Discovery.findChanged({ Include = INCLUDE, Ref = "no-such-ref", Root = root })
                end).to.throw('"no-such-ref" is not a valid git ref')
            end)
        end)

        it("should fail outside a git repository", function()
            withProject("outside", function(root)
                expect(function()
                    Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = root })
                end).to.throw("is not inside a git repository")
            end)
        end)

        it("should fail for a root that does not exist", function()
            withProject("missing_root", function(root)
                expect(function()
                    Discovery.findChanged({ Include = INCLUDE, Ref = "HEAD", Root = `{root}/Missing` })
                end).to.throw("is not a directory")
            end)
        end)
    end)

    describe("Discovery.runInChild()", function()
        it("should pass the arguments and then the spec files to the script", function()
            withProject("child_arguments", function(root)
                writeChildScript(root)
                const ok = Discovery.runInChild({
                    Arguments = { "--flag" },
                    Files = { "Tests/A.spec.luau", "Tests/B.spec.luau" },
                    Root = root,
                    Script = "Run.luau",
                })
                expect(ok).to.equal(true)
                expect(fs.readFile(`{root}/Output.txt`)).to.equal("first|--flag,Tests/A.spec.luau,Tests/B.spec.luau")
            end)
        end)

        it("should load the code that is on disk for every pass", function()
            withProject("child_fresh", function(root)
                writeChildScript(root)
                Discovery.runInChild({ Files = {}, Root = root, Script = "Run.luau" })
                expect(fs.readFile(`{root}/Output.txt`)).to.equal("first|")

                TempDirectory.write(root, "Source/Library.luau", 'return "edited"\n')
                Discovery.runInChild({ Files = {}, Root = root, Script = "Run.luau" })
                expect(fs.readFile(`{root}/Output.txt`)).to.equal("edited|")
            end)
        end)

        it("should report a failing child", function()
            withProject("child_failure", function(root)
                writeChildScript(root)
                TempDirectory.write(root, "Source/Library.luau", 'return "fail"\n')
                expect(Discovery.runInChild({ Files = {}, Root = root, Script = "Run.luau" })).to.equal(false)
            end)
        end)
    end)

    describe("Discovery.watch()", function()
        it("should run every spec at the start and then show the banner", function()
            withProject("watch_start", function(root)
                const handle, runs, messages = startWatch(root, true)
                waitFor(function()
                    return #messages >= 1
                end)
                handle.Stop()

                expect(#runs).to.equal(1)
                expect(runs[1]).to.equal("Tests/Library.spec.luau,Tests/Standalone.spec.luau")
                expect(string.find(messages[1], "Press Ctrl+C to quit.", 1, true)).to.be.ok()
            end)
        end)

        it("should run only the specs that depend on a changed file", function()
            withProject("watch_dependency", function(root)
                const handle, runs = startWatch(root, false)
                task.wait(WATCH_SETTLE)
                expect(#runs).to.equal(0)

                TempDirectory.write(root, "Source/Library.luau", 'return "second, and longer"\n')
                waitFor(function()
                    return #runs >= 1
                end)
                handle.Stop()

                expect(runs[1]).to.equal("Tests/Library.spec.luau")
            end)
        end)

        it("should debounce several quick changes into one run", function()
            withProject("watch_debounce", function(root)
                const handle, runs = startWatch(root, false)
                TempDirectory.write(root, "Source/Library.luau", 'return "second, and longer"\n')
                TempDirectory.write(root, "Tests/Standalone.spec.luau", "return function() end -- edited\n")
                waitFor(function()
                    return #runs >= 1
                end)
                task.wait(WATCH_SETTLE)
                handle.Stop()

                expect(#runs).to.equal(1)
                expect(runs[1]).to.equal("Tests/Library.spec.luau,Tests/Standalone.spec.luau")
            end)
        end)

        it("should pick up a spec that is created while watching", function()
            withProject("watch_new_spec", function(root)
                const handle, runs = startWatch(root, false)
                TempDirectory.write(root, "Tests/Nested/New.spec.luau", "return function() end\n")
                waitFor(function()
                    return #runs >= 1
                end)
                handle.Stop()

                expect(runs[1]).to.equal("Tests/Nested/New.spec.luau")
            end)
        end)

        it("should follow a require that was added while watching", function()
            withProject("watch_new_require", function(root)
                const handle, runs = startWatch(root, false)
                TempDirectory.write(root, "Source/Extra.luau", "return {}\n")
                TempDirectory.write(root, "Tests/Standalone.spec.luau", 'return require("../Source/Extra")\n')
                waitFor(function()
                    return #runs >= 1
                end)
                expect(runs[1]).to.equal("Tests/Standalone.spec.luau")

                TempDirectory.write(root, "Source/Extra.luau", "return { Edited = true }\n")
                waitFor(function()
                    return #runs >= 2
                end)
                handle.Stop()

                expect(runs[2]).to.equal("Tests/Standalone.spec.luau")
            end)
        end)

        it("should run the dependents of a file that is deleted", function()
            withProject("watch_delete", function(root)
                const handle, runs = startWatch(root, false)
                fs.removeFile(`{root}/Source/Library.luau`)
                waitFor(function()
                    return #runs >= 1
                end)
                handle.Stop()

                expect(runs[1]).to.equal("Tests/Library.spec.luau")
            end)
        end)

        it("should run every spec when the configuration file changes", function()
            withProject("watch_config", function(root)
                const handle, runs = startWatch(root, false)
                TempDirectory.write(root, ".luaurc", '{ "aliases": { "source": "./Source" } }\n')
                waitFor(function()
                    return #runs >= 1
                end)
                handle.Stop()

                expect(runs[1]).to.equal("Tests/Library.spec.luau,Tests/Standalone.spec.luau")
            end)
        end)

        it("should run every spec when a configuration file above the root changes", function()
            withProject("watch_outer_config", function(root)
                const runs: { string } = {}
                const handle = Discovery.watch({
                    Debounce = WATCH_DEBOUNCE,
                    Include = { "*.spec.luau" },
                    Interval = WATCH_INTERVAL,
                    Log = function() end,
                    Root = `{root}/Tests`,
                    Run = function(specFiles: { string })
                        table.insert(runs, table.concat(specFiles, ","))
                    end,
                    RunOnStart = false,
                })

                TempDirectory.write(root, ".luaurc", '{ "aliases": { "source": "./Source" } }\n')
                waitFor(function()
                    return #runs >= 1
                end)
                handle.Stop()

                expect(runs[1]).to.equal("Library.spec.luau,Standalone.spec.luau")
            end)
        end)

        it("should ignore hidden files and files that no spec depends on", function()
            withProject("watch_ignored", function(root)
                const handle, runs, messages = startWatch(root, false)
                TempDirectory.write(root, ".hidden.luau", "return {}\n")
                TempDirectory.write(root, "Tests/.Hidden.spec.luau", "return function() end\n")
                TempDirectory.write(root, "Source/Unrelated.luau", "return {}\n")
                task.wait(WATCH_SETTLE)
                handle.Stop()

                expect(#runs).to.equal(0)
                expect(#messages).to.equal(1)
            end)
        end)

        it("should stop running once the handle is stopped", function()
            withProject("watch_stop", function(root)
                const handle, runs = startWatch(root, false)
                handle.Stop()
                TempDirectory.write(root, "Source/Library.luau", 'return "second, and longer"\n')
                task.wait(WATCH_SETTLE)

                expect(#runs).to.equal(0)
            end)
        end)

        it("should keep watching after a run fails", function()
            withProject("watch_failure", function(root)
                const messages: { string } = {}
                local runCount = 0
                const handle = Discovery.watch({
                    Debounce = WATCH_DEBOUNCE,
                    Include = INCLUDE,
                    Interval = WATCH_INTERVAL,
                    Log = function(message: string)
                        table.insert(messages, message)
                    end,
                    Root = root,
                    Run = function()
                        runCount += 1
                        error("The pass blew up.")
                    end,
                    RunOnStart = false,
                })

                TempDirectory.write(root, "Source/Library.luau", 'return "second, and longer"\n')
                waitFor(function()
                    return runCount >= 1
                end)
                TempDirectory.write(root, "Source/Library.luau", 'return "third, and even longer"\n')
                waitFor(function()
                    return runCount >= 2
                end)
                handle.Stop()

                expect(string.find(table.concat(messages, "\n"), "The watch run failed.", 1, true)).to.be.ok()
            end)
        end)

        it("should fail to start when the globs match nothing", function()
            withProject("watch_empty", function(root)
                expect(function()
                    Discovery.watch({
                        Include = { "Tests/**/*.story.luau" },
                        Root = root,
                        Run = function() end,
                    })
                end).to.throw("No spec files")
            end)
        end)
    end)
end
