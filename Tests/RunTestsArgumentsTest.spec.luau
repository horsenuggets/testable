--[[

RunTestsArgumentsTest.spec

Tests for parsing the command line arguments of the RunTests script.

--]]

const RunTestsArguments = require("../Scripts/Helpers/RunTestsArguments")

return function()
    it("should accept no arguments", function()
        const arguments, problem = RunTestsArguments.parse({})

        assert(arguments ~= nil, "arguments should have parsed")
        expect(arguments.Filter).to.equal(nil)
        expect(problem).to.equal(nil)
    end)

    it("should read the filter from a separate argument", function()
        const arguments = RunTestsArguments.parse({ "--filter", "outer runs" })

        assert(arguments ~= nil, "arguments should have parsed")
        expect(arguments.Filter).to.equal("outer runs")
    end)

    it("should read the filter from an equals sign form", function()
        const arguments = RunTestsArguments.parse({ "--filter=outer=runs" })

        assert(arguments ~= nil, "arguments should have parsed")
        expect(arguments.Filter).to.equal("outer=runs")
    end)

    it("should accept a filter that looks like a flag", function()
        const arguments = RunTestsArguments.parse({ "--filter", "--verbose" })

        assert(arguments ~= nil, "arguments should have parsed")
        expect(arguments.Filter).to.equal("--verbose")
    end)

    it("should reject a filter flag without a value", function()
        for _, args in { { "--filter" }, { "--filter", "" }, { "--filter=" } } do
            const arguments, problem = RunTestsArguments.parse(args)

            expect(arguments).to.equal(nil)
            expect(problem).to.equal('The "--filter" option needs the text to filter test names by.')
        end
    end)

    it("should reject a repeated filter", function()
        const arguments, problem = RunTestsArguments.parse({ "--filter", "one", "--filter=two" })

        expect(arguments).to.equal(nil)
        expect(problem).to.equal('The "--filter" option can only be given once.')
    end)

    it("should reject unrecognized arguments", function()
        for _, args in { { "--bogus" }, { "outer" }, { "--filter", "one", "two" }, { "--filters=one" } } do
            const arguments, problem = RunTestsArguments.parse(args)

            expect(arguments).to.equal(nil)
            expect((problem :: string):find("is not recognized.", 1, true) ~= nil).to.equal(true)
        end
    end)

    it("should describe the filter option in the usage line", function()
        expect(RunTestsArguments.Usage).to.equal('[Usage] ./Scripts/RunTests.exec.luau [--filter "<text>"]')
    end)
end
