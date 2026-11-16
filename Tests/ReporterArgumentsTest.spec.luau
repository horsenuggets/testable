--[[

ReporterArgumentsTest.spec

Tests for parsing the reporter flags of the test script into configuration options.

--]]

const Config = require("../Source/Testable/Config")
const ReporterArguments = require("../Scripts/Helpers/ReporterArguments")
const ReporterSelection = require("../Source/Testable/Reporters/ReporterSelection")
const Testable = require("../Source/Testable")
const expect, it = Testable.expect, Testable.it

const function failure(arguments: { string }): string?
    const ok, message = pcall(ReporterArguments.parse, arguments)
    return if ok then nil else tostring(message)
end

return function()
    it("should change nothing without flags", function()
        const options, remaining = ReporterArguments.parse({})
        expect(options.Reporters).to.equal(nil)
        expect(options.SlowestTests).to.equal(nil)
        expect(next(options.ReporterOutputs)).to.equal(nil)
        expect(#remaining).to.equal(0)
    end)

    it("should map reporter names without regard to case", function()
        const options = ReporterArguments.parse({
            "--reporter",
            "text",
            "--reporter",
            "JSON",
            "--reporter",
            "junit",
            "--reporter",
            "Lcov",
        })
        const reporters = options.Reporters :: { string }
        expect(table.concat(reporters, ",")).to.equal("Text,Json,JUnit,Lcov")
    end)

    it("should attach each output path to the reporter before it", function()
        const options = ReporterArguments.parse({
            "--reporter",
            "json",
            "--output",
            "results.json",
            "--reporter",
            "text",
            "--reporter",
            "junit",
            "--output",
            "reports/junit.xml",
        })
        expect(options.ReporterOutputs.Json).to.equal("results.json")
        expect(options.ReporterOutputs.JUnit).to.equal("reports/junit.xml")
        expect(options.ReporterOutputs.Text).to.equal(nil)
    end)

    it("should parse the slowest tests count", function()
        expect(ReporterArguments.parse({ "--slowest", "5" }).SlowestTests).to.equal(5)
        expect(ReporterArguments.parse({ "--slowest", "0" }).SlowestTests).to.equal(0)
    end)

    it("should hand back the arguments it doesn't know in order", function()
        const options, remaining = ReporterArguments.parse({ "first", "--reporter", "json", "--other", "last" })
        expect(table.concat(remaining, ",")).to.equal("first,--other,last")
        expect((options.Reporters :: { string })[1]).to.equal("Json")
    end)

    it("should produce options that Config and the selection accept", function()
        const options = ReporterArguments.parse({ "--reporter", "json", "--output", "results.json", "--slowest", "3" })
        Config.set(options :: any)
        const selection = ReporterSelection.resolve(Config.Reporters, Config.ReporterOutputs)
        const slowestTests = Config.SlowestTests
        Config.reset()
        expect(selection.Text).to.equal(false)
        expect(selection.Outputs[1].Reporter).to.equal("Json")
        expect(selection.Outputs[1].Path).to.equal("results.json")
        expect(slowestTests).to.equal(3)
    end)

    it("should reject an unknown or missing reporter name", function()
        expect(failure({ "--reporter", "tap" })).to.equal(
            'The "--reporter" flag needs "text", "json", "junit", or "lcov", but got "tap".'
        )
        expect(failure({ "--reporter" })).to.equal(
            'The "--reporter" flag needs "text", "json", "junit", or "lcov", but got "".'
        )
    end)

    it("should reject an output path that has no reporter to belong to", function()
        expect(failure({ "--output", "results.json" })).to.equal(
            'The "--output" flag must come after the "--reporter" flag it belongs to.'
        )
        expect(failure({ "--reporter", "json", "--output" })).to.equal('The "--output" flag needs a file path.')
        expect(failure({ "--reporter", "text", "--output", "report.txt" })).to.equal(
            'The "text" reporter always writes to standard output, so it can\'t take "--output".'
        )
        expect(failure({ "--reporter", "json", "--output", "a.json", "--output", "b.json" })).to.equal(
            'The "json" reporter was given more than one "--output" path.'
        )
    end)

    it("should reject a slowest tests count that isn't a whole number", function()
        for _, value in { "-1", "1.5", "many" } do
            expect(failure({ "--slowest", value })).to.equal(
                `The "--slowest" flag needs a whole number of tests, but got "{value}".`
            )
        end
        expect(failure({ "--slowest" }) ~= nil).to.equal(true)
    end)

    it("should return equal options for equal arguments", function()
        const arguments = { "--reporter", "junit", "--output", "junit.xml", "--slowest", "2" }
        const first = ReporterArguments.parse(arguments)
        const second = ReporterArguments.parse(arguments)
        expect(table.concat(first.Reporters :: { string }, ",")).to.equal(
            table.concat(second.Reporters :: { string }, ",")
        )
        expect(first.ReporterOutputs.JUnit).to.equal(second.ReporterOutputs.JUnit)
        expect(first.SlowestTests).to.equal(second.SlowestTests)
        expect(#arguments).to.equal(6)
    end)
end
