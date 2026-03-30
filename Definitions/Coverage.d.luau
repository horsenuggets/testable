--[[

Coverage

Type definitions for debug.getcoverage and debug.iscoverageenabled.
These functions are added by the Lune fork and are not part of the
standard Luau debug library.

--]]

export type CoverageEntry = {
    Function: string,
    LineDefined: number,
    Depth: number,
    Hits: { number },
}

declare debug: {
    info: (...any) -> ...any,
    traceback: ((string?, number?) -> string) & ((thread, string?, number?) -> string),
    getcoverage: (fn: (...any) -> ...any) -> { CoverageEntry },
    iscoverageenabled: () -> boolean,
}
