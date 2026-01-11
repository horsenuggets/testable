--[[

CheckFormatting

Verifies that all code is properly formatted using stylua.

--]]

local process = require("@lune/process")

local function checkFormatting()
    local result = process.exec("stylua", { "--check", "." })

    if result.ok then
        print("Formatting check passed!")
        process.exit(0)
    else
        print("Formatting check failed.")
        print(result.stdout)
        print(result.stderr)
        process.exit(1)
    end
end

checkFormatting()
