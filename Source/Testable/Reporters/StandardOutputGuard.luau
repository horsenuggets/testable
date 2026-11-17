--[[

StandardOutputGuard

Keeps standard output free for a machine-readable report. While the guard is active,
everything printed with the global print function goes to standard error instead. That
covers what tests print, verbose logging, and the text reports of any nested runs. It
can't reach code that kept its own reference to the original print function.

Only Lune has separate output streams, so the guard does nothing anywhere else.

--]]

const Ansi = require("../Ansi")

const StandardOutputGuard = {}

--[[
    Starts sending printed output to standard error and returns a function that puts
    things back. Guards can nest, as long as they are released in reverse order.

    @return release - Restores the print function that was active before the guard
]]
function StandardOutputGuard.redirect(): () -> ()
    if not Ansi.isLune() then
        return function() end
    end

    const stdio = require("@lune/stdio") :: any
    -- Scripts look up globals through the thread's global table before falling back to
    -- the built-in ones, so an entry there replaces print for every module at once.
    -- Level zero is the only way to reach that table, and the cast keeps the analyzer
    -- from flagging the call as deprecated.
    const environment = (getfenv :: any)(0)
    const previous = rawget(environment, "print")
    rawset(environment, "print", function(...: any)
        stdio.ewrite(`{stdio.format(...)}\n`)
    end)

    local released = false
    return function()
        if not released then
            released = true
            rawset(environment, "print", previous)
        end
    end
end

--[[
    Runs a callback and returns its result. When the guard is wanted, printed output is
    redirected for as long as the callback runs, and the redirect is released even when
    the callback fails, in which case the error is raised again unchanged.

    @param active - Whether to redirect printed output while the callback runs
    @param callback - The work to run
    @return The callback's result
]]
function StandardOutputGuard.run<T>(active: boolean, callback: () -> T): T
    assert(type(active) == "boolean")
    assert(type(callback) == "function")
    if not active then
        return callback()
    end
    const release = StandardOutputGuard.redirect()
    const ok, result = pcall(callback)
    release()
    if not ok then
        error(result, 0)
    end
    return result
end

return StandardOutputGuard
