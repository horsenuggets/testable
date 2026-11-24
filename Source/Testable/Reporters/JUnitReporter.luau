--[[

JUnitReporter

Renders test results as JUnit XML, the format CI systems read to annotate test runs. Each
spec root becomes a testsuite and each test becomes a testcase whose classname is the path
of describe blocks leading to it. Failed tests carry a failure element with the full error
text, and skipped tests carry a skipped element. A run that the focus guard failed has a
testsuite for the guard with one failed testcase, and a run that touched snapshots has a
"Snapshots" testsuite without cases whose properties hold the snapshot summary.

--]]

const ResultTree = require("./ResultTree")
const SnapshotSummary = require("../Snapshots/SnapshotSummary")
const TestEnum = require("../TestEnum")
const ATTRIBUTE_ESCAPES = {
    ["\t"] = "&#9;",
    ["\n"] = "&#10;",
    ["\r"] = "&#13;",
    ['"'] = "&quot;",
    ["&"] = "&amp;",
    ["'"] = "&apos;",
    ["<"] = "&lt;",
    [">"] = "&gt;"
}
const INDENT = "  "
const REPLACEMENT_CHARACTER = ResultTree.ReplacementCharacter
const ROOT_NAME = "Testable"
const SNAPSHOT_PROPERTY_PREFIX = "snapshots."
const SNAPSHOT_SUITE_NAME = "Snapshots"
const TEXT_ESCAPES = {
    ["\r"] = "&#13;",
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;"
}

const JUnitReporter = {}

--[[
    Replaces everything XML 1.0 can't represent, which is every control character other
    than tab, newline, and carriage return, plus the two noncharacters U+FFFE and U+FFFF.
]]
const function removeIllegalCharacters(text: string): string
    return (
        ResultTree.sanitize(text)
            :gsub("[\0-\8\11\12\14-\31]", REPLACEMENT_CHARACTER)
            :gsub("\u{FFFE}", REPLACEMENT_CHARACTER)
            :gsub("\u{FFFF}", REPLACEMENT_CHARACTER)
    )
end

--[[
    Escapes text for use inside a double-quoted XML attribute. Whitespace other than
    spaces becomes character references, since parsers would otherwise turn it into
    spaces.
]]
function JUnitReporter.escapeAttribute(text: string): string
    assert(type(text) == "string")
    return (removeIllegalCharacters(text):gsub("[\t\n\r\"&'<>]", ATTRIBUTE_ESCAPES))
end

--[[
    Escapes text for use as the content of an XML element.
]]
function JUnitReporter.escapeText(text: string): string
    assert(type(text) == "string")
    return (removeIllegalCharacters(text):gsub("[\r&<>]", TEXT_ESCAPES))
end

const function countCases(cases: { ResultTree.TestCase }): (number, number)
    local failed = 0
    local skipped = 0
    for _, case in cases do
        if case.Status == TestEnum.TestStatus.Failure then
            failed += 1
        elseif case.Status ~= TestEnum.TestStatus.Success then
            skipped += 1
        end
    end
    return failed, skipped
end

--[[
    Returns the attributes shared by the testsuites and testsuite elements. Planning
    failures are reported as failed cases, so the errors count is always zero.
]]
const function totalsAttributes(name: string, tests: number, failed: number, skipped: number, seconds: number): string
    const escapedName = JUnitReporter.escapeAttribute(name)
    const time = ResultTree.formatSeconds(seconds)
    return `name="{escapedName}" tests="{tests}" failures="{failed}" errors="0" skipped="{skipped}" time="{time}"`
end

