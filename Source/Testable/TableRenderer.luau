--[[

TableRenderer

Formats bordered terminal tables with separate raw cell content for ANSI-safe alignment.

--]]

const Ansi = require("./Ansi")

const TableRenderer = {}

export type TableRow = {
    Colored: { string },
    Raw: { string },
    Separator: boolean?,
}

function TableRenderer.format(headers: { string }, rows: { TableRow }, color: boolean): { string }
    assert(type(headers) == "table")
    assert(type(rows) == "table")
    assert(type(color) == "boolean")
    const widths = {}
    for index, header in headers do
        widths[index] = utf8.len(header) or #header
    end
    for _, row in rows do
        for index, cell in row.Raw do
            widths[index] = math.max(widths[index], utf8.len(cell) or #cell)
        end
    end
    const function border(left: string, middle: string, right: string): string
        const parts = {}
        for _, width in widths do
            table.insert(parts, string.rep("─", width + 2))
        end
        return `{left}{table.concat(parts, middle)}{right}`
    end
    const function cells(values: { string }, raw: { string }): string
        const parts = {}
        for index, value in values do
            const padding = string.rep(" ", widths[index] - (utf8.len(raw[index]) or #raw[index]))
            table.insert(parts, ` {value}{padding} `)
        end
        return `│{table.concat(parts, "│")}│`
    end
    const styledHeaders = {}
    for _, header in headers do
        table.insert(styledHeaders, if color then Ansi.bold(header) else header)
    end
    const lines = {
        border("┌", "┬", "┐"),
        cells(styledHeaders, headers),
        border("├", "┼", "┤"),
    }
    for _, row in rows do
        if row.Separator then
            table.insert(lines, border("├", "┼", "┤"))
        end
        table.insert(lines, cells(if color then row.Colored else row.Raw, row.Raw))
    end
    table.insert(lines, border("└", "┴", "┘"))
    return lines
end

return TableRenderer
