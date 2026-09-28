import Tracing

/// The telemetry vocabulary of this package: the name of each span, the key of
/// each span attribute, the name of each metric, the key of each log metadata
/// value, the label of each logger, and the rule that selects the tracer of a
/// call.
///
/// One home for the vocabulary, thus each name is written one time and read
/// everywhere. A name here is part of the observable surface of the package. A
/// dashboard, a query or an alert of a host application finds the records of
/// this package through the name. Thus change a name only as a deliberate
/// break.
///
/// Each span name, each metric name and each logger label starts with the
/// prefix `FoundationModelsSkills.`. Thus a record of this package stays
/// recognizable in a trace or a log that also holds the records of the host
/// application. `SkillsTracingTests` holds each group to the prefix, and holds
/// each name unique in its group.
///
/// The package uses the API packages only: `swift-distributed-tracing`,
/// `swift-log` and `swift-metrics`. Each one is an abstraction, not an
/// exporter. Until a host application bootstraps a backend, each span, each
/// log record and each metric goes to a no-op handler, thus an application
/// that does not observe pays nothing.
///
/// ## No content
///
/// A span attribute, a log message, a log metadata value and a metric
/// dimension must never hold:
///
/// - the text of a search query,
/// - the body of a skill,
/// - the arguments of a skill,
/// - the rendered text of a skill,
/// - the output of a script,
/// - the response of a model.
///
/// A record leaves the process through the backend that the host application
/// bootstrapped. The package cannot know where that backend sends the record,
/// thus the record holds no content of the user. Identifiers, names, counts,
/// sizes, durations and type names are safe. A skill id is a name, thus it is
/// safe. Content is not safe.
///
/// The description of an error is content too: the error of a selection
/// session can hold the query or the model response. Thus a record names the
/// type of an error (``AttributeKey/errorType``, ``MetadataKey/errorType``),
/// and never its description.
enum SkillsTracing {
    /// What each span name, metric name and logger label starts with.
    private static let prefix = "FoundationModelsSkills."

    /// The operation name of each span that the package opens.
    enum SpanName {
        /// One ``SkillSearchAgent/answer(query:limit:)`` call: the selection
        /// tier, and the retrieval fallback when the selection tier fails.
        static let search = prefix + "search"

        /// One build of the catalog: the build at the start of a
        /// ``SkillsRegistry``, and the build of each hot reload.
        static let catalogLoad = prefix + "catalog.load"

        /// One ``SkillsRegistry/call(id:arguments:)`` call, which renders the
        /// body of one skill.
        static let skillLoad = prefix + "skill.load"
    }

    /// The key of each attribute that a span of the package holds.
    ///
    /// Read the rule of the type before you add a key. A key here names an
    /// identifier, a name, a count, a size or a type name, and never a part of
    /// the content of the user.
    enum AttributeKey {
        /// The id of one skill. A skill id is a name, thus it is safe.
        static let skillID = "skill.id"

        /// The number of skills in the catalog after a load.
        static let skillCount = "skill.count"

        /// The largest number of matches that a search can give.
        static let searchLimit = "search.limit"

        /// The number of matches that a search gave.
        static let searchResultCount = "search.result_count"

        /// The tier that chose the matches of a search. See
        /// ``SkillsTracing/SearchTier``.
        static let searchTier = "search.tier"

        /// `true` when the selection tier failed and the retrieval fallback
        /// ranked the query.
        static let searchFallback = "search.fallback"

        /// The number of diagnostics that a catalog load found.
        static let diagnosticCount = "diagnostic.count"

        /// The type name of an error, from `String(reflecting:)` on the type
        /// of the error. Never the description of the error.
        static let errorType = "error.type"
    }

    /// The value that ``AttributeKey/searchTier`` and the dimension of
    /// ``MetricName/searchDuration`` hold: the tier that chose the matches.
    enum SearchTier: String {
        /// The selection tier: a language model chose the matches.
        case selection

        /// The retrieval tier: the keyword and vector rank chose the matches.
        case retrieval
    }

    /// The name of each metric that the package records.
    enum MetricName {
        /// A timer: the duration of one search. Its one dimension is
        /// ``AttributeKey/searchTier``.
        static let searchDuration = prefix + "search.duration"

        /// A gauge: the number of skills in the catalog after the last load.
        ///
        /// A gauge and not a counter. Each load builds the full catalog again,
        /// thus the value of a load replaces the value of the load before it.
        /// A counter would add the size of each reload to the sum, and the sum
        /// would not be the size of any catalog.
        static let skillsLoaded = prefix + "skills.loaded"
    }

    /// The key of each metadata value that a log record of the package holds.
    ///
    /// A log record and a span use the same key for the same value, thus a
    /// query can join a log record to the span of the same event.
    enum MetadataKey {
        /// The type name of an error. See ``AttributeKey/errorType``.
        static let errorType = AttributeKey.errorType
    }

    /// The label of each logger of the package.
    enum LoggerLabel {
        /// The logger of ``SkillSearchAgent``.
        static let search = prefix + "search"
    }

    /// The tracer that a call opens its span through.
    ///
    /// `nil` is the resolve-late shape. An application that bootstraps a
    /// tracing backend *after* it makes a ``SkillsRegistry`` or a
    /// ``SkillSearchAgent`` still traces, because the tracer is read only
    /// when the call starts.
    ///
    /// - Parameter explicit: The tracer that the caller gave, or `nil` to read
    ///   the bootstrapped tracer now.
    /// - Returns: `explicit` when it is set, else `InstrumentationSystem.tracer`.
    static func tracer(explicit: (any Tracer)?) -> any Tracer {
        explicit ?? InstrumentationSystem.tracer
    }
}
