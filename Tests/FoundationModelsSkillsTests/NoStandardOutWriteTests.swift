import Foundation
import Testing

/// Guards the `no_direct_standard_out_logs` rule of the code hygiene gate: no
/// line of this package, and no line of its example, writes to a standard
/// stream with `print`, `debugPrint`, `dump` or `_printChanges`. Every line
/// goes through `StandardStream`, the one line writer.
///
/// The suite reads every Swift file under `Sources/` and
/// `Examples/skills-demo/`, found from this file's `#filePath`, and reports
/// each line that calls one of the four. A call is the name of one of the
/// four and the `(` that opens its arguments, with no letter, number or
/// underscore before the name. Thus `sprint(x)` and `printableLine(x)` are
/// not reported. A comment line holds no code, thus the walk passes over it,
/// the way the `match_kinds: [identifier]` key of the rule itself does.
@Suite("No standard out write")
struct NoStandardOutWriteTests {
    /// The calls that no line of code may hold. Each one is a name and the
    /// `(` that opens its arguments.
    private static let disallowedCalls = ["print(", "debugPrint(", "dump(", "_printChanges("]

    /// The text that opens a comment line.
    private static let commentMarker = "//"

    /// The suffix of a Swift source file.
    private static let swiftFileSuffix = ".swift"

    /// The number of the first line of a file.
    private static let firstLineNumber = 1

    @Test(arguments: [
        "print(\"hello\")",
        "debugPrint(value)",
        "dump(value)",
        "Self._printChanges()",
        "        print(\"indented\")",
    ])
    func aLineThatCallsOneOfTheFourIsReported(line: String) {
        #expect(Self.disallowedCallLines(in: line) == [Self.firstLineNumber])
    }

    @Test(arguments: [
        "Self.printableLine(of: text)",
        "sprintDistance()",
        "StandardStream.output.write(line: text)",
        "// print(\"a comment holds no code\")",
        "/// The one writer, which `dump(_:)` never replaces.",
    ])
    func aLineThatCallsNoneOfTheFourIsNotReported(line: String) {
        #expect(Self.disallowedCallLines(in: line).isEmpty)
    }

    @Test func theReportedLineNumberCountsFromOne() {
        let text = """
            StandardStream.output.write(line: text)
            let value = registry.roots
            dump(value)
            """

        #expect(Self.disallowedCallLines(in: text) == [3])
    }

    @Test(arguments: ["Sources", "Examples/skills-demo"])
    func noFileOfTheDirectoryWritesToAStandardStreamWithACall(directory: String) throws {
        let root = FixtureLibrary.packageRoot().appendingPathComponent(directory, isDirectory: true)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(Self.swiftFileSuffix) }

        let offenders = try files.flatMap { relativePath in
            let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            return Self.disallowedCallLines(in: text).map { "\(directory)/\(relativePath):\($0)" }
        }

        #expect(!files.isEmpty, "the walk found no Swift file under \(root.path), thus it proves nothing")
        #expect(
            offenders.isEmpty,
            """
            No file may write to a standard stream with print, debugPrint, dump or _printChanges. Write \
            each line with StandardStream; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Finds each line of `text` that calls one of the four.
    ///
    /// - Parameter text: The source text to read.
    /// - Returns: The number of each reported line. The first line is 1.
    private static func disallowedCallLines(in text: String) -> [Int] {
        text.components(separatedBy: .newlines).enumerated()
            .filter { !isComment($0.element) && callsOneOfTheFour($0.element) }
            .map { $0.offset + firstLineNumber }
    }

    /// Tells whether `line` opens with the comment marker.
    private static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(commentMarker)
    }

    /// Tells whether `line` holds a call to one of the four.
    private static func callsOneOfTheFour(_ line: String) -> Bool {
        disallowedCalls.contains { holds(call: $0, in: line) }
    }

    /// Tells whether `line` holds `call` where a name starts.
    ///
    /// - Parameters:
    ///   - call: The call text to look for.
    ///   - line: The line to read.
    /// - Returns: `true` when one occurrence of `call` starts a name.
    private static func holds(call: String, in line: String) -> Bool {
        var start = line.startIndex
        while let found = line.range(of: call, range: start..<line.endIndex) {
            if startsAName(at: found.lowerBound, in: line) {
                return true
            }
            start = found.upperBound
        }
        return false
    }

    /// Tells whether a name starts at `index` of `line`.
    ///
    /// - Parameters:
    ///   - index: The index the name would start at.
    ///   - line: The line to read.
    /// - Returns: `true` when no letter, number or underscore stands before
    ///   `index`.
    private static func startsAName(at index: String.Index, in line: String) -> Bool {
        guard index > line.startIndex else { return true }
        let before = line[line.index(before: index)]
        return !before.isLetter && !before.isNumber && before != "_"
    }
}
