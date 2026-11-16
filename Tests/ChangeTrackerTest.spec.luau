--[[

ChangeTrackerTest.spec

Tests for the pure pieces of watch mode, covering which files are watched, how two
snapshots of modification times are compared, and how bursts of changes are debounced
with an injected clock.

--]]

const ChangeTracker = require("../Source/Testable/Discovery/ChangeTracker")

const Batch = ChangeTracker.Batch

const function join(paths: { string }?): string
    return if paths == nil then "nil" else table.concat(paths, ",")
end

return function()
    describe("ChangeTracker.isWatchable()", function()
        it("should watch ordinary files", function()
            expect(ChangeTracker.isWatchable("/root", "/root/Tests/A.spec.luau")).to.equal(true)
            expect(ChangeTracker.isWatchable("/root", "/root/Source/Module.luau")).to.equal(true)
        end)

        it("should ignore hidden files and files in hidden directories", function()
            expect(ChangeTracker.isWatchable("/root", "/root/.env")).to.equal(false)
            expect(ChangeTracker.isWatchable("/root", "/root/Tests/.Hidden.luau")).to.equal(false)
            expect(ChangeTracker.isWatchable("/root", "/root/.git/Module.luau")).to.equal(false)
        end)

        it("should still watch configuration files in visible directories", function()
            expect(ChangeTracker.isWatchable("/root", "/root/.luaurc")).to.equal(true)
            expect(ChangeTracker.isWatchable("/root", "/root/Tests/.luaurc")).to.equal(true)
            expect(ChangeTracker.isWatchable("/root", "/root/.git/.luaurc")).to.equal(false)
        end)

        it("should judge hidden segments relative to the root", function()
            expect(ChangeTracker.isWatchable("/home/.worktrees/project", "/home/.worktrees/project/A.luau")).to.equal(
                true
            )
            expect(ChangeTracker.isWatchable("/home/project", "/home/Shared/A.luau")).to.equal(true)
            expect(ChangeTracker.isWatchable("/home/project", "/home/.cache/A.luau")).to.equal(false)
        end)
    end)

    describe("ChangeTracker.watchList()", function()
        it("should add the configuration file of every directory up to the root", function()
            expect(join(ChangeTracker.watchList("/root", { "/root/Tests/Nested/A.spec.luau" }))).to.equal(
                "/root/.luaurc,/root/Tests/.luaurc,/root/Tests/Nested/.luaurc,/root/Tests/Nested/A.spec.luau"
            )
        end)

        it("should always include the root configuration file", function()
            expect(join(ChangeTracker.watchList("/root", {}))).to.equal("/root/.luaurc")
        end)

        it("should drop hidden files and remove duplicates", function()
            expect(join(ChangeTracker.watchList("/root", { "/root/A.luau", "/root/./A.luau", "/root/.hidden/B.luau" }))).to.equal(
                "/root/.luaurc,/root/A.luau"
            )
        end)

        it("should watch files outside the root without their configuration files", function()
            expect(join(ChangeTracker.watchList("/root/project", { "/root/Shared/A.luau" }))).to.equal(
                "/root/Shared/A.luau,/root/project/.luaurc"
            )
        end)
    end)

    describe("ChangeTracker.diff()", function()
        it("should report nothing for identical snapshots", function()
            expect(join(ChangeTracker.diff({ A = "1/10", B = "2/10" }, { A = "1/10", B = "2/10" }))).to.equal("")
            expect(join(ChangeTracker.diff({}, {}))).to.equal("")
        end)

        it("should report created, modified, and removed files in sorted order", function()
            const previous = { Kept = "1/10", Modified = "1/10", Removed = "1/10" }
            const current = { Created = "5/10", Kept = "1/10", Modified = "2/10" }
            expect(join(ChangeTracker.diff(previous, current))).to.equal("Created,Modified,Removed")
        end)

        it("should report a file whose time is the same but whose size differs", function()
            expect(join(ChangeTracker.diff({ A = "5/10" }, { A = "5/11" }))).to.equal("A")
        end)
    end)

    describe("ChangeTracker.Batch", function()
        it("should release nothing while it is empty", function()
            const batch = Batch.new(1)
            expect(batch:Take(100)).to.equal(nil)
            batch:Add({}, 0)
            expect(batch:Take(100)).to.equal(nil)
        end)

        it("should hold changes until the debounce period has passed", function()
            const batch = Batch.new(1)
            batch:Add({ "A" }, 10)
            expect(batch:Take(10.5)).to.equal(nil)
            expect(join(batch:Take(11))).to.equal("A")
        end)

        it("should restart the debounce period on every new change", function()
            const batch = Batch.new(1)
            batch:Add({ "B" }, 10)
            batch:Add({ "A" }, 10.8)
            expect(batch:Take(11.5)).to.equal(nil)
            expect(join(batch:Take(11.8))).to.equal("A,B")
        end)

        it("should merge duplicates and empty itself once released", function()
            const batch = Batch.new(0.5)
            batch:Add({ "A", "B" }, 1)
            batch:Add({ "A" }, 1.1)
            expect(join(batch:Take(2))).to.equal("A,B")
            expect(batch:Take(3)).to.equal(nil)

            batch:Add({ "C" }, 4)
            expect(join(batch:Take(5))).to.equal("C")
        end)

        it("should release immediately with no debounce", function()
            const batch = Batch.new(0)
            batch:Add({ "A" }, 1)
            expect(join(batch:Take(1))).to.equal("A")
        end)

        it("should reject a negative debounce", function()
            expect(function()
                Batch.new(-1)
            end).to.throw()
        end)
    end)
end
