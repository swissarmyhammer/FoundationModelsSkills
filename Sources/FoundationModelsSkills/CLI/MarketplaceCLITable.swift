/// Lays the rows of a `marketplace` command out as columns of text
/// (marketplace.md §9.2).
///
/// `list` and `check` both show a table, thus the layout lives here one time.
internal enum MarketplaceCLITable {
    /// The text between two columns.
    private static let columnSeparator = "  "

    /// The character that makes a column as wide as its widest cell.
    private static let paddingCharacter = " "

    /// The empty text, for a cell that a short row does not hold.
    private static let missingCell = ""

    /// Lays out one heading line and one line for each row.
    ///
    /// - Parameters:
    ///   - headings: The heading of each column.
    ///   - rows: The cells of each row, in the order of the headings.
    /// - Returns: The heading line and the row lines. An empty row list gives
    ///   no line at all, thus a command with nothing to show writes nothing.
    static func lines(headings: [String], rows: [[String]]) -> [String] {
        guard !rows.isEmpty else {
            return []
        }
        let widths = widths(ofHeadings: headings, rows: rows)
        return ([headings] + rows).map { line(ofCells: $0, widths: widths) }
    }

    /// The width of each column: the widest of its heading and its cells.
    ///
    /// - Parameters:
    ///   - headings: The heading of each column.
    ///   - rows: The cells of each row.
    /// - Returns: One width for each heading.
    private static func widths(ofHeadings headings: [String], rows: [[String]]) -> [Int] {
        headings.indices.map { column in
            rows.reduce(headings[column].count) { widest, row in
                max(widest, cell(ofRow: row, atColumn: column).count)
            }
        }
    }

    /// Lays one row out as one line.
    ///
    /// The last column takes no padding, thus no line ends in a space.
    ///
    /// - Parameters:
    ///   - cells: The cells of the row.
    ///   - widths: The width of each column.
    /// - Returns: The line.
    private static func line(ofCells cells: [String], widths: [Int]) -> String {
        let lastColumn = widths.count - 1
        return widths.indices
            .map { column in
                let text = cell(ofRow: cells, atColumn: column)
                return column == lastColumn ? text : padded(text, toWidth: widths[column])
            }
            .joined(separator: columnSeparator)
    }

    /// The cell of one row in one column.
    ///
    /// - Parameters:
    ///   - cells: The cells of the row.
    ///   - column: The column.
    /// - Returns: The cell, or the empty text when the row is shorter than
    ///   the heading list.
    private static func cell(ofRow cells: [String], atColumn column: Int) -> String {
        cells.indices.contains(column) ? cells[column] : missingCell
    }

    /// Makes one cell as wide as its column.
    ///
    /// - Parameters:
    ///   - text: The cell.
    ///   - width: The width of the column.
    /// - Returns: The cell with spaces after it.
    private static func padded(_ text: String, toWidth width: Int) -> String {
        text + String(repeating: paddingCharacter, count: max(0, width - text.count))
    }
}
