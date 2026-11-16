--[[

ReadmeOptionsTest.spec

Keeps the options table in the README in step with the options that Config accepts, so a
new option can't be added without being documented and a removed one can't linger.

--]]

const Testable = require("../Source/Testable")
const fs = require("@lune/fs")
const expect, it = Testable.expect, Testable.it

const CONFIG_PATH = "Source/Testable/Config.luau"
const README_PATH = "README.md"

--[[
    Reads the option names out of the ConfigOptions type, which is the one place that
    lists every option, including those whose default is nil.
]]
const function readConfigOptions(): { string }
    const source = fs.readFile(CONFIG_PATH)
    const body = string.match(source, "export type ConfigOptions = (%b{})")
    assert(body ~= nil, "Config must declare the ConfigOptions type")

    const names = {}
    for name in string.gmatch(body, "\n%s+(%w+): ") do
        table.insert(names, name)
    end
    return names
end

--[[
    Reads the option names out of the first column of the README's options table, in the
    order the rows are written.
]]
const function readReadmeOptions(): { string }
    const names = {}
    for name in string.gmatch(fs.readFile(README_PATH), "\n| `(%w+)`%s+|") do
        table.insert(names, name)
    end
    return names
end

return function()
    it("should document every option that Config accepts, and nothing else", function()
        const configOptions = readConfigOptions()
        table.sort(configOptions)

        expect(#configOptions > 0).to.equal(true)
        expect(table.concat(readReadmeOptions(), ", ")).to.equal(table.concat(configOptions, ", "))
    end)
end
