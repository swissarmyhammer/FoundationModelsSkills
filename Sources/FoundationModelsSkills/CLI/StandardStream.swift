import Foundation

/// One standard stream of this process, as a writer of whole lines.
///
/// Every line that this package and its example write to a standard stream
/// goes through this type. Thus the line break that ends a line is stated one
/// time, and no caller builds the bytes of a line itself.
///
/// A caller that collects its output instead of writing it still builds its
/// text with ``text(of:)``, thus a collected run and a written run end each
/// line the same way.
public enum StandardStream: Sendable {
    /// The standard output stream, where a run writes its answer.
    case output

    /// The standard error stream, where a run writes a failure.
    case error

    /// The line break that ends one written line.
    public static let lineBreak = "\n"

    /// The text of a list of lines, each one with a line break after it.
    ///
    /// - Parameter lines: The lines, each one with no line break at its end.
    /// - Returns: The text, or the empty text for an empty list.
    public static func text(of lines: [String]) -> String {
        lines.lazy.map { "\($0)\(lineBreak)" }.joined()
    }

    /// The file handle that this stream writes into.
    internal var handle: FileHandle {
        switch self {
        case .output: FileHandle.standardOutput
        case .error: FileHandle.standardError
        }
    }

    /// Writes one line, with a line break after it.
    ///
    /// - Parameter line: The line, with no line break at its end.
    public func write(line: String) {
        Self.write(lines: [line], to: handle)
    }

    /// Writes each line of a list, each one with a line break after it.
    ///
    /// - Parameter lines: The lines, each one with no line break at its end.
    ///   An empty list writes nothing.
    public func write(lines: [String]) {
        Self.write(lines: lines, to: handle)
    }

    /// Writes the text of a list of lines into one file handle.
    ///
    /// This is the one place that turns lines into bytes. It is the seam a
    /// test writes through: a test gives the write end of a `Pipe` and reads
    /// the bytes back, thus no case writes to a stream of this process.
    ///
    /// - Parameters:
    ///   - lines: The lines, each one with no line break at its end. An empty
    ///     list writes nothing.
    ///   - handle: The file handle that takes the bytes.
    internal static func write(lines: [String], to handle: FileHandle) {
        let text = text(of: lines)
        guard !text.isEmpty else { return }
        handle.write(Data(text.utf8))
    }
}
