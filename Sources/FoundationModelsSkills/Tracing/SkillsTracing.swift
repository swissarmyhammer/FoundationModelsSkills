import Logging
import Metrics
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
///
/// `TelemetryContentSafetyTests` proves this rule. It puts a unique marker in
/// a search query, in the arguments of a skill, in the body of a skill and in
/// the output of a script. It then runs a search, a skill load and a hot
/// reload in a `TelemetryCapture` of `FoundationModelsExtras`, which fails on
/// each span attribute, log message, log metadata value and metric dimension
/// that holds a marker.
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

        /// The logger of ``SkillsRegistry``. It gets the "enter" record of
        /// each skill load.
        static let registry = prefix + "registry"
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

    /// The tracer, the metrics factory and the logger of one component:
    /// ``SkillSearchAgent`` or ``SkillsRegistry``.
    ///
    /// Each value is optional. `nil` is the resolve-late shape: the component
    /// reads the bootstrapped tracer, the factory of the current task (see
    /// `withMetricsFactory`) or a new logger when a call starts, not when the
    /// component is made. Thus a host application that bootstraps a backend
    /// after it makes the component still observes it.
    ///
    /// The public initializers of the two components give the default value,
    /// which sets nothing, thus the public API has no telemetry parameter. A
    /// test gives explicit values through an internal initializer. An
    /// explicit value is necessary for the rebuild of a hot reload: that
    /// rebuild runs on the queue of the watcher, where no task-local tracer
    /// or factory reaches.
    struct Telemetry: Sendable {
        /// The explicit tracer, or `nil` for the bootstrapped tracer.
        private let explicitTracer: (any Tracer)?

        /// The explicit metrics factory, or `nil` for the factory of the
        /// current task.
        private let explicitMetricsFactory: (any MetricsFactory)?

        /// The explicit logger, or `nil` for a new logger at each call.
        private let explicitLogger: Logger?

        /// Makes the telemetry of one component.
        ///
        /// - Parameters:
        ///   - tracer: The tracer of each span, or `nil` for the
        ///     bootstrapped tracer at call time.
        ///   - metricsFactory: The factory of each metric, or `nil` for the
        ///     factory of the current task at call time.
        ///   - logger: The logger of each record, or `nil` for a new logger at
        ///     call time.
        init(tracer: (any Tracer)? = nil, metricsFactory: (any MetricsFactory)? = nil, logger: Logger? = nil) {
            explicitTracer = tracer
            explicitMetricsFactory = metricsFactory
            explicitLogger = logger
        }

        /// The tracer that a call opens its span through. See
        /// ``SkillsTracing/tracer(explicit:)``.
        var tracer: any Tracer {
            SkillsTracing.tracer(explicit: explicitTracer)
        }

        /// The factory that a call makes its metrics through: the explicit
        /// factory, else `MetricsSystem.factory`, which is the factory of the
        /// current task when `withMetricsFactory` binds one, else the
        /// bootstrapped factory.
        var metricsFactory: any MetricsFactory {
            explicitMetricsFactory ?? MetricsSystem.factory
        }

        /// The logger that a call writes its records to.
        ///
        /// A new logger keeps the handler of the time that it is made, thus
        /// the component makes it at call time and does not store it.
        ///
        /// - Parameter label: The label of a new logger, one of
        ///   ``SkillsTracing/LoggerLabel``.
        /// - Returns: The explicit logger, else a new logger with `label`.
        func logger(label: String) -> Logger {
            explicitLogger ?? Logger(label: label)
        }

        /// Records the duration of one search that gave an answer, in the
        /// timer ``SkillsTracing/MetricName/searchDuration``.
        ///
        /// - Parameters:
        ///   - duration: The time from the start of the search to the answer.
        ///   - tier: The tier that chose the matches. It is the one dimension
        ///     of the timer.
        func recordSearchDuration(_ duration: Duration, tier: SearchTier) {
            Timer(
                label: MetricName.searchDuration, dimensions: [(AttributeKey.searchTier, tier.rawValue)],
                factory: metricsFactory
            ).record(duration: duration)
        }

        /// Records the size of one catalog build, in the gauge
        /// ``SkillsTracing/MetricName/skillsLoaded``.
        ///
        /// - Parameter count: The number of skills in the catalog.
        func recordSkillsLoaded(_ count: Int) {
            Gauge(label: MetricName.skillsLoaded, factory: metricsFactory).record(count)
        }
    }
}
