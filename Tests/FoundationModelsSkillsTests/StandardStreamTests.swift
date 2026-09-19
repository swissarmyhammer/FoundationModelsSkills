import Foundation
import Testing

@testable import FoundationModelsSkills

/// Holds ``StandardStream`` -- the one line writer of this package and of its
/// example -- to the text it builds and to the bytes it writes.
///
/// No case here writes to the standard output of this process: the byte case
/// writes into the write end of a `Pipe` and reads the bytes back, thus a
/// parallel run stays clean.
@Suite struct StandardStreamTests {
    /// A line of a case, and the line that follows it.
    private static let firstLine = "first"

    /// The second line of the cases that write more than one line.
    private static let secondLine = "second"

    // MARK: - The text of a list of lines

    @Test func theLineBreakOfTheTypeIsTheNewline() {
        #expect(StandardStream.lineBreak == "\n")
    }

    @Test func theTextOfOneLineEndsWithTheLineBreak() {
        #expect(StandardStream.text(of: [Self.firstLine]) == "first\n")
    }

    @Test func theTextOfTwoLinesEndsEachOneWithTheLineBreak() {
        #expect(StandardStream.text(of: [Self.firstLine, Self.secondLine]) == "first\nsecond\n")
    }

    @Test func theTextOfNoLineIsEmpty() {
        #expect(StandardStream.text(of: []).isEmpty)
    }

    // MARK: - The bytes that reach the handle

    @Test func aWriteOfTwoLinesGivesTheBytesOfTheirText() throws {
        let pipe = Pipe()

        StandardStream.write(lines: [Self.firstLine, Self.secondLine], to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        let written = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(written == StandardStream.text(of: [Self.firstLine, Self.secondLine]))
    }

    @Test func aWriteOfNoLineWritesNoByte() throws {
        let pipe = Pipe()

        StandardStream.write(lines: [], to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        #expect(pipe.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    // MARK: - The handle of each stream

    @Test func theOutputStreamWritesToTheStandardOutputOfThisProcess() {
        #expect(StandardStream.output.handle === FileHandle.standardOutput)
    }

    @Test func theErrorStreamWritesToTheStandardErrorOfThisProcess() {
        #expect(StandardStream.error.handle === FileHandle.standardError)
    }
}
