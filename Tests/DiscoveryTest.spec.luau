--[[

DiscoveryTest.spec

Tests for spec discovery against real files in scratch directories. Covers naming and
loading discovered specs, selecting the specs affected by changed files or by a git ref,
running a pass in a child process, and watch mode.

--]]

const TempDirectory = require("./Helpers/TempDirectory")
const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const process = require("@lune/process")
const task = require("@lune/task")

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
    end)

    describe("Discovery.findSpecs() and Discovery.discover()", function()
        local root: string

        beforeAll(function()
            root = createProject("discover")
            TempDirectory.write(root, "Tests/Nested/Deep.spec.luau", "return function() end\n")
            TempDirectory.write(root, "Tests/.Hidden.spec.luau", "return function() end\n")
            TempDirectory.write(root, "Tests/.hidden/Inner.spec.luau", "return function() end\n")
            TempDirectory.write(root, "Broken/NotAFunction.spec.luau", "return 5\n")
        end)

        afterAll(function()
            TempDirectory.remove(root)
        end)

        it("should find specs at every depth, sorted and without hidden files", function()
            expect(table.concat(Discovery.findSpecs({ Include = INCLUDE, Root = root }), ",")).to.equal(
                "Tests/Library.spec.luau,Tests/Nested/Deep.spec.luau,Tests/Standalone.spec.luau"
            )
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
                TempDirectory.write(root, "Run.luau", CHILD_SCRIPT)
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
                TempDirectory.write(root, "Run.luau", CHILD_SCRIPT)
                Discovery.runInChild({ Files = {}, Root = root, Script = "Run.luau" })
                expect(fs.readFile(`{root}/Output.txt`)).to.equal("first|")

                TempDirectory.write(root, "Source/Library.luau", 'return "edited"\n')
                Discovery.runInChild({ Files = {}, Root = root, Script = "Run.luau" })
                expect(fs.readFile(`{root}/Output.txt`)).to.equal("edited|")
            end)
        end)

        it("should report a failing child", function()
            withProject("child_failure", function(root)
                TempDirectory.write(root, "Run.luau", CHILD_SCRIPT)
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
