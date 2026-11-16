--[[

TrackedModule

A coverage fixture that tests load with luau.load and register through Coverage.track,
the way sandboxes load modules outside of require.

--]]

const TrackedModule = {}

function TrackedModule.classify(value: number): string
    if value > 0 then
        return "positive"
    end
    return "other"
end

function TrackedModule.unused(): string
    return "never called"
end

return TrackedModule
