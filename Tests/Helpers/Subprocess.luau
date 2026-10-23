--[[

Subprocess

Runs a Luau script in a separate Lune process from the project root. Tests use this to
run their own isolated Testable instance and check its exit code and output without
affecting the outer test run.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Subprocess = {}

local scriptCounter = 0

--[[
    Writes the given script source to a uniquely named temporary file in the project
    root, runs it with Lune, and removes the file afterward.

    @param scriptContent - The Luau source of the script to run
    @return ok - True if the script exited with a zero exit code
    @return output - The combined stdout and stderr of the script
]]
function Subprocess.runScript(scriptContent: string): (boolean, string)
    assert(type(scriptContent) == "string", "scriptContent must be a string")

    scriptCounter += 1
    local projectRoot = process.cwd
    local random = math.random(100000, 999999)
    local scriptName = `_temp_test_{os.time()}_{scriptCounter}_{random}.luau`
    local scriptPath = `{projectRoot}/{scriptName}`

    fs.writeFile(scriptPath, scriptContent)

    local result = process.exec("lune", { "run", scriptName }, {
        cwd = projectRoot,
    })

    fs.removeFile(scriptPath)

    return result.ok, (result.stdout or "") .. (result.stderr or "")
end

return Subprocess
