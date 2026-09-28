import Logging

/// One log record that `RecordingLogHandler` recorded.
struct LogRecord: Sendable {
    /// The level of the record.
    let level: Logger.Level

    /// The message of the record.
    let message: String

    /// The merged metadata of the record: the handler metadata and the
    /// metadata of the call.
    let metadata: Logger.Metadata

    /// The description of the error that the event carried, or `nil` when
    /// it carried no error. A backend can write that description, thus it
    /// is content too.
    let errorDescription: String?

    /// Tells whether the message, a metadata value or the error of the
    /// event holds `text`.
    ///
    /// - Parameter text: The text to find.
    /// - Returns: `true` when the message, the description of a metadata
    ///   value, or the description of the error holds `text`.
    func holds(_ text: String) -> Bool {
        message.contains(text)
            || metadata.values.contains { $0.description.contains(text) }
            || errorDescription?.contains(text) == true
    }
}

/// A `LogHandler` that gives each log record to a `Recorder`.
///
/// `SkillSearchAgentTests` and `SkillsTelemetryTests` both read the records
/// of a logger back, thus the handler is here and not in one of the two
/// suites.
struct RecordingLogHandler: LogHandler {
    /// Where each record goes.
    let recorder: Recorder<LogRecord>

    /// The metadata of the logger that holds this handler.
    var metadata: Logger.Metadata = [:]

    /// The lowest level that the logger sends to this handler. Each level
    /// passes, thus the recorder sees each record.
    var logLevel: Logger.Level = .trace

    /// Reads or writes one metadata value of the logger.
    ///
    /// - Parameter key: The metadata key.
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// Gives `event` to the recorder, with the metadata of this handler and
    /// the metadata of the call merged.
    ///
    /// - Parameter event: The log record.
    func log(event: LogEvent) {
        let merged = metadata.merging(event.metadata ?? [:]) { _, call in call }
        recorder.record(
            LogRecord(
                level: event.level, message: event.message.description, metadata: merged,
                errorDescription: event.error.map { String(describing: $0) }))
    }

    /// Makes a logger that writes each record to `recorder`.
    ///
    /// - Parameters:
    ///   - label: The label of the logger.
    ///   - recorder: Where each record goes.
    /// - Returns: The logger.
    static func makeLogger(label: String, recorder: Recorder<LogRecord>) -> Logger {
        Logger(label: label) { _ in RecordingLogHandler(recorder: recorder) }
    }
}
