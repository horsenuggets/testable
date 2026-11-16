--[[

IsolatedRun

Runs a single test module in its own Testable instance through a subprocess and parses
what the run reported. Tests use this to check pass/fail, the counts, and each test's
status and skip reason without touching the outer run's configuration.

--]]

const Subprocess = require("./Subprocess")

const SCRIPT_TEMPLATE = [[
    const process = require("@lune/process")
    const Testable = require("./Source/Testable")

    Testable.configure({ ForbidFocus = %s, Parallel = %s, PrintSkipped = %s })

    const tests = {
        {
            Name = "IsolatedModule",
            Func = function()
                %s
            end,
        },
    }

    const results, passed = Testable.run(tests)
    results:visitAllNodes(function(node)
        if node.planNode.type == "It" then
            print(`NODE|{node.planNode.phrase}|{node.status}|{node.skipReason or "-"}`)
        end
    end)
    print(`RESULT|Passed|{passed}`)
    print(`RESULT|SuccessCount|{results.successCount}`)
    print(`RESULT|FailureCount|{results.failureCount}`)
    print(`RESULT|SkippedCount|{results.skippedCount}`)
    print(`RESULT|FocusExcludedCount|{results.focusExcludedCount}`)
    print(`RESULT|ErrorCount|{#results.errors}`)
    process.exit(if passed then 0 else 1)
]]

export type Options = {
    ForbidFocus: boolean,
    Parallel: boolean,
    PrintSkipped: boolean,
}

export type NodeOutcome = {
    Reason: string?,
    Status: string,
}

export type Outcome = {
    ErrorCount: number,
    ExitedCleanly: boolean,
    FailureCount: number,
    FocusExcludedCount: number,
    Nodes: { [string]: NodeOutcome },
    Output: string,
    Passed: boolean,
    SkippedCount: number,
    SuccessCount: number,
}

const IsolatedRun = {}

--[[
    Builds the script that runs one test module with the given body and prints its
    results in a parseable form.

    @param moduleBody - The Luau source of the test module function's body
    @param options - The configuration the isolated run uses
    @return The full script source
]]
function IsolatedRun.buildScript(moduleBody: string, options: Options): string
    assert(type(moduleBody) == "string", "moduleBody must be a string")
    assert(type(options) == "table", "options must be a table")
    assert(type(options.ForbidFocus) == "boolean", "ForbidFocus must be a boolean")
    assert(type(options.Parallel) == "boolean", "Parallel must be a boolean")
    assert(type(options.PrintSkipped) == "boolean", "PrintSkipped must be a boolean")

    return string.format(
        SCRIPT_TEMPLATE,
        tostring(options.ForbidFocus),
        tostring(options.Parallel),
        tostring(options.PrintSkipped),
        moduleBody
    )
end

--[[
    Parses the output of a script built by buildScript.

    @param exitedCleanly - Whether the script exited with a zero exit code
    @param rawOutput - The combined output of the script
    @return The parsed outcome, with tests keyed by their phrase and color codes removed
        from the output
]]
function IsolatedRun.parse(exitedCleanly: boolean, rawOutput: string): Outcome
    assert(type(exitedCleanly) == "boolean", "exitedCleanly must be a boolean")
    assert(type(rawOutput) == "string", "rawOutput must be a string")

    const output = (rawOutput:gsub("\27%[[%d;]*m", ""))

    const nodes: { [string]: NodeOutcome } = {}
    const values: { [string]: string } = {}

    for line in output:gmatch("[^\r\n]+") do
        const phrase, status, reason = line:match("^NODE|(.-)|(.-)|(.*)$")
        if phrase then
            nodes[phrase] = { Reason = if reason == "-" then nil else reason, Status = status }
        end

        const key, value = line:match("^RESULT|(.-)|(.*)$")
        if key then
            values[key] = value
        end
    end

    return {
        ErrorCount = tonumber(values.ErrorCount) or -1,
        ExitedCleanly = exitedCleanly,
        FailureCount = tonumber(values.FailureCount) or -1,
        FocusExcludedCount = tonumber(values.FocusExcludedCount) or -1,
        Nodes = nodes,
        Output = output,
        Passed = values.Passed == "true",
        SkippedCount = tonumber(values.SkippedCount) or -1,
        SuccessCount = tonumber(values.SuccessCount) or -1,
    }
end

--[[
    Runs one test module in an isolated Testable instance.

    @param moduleBody - The Luau source of the test module function's body
    @param options - The configuration the isolated run uses
    @return The parsed outcome of the run
]]
function IsolatedRun.run(moduleBody: string, options: Options): Outcome
    return IsolatedRun.parse(Subprocess.runScript(IsolatedRun.buildScript(moduleBody, options)))
end

return IsolatedRun
