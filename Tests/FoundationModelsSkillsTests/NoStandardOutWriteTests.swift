import Foundation
import Testing

/// Guards the `no_direct_standard_out_logs` rule of the code hygiene gate: no
/// line of this package, and no line of its example, writes to a standard
/// stream with `print`, `debugPrint`, `dump` or `_printChanges`. Every line
/// goes through `StandardStream`, the one line writer.
///
/// The suite gives `SwiftSourceScan` the test of a line below, and that reader
/// walks every Swift file under `Sources/` and `Examples/skills-demo/`. A call
/// is the name of one of the four and the `(` that opens its arguments, with
/// no letter, number or underscore before the name. Thus `sprint(x)` and
/// `printableLine(x)` are not reported. A comment line holds no code, thus the
/// walk passes over it, the way the `match_kinds: [identifier]` key of the
/// rule itself does.
@Suite("No standard out write")
struct NoStandardOutWriteTests {
    /// The calls that no line of code may hold. Each one is a name and the
    /// `(` that opens its arguments.
    private static let disallowedCalls = ["print(", "debugPrint(", "dump(", "_printChanges("]

    /// The text that opens a comment line.
    private static let commentMarker = "//"

    @Test(arguments: [
        "print(\"hello\")",
        "debugPrint(value)",
        "dump(value)",
        "Self._printChanges()",
        "        print(\"indented\")",
    ])
    func aLineThatCallsOneOfTheFourIsReported(line: String) {
        #expect(Self.writesToAStandardStream(line))
    }

    @Test(arguments: [
        "Self.printableLine(of: text)",
        "sprintDistance()",
        "StandardStream.output.write(line: text)",
        "// print(\"a comment holds no code\")",
        "/// The one writer, which `dump(_:)` never replaces.",
    ])
    func aLineThatCallsNoneOfTheFourIsNotReported(line: String) {
        #expect(!Self.writesToAStandardStream(line))
    }

    @Test(arguments: ["Sources", "Examples/skills-demo"])
    func noFileOfTheDirectoryWritesToAStandardStreamWithACall(directory: String) throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: directory, matching: Self.writesToAStandardStream)

        #expect(
            offenders.isEmpty,
            """
            No file may write to a standard stream with print, debugPrint, dump or _printChanges. Write \
            each line with StandardStream; found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` writes to a standard stream with a call to one of
    /// the four.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line holds code that calls one of the four.
    private static func writesToAStandardStream(_ line: String) -> Bool {
        !isComment(line) && callsOneOfTheFour(line)
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
