--[[

FilterArgumentsTest.spec

Tests for parsing the command-line flag that filters tests by name.

--]]

const FilterArguments = require("../Scripts/Helpers/FilterArguments")
const Testable = require("../Source/Testable")
const expect, it = Testable.expect, Testable.it

return function()
    it("should accept no arguments", function()
        const options, remaining = FilterArguments.parse({})

        expect(options.Filter).to.equal(nil)
        expect(#remaining).to.equal(0)
    end)

    it("should read the filter from a separate argument", function()
        const options, remaining = FilterArguments.parse({ "--filter", "outer runs" })

        expect(options.Filter).to.equal("outer runs")
        expect(#remaining).to.equal(0)
    end)

    it("should read the filter from an equals sign form", function()
        const options, remaining = FilterArguments.parse({ "--filter=outer=runs" })

        expect(options.Filter).to.equal("outer=runs")
        expect(#remaining).to.equal(0)
    end)

    it("should accept a filter that looks like a flag", function()
        const options, remaining = FilterArguments.parse({ "--filter", "--filter" })

        expect(options.Filter).to.equal("--filter")
        expect(#remaining).to.equal(0)
    end)

    it("should reject a filter flag without a value", function()
        for _, arguments in { { "--filter" }, { "--filter", "" }, { "--filter=" } } do
            const ok, problem = pcall(FilterArguments.parse, arguments)

            expect(ok).to.equal(false)
            expect(problem).to.equal('The "--filter" flag needs the text to filter test names by.')
        end
    end)

    it("should reject a repeated filter", function()
        const ok, problem = pcall(FilterArguments.parse, { "--filter", "one", "--filter=two" })

        expect(ok).to.equal(false)
        expect(problem).to.equal('The "--filter" flag can only be given once.')
    end)

    it("should hand back the arguments it doesn't know in their original order", function()
        const options, remaining = FilterArguments.parse({ "--bogus", "--filter", "one", "two", "--filters=three" })

        expect(options.Filter).to.equal("one")
        expect(#remaining).to.equal(3)
        expect(remaining[1]).to.equal("--bogus")
        expect(remaining[2]).to.equal("two")
        expect(remaining[3]).to.equal("--filters=three")
    end)

    it("should not change the arguments it was given", function()
        const arguments = { "--filter", "one", "two" }
        FilterArguments.parse(arguments)

        expect(#arguments).to.equal(3)
        expect(arguments[1]).to.equal("--filter")
    end)

    it("should describe the flag in its usage text", function()
        expect(FilterArguments.Usage).to.equal('[--filter "<text>"]')
    end)
end
