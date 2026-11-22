--[[

SuiteOrderTest.spec

Verifies preferred spec ordering in the real planner and sequential executor. Suite
membership, original descriptors, snapshot ownership and default ordering stay intact.

--]]

const Subprocess = require("./Helpers/Subprocess")
const Testable = require("../Source/Testable")
const expect, it = Testable.expect, Testable.it
const PERMUTATIONS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
const EXECUTION_SCRIPT = [[
    const Testable = require("./Source/Testable")
    const permutations = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
    for _, permutation in permutations do
        const events = {}
        const roots = {}
        for _, index in permutation do
            const name = ({ "Alpha", "Beta", "Gamma" })[index]
            table.insert(roots, {
                Name = name,
                SnapshotPath = `fixtures/{name}.snap`,
                Func = function()
                    Testable.it("runs", function()
                        table.insert(events, name)
                    end)
                end,
            })
        end
        Testable.configure({
            InjectGlobals = false,
            Parallel = false,
            Reporters = {},
            SuiteOrder = { "Gamma", "Alpha" },
        })
        const results, passed = Testable.run(roots)
        assert(passed and results.successCount == 3 and results.failureCount == 0)
        assert(table.concat(events, ",") == "Gamma,Alpha,Beta")
    end
    print("Every permutation executed all three suites exactly once in preferred order.")
]]
const SNAPSHOT_SCRIPT = [[
    const Testable = require("./Source/Testable")
    const events = {}
    Testable.configure({ InjectGlobals = false, Parallel = false, Reporters = {}, SuiteOrder = { "Gamma" } })
    const bootstrap = Testable.TestBootstrap
    const discover = bootstrap.getModulesFromMultipleRoots
    bootstrap.getModulesFromMultipleRoots = function(self, roots)
        Testable.Config.SuiteOrder[1] = "Beta"
        return discover(self, roots)
    end
    const roots = {}
    for _, name in { "Alpha", "Beta", "Gamma" } do
        roots[name] = function()
            Testable.it("runs", function()
                table.insert(events, name)
            end)
        end
    end
    const results, passed = Testable.run(roots)
    assert(passed and results.successCount == 3)
    assert(table.concat(events, ",") == "Gamma,Alpha,Beta")
    print("The current run preserves its suite order across discovery configuration changes.")
]]

const function descriptor(name: string): any
    assert(type(name) == "string")
    return {
        method = function()
            it("runs", function() end)
        end,
        path = { name },
        pathStringForSorting = name:lower(),
        snapshotPath = `fixtures/{name}.snap`,
    }
end

const function planNames(plan: any): string
    assert(type(plan) == "table")
    const names = {}
    for _, node in plan.children do
        table.insert(names, node.phrase)
    end
    return table.concat(names, ",")
end

return function()
    for _, permutation in PERMUTATIONS do
        it(
            `orders the actual plan for permutation "{table.concat(permutation, ",")}" without mutating descriptors`,
            function()
                const modules = { descriptor("Alpha"), descriptor("Beta"), descriptor("Gamma") }
                const input = { modules[permutation[1]], modules[permutation[2]], modules[permutation[3]] }
                const original = table.clone(input)
                const preferred = { "Gamma", "Alpha" }
                const plan = Testable.TestPlanner.createPlan(input, nil, nil, preferred)
                expect(planNames(plan)).to.equal("Gamma,Alpha,Beta")
                expect(#plan.children).to.equal(#modules)
                for index, module in input do
                    expect(module).to.equal(original[index])
                    expect(module.pathStringForSorting).to.equal(module.path[1]:lower())
                end
                for index, module in { modules[3], modules[1], modules[2] } do
                    const node = plan.children[index]
                    expect(node.specModule).to.equal(module)
                    expect(node.specModule.method).to.equal(module.method)
                    expect(node.specModule.path).to.equal(module.path)
                    expect(node.specModule.snapshotPath).to.equal(module.snapshotPath)
                end
                expect(table.concat(preferred, ",")).to.equal("Gamma,Alpha")
                expect(planNames(Testable.TestPlanner.createPlan(input, nil, nil, preferred))).to.equal(planNames(plan))
            end
        )
    end

    it("retains alphabetical ordering when preferences are absent or empty", function()
        for _, order in { { Value = nil }, { Value = {} } } do
            const modules = { descriptor("Gamma"), descriptor("Alpha"), descriptor("Beta") }
            expect(planNames(Testable.TestPlanner.createPlan(modules, nil, nil, order.Value))).to.equal(
                "Alpha,Beta,Gamma"
            )
        end
    end)

    it("does not invent missing preferred suites or exclude unlisted suites", function()
        const modules = { descriptor("Gamma"), descriptor("Beta"), descriptor("Alpha") }
        const plan = Testable.TestPlanner.createPlan(modules, nil, nil, { "Missing", "Gamma" })
        expect(planNames(plan)).to.equal("Gamma,Alpha,Beta")
        expect(#plan.children).to.equal(3)
    end)

    it("matches original identities case-sensitively instead of renaming specs", function()
        const plan = Testable.TestPlanner.createPlan(
            { descriptor("Gamma"), descriptor("Alpha") },
            nil,
            nil,
            { "gamma" }
        )
        expect(planNames(plan)).to.equal("Alpha,Gamma")
    end)

    it("matches nested spec identities while preserving their snapshot ownership", function()
        const nested = descriptor("Inner")
        nested.path = { "Inner", "Outer" }
        nested.pathStringForSorting = "outer inner"
        const plan = Testable.TestPlanner.createPlan({ descriptor("Alpha"), nested }, nil, nil, { "Outer Inner" })
        expect(planNames(plan)).to.equal("Outer,Alpha")
        expect(plan.children[1].children[1].phrase).to.equal("Inner")
        expect(plan.children[1].children[1].specModule).to.equal(nested)
    end)

    it("executes every suite exactly once in preferred order with sequential execution", function()
        const ok, output = Subprocess.runScript(EXECUTION_SCRIPT)
        assert(ok, output)
        expect(output:find("Every permutation executed all three suites exactly once", 1, true) ~= nil).to.equal(true)
    end)

    it("keeps preferred suite failures and later suites in the verdict", function()
        const code = EXECUTION_SCRIPT:gsub(
            "table.insert%(events, name%)",
            'table.insert(events, name); if name == "Gamma" then Testable.expect(false).to.equal(true) end'
        ):gsub(
            "assert%(passed and results.successCount == 3 and results.failureCount == 0%)",
            "assert(not passed and results.successCount == 2 and results.failureCount == 1)"
        )
        const ok, output = Subprocess.runScript(code)
        assert(ok, output)
    end)

    it("snapshots the run order before discovery can mutate configuration", function()
        const ok, output = Subprocess.runScript(SNAPSHOT_SCRIPT)
        assert(ok, output)
        expect(output:find("preserves its suite order across discovery", 1, true) ~= nil).to.equal(true)
    end)
end
