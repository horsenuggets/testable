--[[

WorkerSchedulingTest.spec

Verifies deterministic worker ownership, global suite order, and transitive grouping.
Invalid input must fail rather than silently omit files.

--]]

const Scheduling = require("../Source/Testable/Workers/Scheduling")
const Testable = require("../Source/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it
const FILES = { "Z.spec.luau", "A.spec.luau", "Y.spec.luau", "B.spec.luau", "X.spec.luau", "C.spec.luau" }

const function namesFor(files: { string }): { [string]: string }
    const names = {}
    for index, path in ipairs(files) do
        names[path] = `Suite {#files - index + 1}`
    end
    return names
end

const function rejects(callback: () -> ())
    const ok, message = pcall(callback)
    expect(ok).to.equal(false)
    expect(string.find(tostring(message), "Invalid worker scheduling.", 1, true) ~= nil).to.equal(true)
end

const function assertFiles(actual: { string }, expected: { string })
    expect(#actual).to.equal(#expected)
    for index, path in ipairs(expected) do
        expect(actual[index]).to.equal(path)
    end
end

const function assertJobs(actual: { Scheduling.Job }, expected: { { string } })
    expect(#actual).to.equal(#expected)
    for index, files in ipairs(expected) do
        expect(actual[index].Id).to.equal(index)
        assertFiles(actual[index].Files, files)
    end
end

const function assertOwnership(files: { string }, jobs: { Scheduling.Job }, workers: number): { [string]: number }
    expect(#jobs <= math.min(workers, #files)).to.equal(true)
    const positions = {}
    for index, path in ipairs(files) do
        positions[path] = index
    end
    const owners = {}
    local assigned = 0
    for index, job in ipairs(jobs) do
        expect(job.Id).to.equal(index)
        expect(#job.Files > 0).to.equal(true)
        local previous = 0
        for _, path in ipairs(job.Files) do
            expect(owners[path]).to.equal(nil)
            expect(positions[path] ~= nil).to.equal(true)
            expect(positions[path] > previous).to.equal(true)
            previous = positions[path]
            owners[path] = job.Id
            assigned += 1
        end
    end
    expect(assigned).to.equal(#files)
    return owners
end

return function()
    describe("file partitioning", function()
        it("should retain caller order instead of sorting by paths or names", function()
            const jobs = Scheduling.partition(FILES, namesFor(FILES), 2, {})
            assertJobs(jobs, {
                { FILES[1], FILES[3], FILES[5] },
                { FILES[2], FILES[4], FILES[6] }
            })
            assertOwnership(FILES, jobs, 2)
        end)

        it("should assign entire groups by earliest file to the least-loaded bucket", function()
            const groups = { { FILES[6], FILES[1] }, { FILES[4], FILES[2] } }
            const jobs = Scheduling.partition(FILES, namesFor(FILES), 3, groups)
            assertJobs(jobs, {
                { FILES[1], FILES[6] },
                { FILES[2], FILES[4] },
                { FILES[3], FILES[5] }
            })
            assertOwnership(FILES, jobs, 3)
            assertJobs(Scheduling.partition(FILES, namesFor(FILES), 3, { groups[2], groups[1] }), {
                { FILES[1], FILES[6] },
                { FILES[2], FILES[4] },
                { FILES[3], FILES[5] }
            })
        end)

        it("should restore global order when components interleave in one bucket", function()
            assertJobs(Scheduling.partition(FILES, namesFor(FILES), 1, { { FILES[1], FILES[6] } }), { FILES })
        end)

        it("should union overlapping groups before assigning any file", function()
            const groups = {
                { FILES[5], FILES[6] },
                { FILES[3], FILES[5] },
                { FILES[1], FILES[3] },
                { FILES[1], FILES[1] }
            }
            assertJobs(Scheduling.partition(FILES, namesFor(FILES), 6, groups), {
                { FILES[1], FILES[3], FILES[5], FILES[6] },
                { FILES[2] },
                { FILES[4] }
            })
        end)

        it("should connect selected files through unselected paths without assigning those paths", function()
            const files = { FILES[1], FILES[4], FILES[6] }
            const names = namesFor(FILES)
            const groups = {
                { FILES[1], "AbsentOne" },
                { "AbsentTwo", FILES[6] },
                { "AbsentOne", "AbsentTwo" },
                { "AbsentThree", "AbsentFour" }
            }
            assertJobs(Scheduling.partition(files, names, 3, groups), {
                { FILES[1], FILES[6] },
                { FILES[4] }
            })
            assertOwnership(files, Scheduling.partition(files, namesFor(files), 3, groups), 3)
        end)

        it("should allow extra global names and groups unrelated to the selection", function()
            assertJobs(Scheduling.partition({ FILES[3] }, namesFor(FILES), 100, { { "Missing" } }), {
                { FILES[3] }
            })
        end)

        it("should return no jobs for empty files and still validate the remaining arguments", function()
            assertJobs(Scheduling.partition({}, {}, 4, {}), {})
            assertJobs(Scheduling.partition({}, namesFor(FILES), 4, { { "Missing" } }), {})
            rejects(function()
                Scheduling.partition({}, {}, 0, {})
            end)
            rejects(function()
                Scheduling.partition({}, {}, 1, { {} })
            end)
        end)

        it("should cap workers to selected files and emit only nonempty contiguous jobs", function()
            const files = { FILES[1], FILES[2], FILES[3] }
            assertJobs(Scheduling.partition(files, namesFor(files), 100, {}), {
                { files[1] },
                { files[2] },
                { files[3] }
            })
            assertJobs(Scheduling.partition(files, namesFor(files), 100, { files }), { files })
            assertJobs(Scheduling.partition(files, namesFor(files), 1, {}), { files })
        end)

        it("should be deterministic and preserve ownership for every four-file overlap graph", function()
            const files = { FILES[1], FILES[2], FILES[3], FILES[4] }
            const edges = { { 1, 2 }, { 1, 3 }, { 1, 4 }, { 2, 3 }, { 2, 4 }, { 3, 4 } }
            for mask = 0, 63 do
                const groups = {}
                const connected = {}
                for index = 1, 4 do
                    connected[index] = { [index] = true }
                end
                for index, edge in ipairs(edges) do
                    if bit32.band(mask, bit32.lshift(1, index - 1)) ~= 0 then
                        table.insert(groups, { files[edge[1]], files[edge[2]] })
                        connected[edge[1]][edge[2]] = true
                        connected[edge[2]][edge[1]] = true
                    end
                end
                -- Compute reachability independently of the scheduler's union-find.
                for via = 1, 4 do
                    for left = 1, 4 do
                        for right = 1, 4 do
                            if connected[left][via] and connected[via][right] then
                                connected[left][right] = true
                            end
                        end
                    end
                end
                for workers = 1, 6 do
                    const jobs = Scheduling.partition(files, namesFor(files), workers, groups)
                    const owners = assertOwnership(files, jobs, workers)
                    const repeated = Scheduling.partition(files, namesFor(files), workers, groups)
                    expect(#repeated).to.equal(#jobs)
                    for index, job in ipairs(jobs) do
                        expect(repeated[index].Id).to.equal(job.Id)
                        assertFiles(repeated[index].Files, job.Files)
                    end
                    for left = 1, 4 do
                        for right = 1, 4 do
                            if connected[left][right] then
                                expect(owners[files[left]]).to.equal(owners[files[right]])
                            elseif workers >= 4 then
                                expect(owners[files[left]] ~= owners[files[right]]).to.equal(true)
                            end
                        end
                    end
                end
            end
        end)

        it("should not mutate or alias input tables or another partition's output", function()
            const files = table.freeze(table.clone(FILES))
            const names = table.freeze(namesFor(files))
            const group = table.freeze({ files[6], files[1] })
            const groups = table.freeze({ group })
            const first = Scheduling.partition(files, names, 2, groups)
            const second = Scheduling.partition(files, names, 2, groups)
            expect(first ~= second).to.equal(true)
            for index, job in ipairs(first) do
                expect(job ~= second[index]).to.equal(true)
                expect(job.Files ~= second[index].Files).to.equal(true)
                expect(job.Files ~= files and job.Files ~= group).to.equal(true)
            end
            const original = second[1].Files[1]
            first[1].Files[1] = "Changed"
            first[1].Id = 99
            expect(second[1].Files[1]).to.equal(original)
            expect(second[1].Id).to.equal(1)
            assertFiles(files, FILES)
            expect(names[files[1]]).to.equal("Suite 6")
            assertFiles(group, { files[6], files[1] })
        end)
    end)

    describe("input validation", function()
        const malformedArrays: { any } = {
            false,
            "array",
            { [2] = "A" },
            { [1] = "A", [3] = "B" },
            { [2] = "A", [3] = "B", [4] = "C", [6] = "D" },
            { [0] = "A" },
            { [-1] = "A" },
            { [1.5] = "A" },
            { [math.huge] = "A" },
            { Key = "A" },
            { "A", Key = "B" },
            setmetatable({}, {
                __index = function()
                    return "A"
                end
            })
        }
        for index, value in ipairs(malformedArrays) do
            it(`should reject malformed file array {index}`, function()
                rejects(function()
                    Scheduling.partition(value, { A = "Suite A", B = "Suite B", C = "Suite C", D = "Suite D" }, 1, {})
                end)
            end)
            it(`should reject malformed outer group array {index}`, function()
                rejects(function()
                    Scheduling.partition({}, {}, 1, value)
                end)
            end)
            it(`should reject malformed inner group array {index}`, function()
                rejects(function()
                    Scheduling.partition({}, {}, 1, { value })
                end)
            end)
        end

        const invalidWorkers: { any } = { 0, -1, 1.5, math.huge, -math.huge, 0 / 0, "2", false }
        for index, workers in ipairs(invalidWorkers) do
            it(`should reject invalid worker count {index}`, function()
                rejects(function()
                    Scheduling.partition({}, {}, workers :: any, {})
                end)
            end)
        end

        const invalidNames: { any } = {
            false,
            {},
            { A = "" },
            { A = false },
            { A = "Same", B = "Same" },
            { ["A"] = "Suite A", [""] = "Empty path" },
            { ["A"] = "Suite A", [1] = "Numeric path" },
            setmetatable({}, { __index = { A = "Suite A" } })
        }
        for index, names in ipairs(invalidNames) do
            it(`should reject invalid or incomplete names {index}`, function()
                rejects(function()
                    Scheduling.partition({ "A" }, names, 1, {})
                end)
            end)
        end

        for index, files in ipairs({ { "" }, { false }, { 123 }, { "A", "A" } }) do
            it(`should reject invalid file contents {index}`, function()
                rejects(function()
                    Scheduling.partition(files :: any, { A = "Suite A" }, 1, {})
                end)
            end)
        end

        for index, group in ipairs({ {}, { "" }, { false }, { 123 } }) do
            it(`should reject invalid ownership group contents {index}`, function()
                rejects(function()
                    Scheduling.partition({}, {}, 1, { group } :: any)
                end)
            end)
        end
    end)
end