const function appendCase(case: ResultTree.TestCase, suiteName: string, lines: { string })
    const escape = JUnitReporter.escapeAttribute
    const classname = if #case.Path > 0 then table.concat(case.Path, ResultTree.FullNameSeparator) else suiteName
    const time = ResultTree.formatSeconds(case.Duration)
    const opening = `{INDENT}{INDENT}<testcase name="{escape(case.Name)}" classname="{escape(classname)}" time="{time}"`
    if case.Status == TestEnum.TestStatus.Success then
        table.insert(lines, `{opening}/>`)
        return
    end
    table.insert(lines, `{opening}>`)
    const inner = `{INDENT}{INDENT}{INDENT}`
    if case.Status == TestEnum.TestStatus.Failure then
        const message = case.ErrorMessage or "The test failed."
        const firstLine = message:match("^[^\r\n]*") :: string
        table.insert(
            lines,
            `{inner}<failure message="{escape(firstLine)}" type="Failure">{JUnitReporter.escapeText(message)}</failure>`
        )
    elseif case.SkipReason ~= nil then
        table.insert(lines, `{inner}<skipped message="{escape(case.SkipReason)}"/>`)
    else
        table.insert(lines, `{inner}<skipped/>`)
    end
    table.insert(lines, `{INDENT}{INDENT}</testcase>`)
end

--[[
    Appends the snapshot summary as a testsuite that has no cases and carries the counts
    as properties. JUnit only allows properties inside a testsuite, and the summary
    belongs to the whole run rather than to one spec root, so it gets a suite of its own.
]]
const function appendSnapshotSuite(summary: any, lines: { string })
    const escape = JUnitReporter.escapeAttribute
    const inner = `{INDENT}{INDENT}{INDENT}`
    table.insert(lines, `{INDENT}<testsuite {totalsAttributes(SNAPSHOT_SUITE_NAME, 0, 0, 0, 0)}>`)
    table.insert(lines, `{INDENT}{INDENT}<properties>`)
    for _, entry in SnapshotSummary.counts(summary) do
        const name = `{SNAPSHOT_PROPERTY_PREFIX}{string.lower(entry.Name)}`
        table.insert(lines, `{inner}<property name="{name}" value="{entry.Value}"/>`)
    end
    for index, obsolete in summary.Obsolete do
        const name = `{SNAPSHOT_PROPERTY_PREFIX}obsolete.{index}`
        const value = `"{tostring(obsolete.Key)}" in "{tostring(obsolete.Path)}"`
        table.insert(lines, `{inner}<property name="{name}" value="{escape(value)}"/>`)
    end
    table.insert(lines, `{INDENT}{INDENT}</properties>`)
    table.insert(lines, `{INDENT}</testsuite>`)
end

--[[
    Returns the JUnit XML document for the given results without emitting anything. The
    same results always produce the same text.
]]
function JUnitReporter.format(results: any): string
    assert(type(results) == "table")
    assert(type(results.children) == "table")
    const suiteLines = {}
    local totalCases = 0
    local totalFailed = 0
    local totalSkipped = 0
    for _, suite in results.children do
        const name = ResultTree.name(suite)
        const cases = ResultTree.collectSuiteCases(suite)
        const failed, skipped = countCases(cases)
        totalCases += #cases
        totalFailed += failed
        totalSkipped += skipped
        const attributes = totalsAttributes(name, #cases, failed, skipped, ResultTree.duration(suite))
        const opening = `{INDENT}<testsuite {attributes}`
        if #cases == 0 then
            table.insert(suiteLines, `{opening}/>`)
            continue
        end
        table.insert(suiteLines, `{opening}>`)
        for _, case in cases do
            appendCase(case, name, suiteLines)
        end
        table.insert(suiteLines, `{INDENT}</testsuite>`)
    end
    if type(results.snapshotSummary) == "table" and SnapshotSummary.hasActivity(results.snapshotSummary) then
        appendSnapshotSuite(results.snapshotSummary, suiteLines)
    end

    const lines = { '<?xml version="1.0" encoding="UTF-8"?>' }
    const attributes = totalsAttributes(ROOT_NAME, totalCases, totalFailed, totalSkipped, ResultTree.duration(results))
    const opening = `<testsuites {attributes}`
    if #suiteLines == 0 then
        table.insert(lines, `{opening}/>`)
    else
        table.insert(lines, `{opening}>`)
        table.move(suiteLines, 1, #suiteLines, #lines + 1, lines)
        table.insert(lines, "</testsuites>")
    end
    return table.concat(lines, "\n")
end

return JUnitReporter
