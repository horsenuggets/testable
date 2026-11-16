--[[

ReporterSelection

Decides which reporters run and where each one's output goes, then renders and delivers
the machine-readable reports. The decision is a pure function of the configured reporter
names and output paths, and delivery goes through sinks that tests can replace, so the
only real I/O is the default sinks at the edge.

Standard output carries one report at most. The text report always goes there, so a
machine-readable reporter can only use it when the text reporter is off and no other
machine-readable reporter wants it too. Every other reporter needs an output path.

--]]

const Ansi = require("../Ansi")
const JUnitReporter = require("./JUnitReporter")
const JsonReporter = require("./JsonReporter")
const LcovReporter = require("./LcovReporter")
const TestEnum = require("../TestEnum")
const Reporter = TestEnum.Reporter

-- A machine-readable report and the file it's written to. Without a path it goes to
-- standard output.
export type Output = {
    Path: string?,
    Reporter: string,
}

export type Selection = {
    NeedsCoverage: boolean,
    Outputs: { Output },
    Text: boolean,
}

-- Where rendered reports are delivered.
export type Sinks = {
    Print: (contents: string) -> (),
    WriteFile: (path: string, contents: string) -> (),
}

const ReporterSelection = {}

--[[
    Turns the configured reporter names and output paths into a selection, in the order
    the reporters were listed. Paths for reporters that aren't selected are ignored, so a
    path can stay configured while its reporter is switched off.

    @param reporters - The reporter names to run
    @param outputs - Output file paths keyed by reporter name
    @return The reporters to run and where their output goes
]]
function ReporterSelection.resolve(reporters: { string }, outputs: { [string]: string }): Selection
    assert(type(reporters) == "table", "Reporters must be an array of reporter names")
    assert(type(outputs) == "table", "ReporterOutputs must be a table of paths keyed by reporter name")
    for name, path in outputs do
        if Reporter[name] == nil then
            error(`ReporterOutputs has a path for "{name}", which is not a reporter.`)
        elseif name == Reporter.Text then
            error('The "Text" reporter always writes to standard output, so it can\'t have an output path.')
        elseif type(path) ~= "string" or path == "" then
            error(`The output path of the "{name}" reporter must be a non-empty string.`)
        end
    end

    const selection: Selection = { NeedsCoverage = false, Outputs = {}, Text = false }
    const seen: { [string]: boolean } = {}
    const reporterByPath: { [string]: string } = {}
    local standardOutputReporter: string? = nil
    for _, name in reporters do
        if type(name) ~= "string" or Reporter[name] == nil then
            error(`"{name}" is not a reporter. Use "JUnit", "Json", "Lcov", or "Text".`)
        elseif seen[name] then
            error(`The "{name}" reporter is listed more than once.`)
        end
        seen[name] = true
        if name == Reporter.Text then
            selection.Text = true
            continue
        end
        if name == Reporter.Lcov then
            selection.NeedsCoverage = true
        end
        const path = outputs[name]
        if path == nil then
            if standardOutputReporter ~= nil then
                error(
                    `The "{standardOutputReporter}" and "{name}" reporters would both write to standard output. `
                        .. "Give at least one of them a path in ReporterOutputs."
                )
            end
            standardOutputReporter = name
        elseif reporterByPath[path] ~= nil then
            error(`The "{reporterByPath[path]}" and "{name}" reporters would both write to "{path}".`)
        else
            reporterByPath[path] = name
        end
        table.insert(selection.Outputs, { Path = path, Reporter = name })
    end
    if selection.Text and standardOutputReporter ~= nil then
        error(
            `The "Text" and "{standardOutputReporter}" reporters would both write to standard output. `
                .. `Give the "{standardOutputReporter}" reporter a path in ReporterOutputs, or leave "Text" out.`
        )
    end
    return selection
end

--[[
    Renders one machine-readable report as a string.

    @param reporter - The name of a machine-readable reporter
    @param results - The test results
    @param coverageReport - The coverage report, which only the "Lcov" reporter needs
    @return The rendered report
]]
function ReporterSelection.render(reporter: string, results: any, coverageReport: any?): string
    assert(type(reporter) == "string")
    assert(type(results) == "table")
    if reporter == Reporter.Json then
        return JsonReporter.format(results)
    elseif reporter == Reporter.JUnit then
        return JUnitReporter.format(results)
    elseif reporter == Reporter.Lcov then
        if coverageReport == nil then
            error('The "Lcov" reporter needs coverage data, but none was collected.')
        end
        return LcovReporter.format(coverageReport)
    end
    error(`"{reporter}" is not a machine-readable reporter.`)
end

const function writeFile(path: string, contents: string)
    if not Ansi.isLune() then
        error(`Can't write "{path}" because reporters can only write files in Lune.`)
    end
    -- Required here so that Roblox never loads a module that needs the filesystem.
    const FileWriter = require("./FileWriter") :: any
    FileWriter.write(path, contents)
end

const DEFAULT_SINKS: Sinks = { Print = print, WriteFile = writeFile }

--[[
    Renders every machine-readable report in the selection and delivers it to its file,
    or to standard output when it has no path.

    @param selection - The selection from ReporterSelection.resolve
    @param results - The test results
    @param coverageReport - The coverage report, if coverage was collected
    @param sinks - Replacements for printing and file writing, used by tests
]]
function ReporterSelection.emit(selection: Selection, results: any, coverageReport: any?, sinks: Sinks?)
    assert(type(selection) == "table")
    assert(type(results) == "table")
    assert(sinks == nil or type(sinks) == "table")
    const resolvedSinks = sinks or DEFAULT_SINKS
    for _, output in selection.Outputs do
        const contents = ReporterSelection.render(output.Reporter, results, coverageReport)
        if output.Path ~= nil then
            resolvedSinks.WriteFile(output.Path, contents)
        else
            resolvedSinks.Print(contents)
        end
    end
end

return ReporterSelection
