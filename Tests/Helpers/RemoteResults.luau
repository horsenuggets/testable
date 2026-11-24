--[[

RemoteResults

Pure parsing of what the remote test script printed while it ran inside a Roblox place.
Every check prints one "[PASS] name" or "[FAIL] name - error" line, and the script ends
with a "[DONE] count" line. Parsing the final line as well lets a run that stopped early,
or lost some of its lines, be told apart from one that simply had fewer checks.

--]]

export type TestResult = {
    Error: string?,
    Name: string,
    Passed: boolean
}

export type Parsed = {
    -- How many checks the script said it ran, or nil if it never reached its last line.
    ReportedCount: number?,
    Results: { TestResult }
}

const RemoteResults = {}

const function _formatChecks(count: number): string
    return if count == 1 then "1 check" else `{count} checks`
end

--[[
    Parses the log messages of a remote run. Messages that aren't result lines, such as
    the reports of the runs the script starts, are ignored.

    @param logs - The log messages in the order they were printed
    @return The results of the checks and the count from the final line
]]
function RemoteResults.parse(logs: { string }): Parsed
    assert(type(logs) == "table", "logs must be an array of strings")

    const parsed: Parsed = { ReportedCount = nil, Results = {} }

    for _, line in logs do
        const passName = line:match("^%[PASS%] (.+)$")
        if passName then
            table.insert(parsed.Results, { Name = passName, Passed = true })
            continue
        end

        -- The name is matched lazily, so an error that contains " - " stays whole.
        const failName, failError = line:match("^%[FAIL%] (.-) %- (.+)$")
        if failName then
            table.insert(parsed.Results, { Error = failError, Name = failName, Passed = false })
            continue
        end

        const count = line:match("^%[DONE%] (%d+)$")
        if count then
            parsed.ReportedCount = tonumber(count)
        end
    end

    return parsed
end

--[[
    Checks that a remote run finished and that every check it ran was reported.

    @param parsed - The parsed log messages
    @param taskError - The error the execution task ended with, if it failed
    @return A sentence describing what is wrong, or nil when the run is complete
]]
function RemoteResults.findProblem(parsed: Parsed, taskError: string?): string?
    assert(type(parsed) == "table", "parsed must be a table")
    assert(taskError == nil or type(taskError) == "string", "taskError must be a string or nil")

    const count = #parsed.Results
    const reportedCount = parsed.ReportedCount
    const suffix = if taskError ~= nil then ` The execution task failed with "{taskError}".` else ""

    if reportedCount == nil then
        return `The remote script stopped before it finished, after reporting {_formatChecks(count)}.{suffix}`
    end

    if reportedCount ~= count then
        return `The remote script ran {_formatChecks(reportedCount)}, but the logs hold the results of {count}.{suffix}`
    end

    if taskError ~= nil then
        return `The remote script finished, but the execution task failed with "{taskError}".`
    end

    return nil
end

return RemoteResults
