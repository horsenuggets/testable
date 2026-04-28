--[[

TableRenderer

Renders bordered terminal tables with support for colored cell content and separate raw
text for width calculation. Adapted from rbxstudio-cli's TableHelpers.

--]]

local Ansi = require("./Ansi")

local IS_LUNE = Ansi.isLune()

local TableRenderer = {}

export type TableRow = {
    Raw: { string },
    Colored: { string },
    Separator: boolean?,
}

--[[
    Renders a bordered table to stdout with auto-sized columns.

    @param headers - Column header strings (rendered bold in Lune)
    @param rows - Array of TableRow entries with Raw (for width) and Colored (for display)
]]
function TableRenderer.render(headers: { string }, rows: { TableRow })
    local widths = {}
    for i, header in headers do
        widths[i] = #header
    end
    for _, row in rows do
        for i, cell in row.Raw do
            widths[i] = math.max(widths[i] or 0, #cell)
        end
    end

    local function border(left: string, mid: string, right: string): string
        local parts = {}
        for _, w in widths do
            table.insert(parts, string.rep("─", w + 2))
        end
        return `{left}{table.concat(parts, mid)}{right}`
    end

    local function formatCells(cells: { string }, rawCells: { string }): string
        local parts = {}
        for i, cell in cells do
            local rawLen = #(rawCells[i] or "")
            local padding = string.rep(" ", (widths[i] or 0) - rawLen)
            table.insert(parts, ` {cell}{padding} `)
        end
        return `│{table.concat(parts, "│")}│`
    end

    local boldHeaders = {}
    for _, h in headers do
        table.insert(boldHeaders, if IS_LUNE then Ansi.bold(h) else h)
    end

    print(border("┌", "┬", "┐"))
    print(formatCells(boldHeaders, headers))
    print(border("├", "┼", "┤"))
    for _, row in rows do
        if row.Separator then
            print(border("├", "┼", "┤"))
        end
        print(formatCells(row.Colored, row.Raw))
    end
    print(border("└", "┴", "┘"))
end

return TableRenderer
