import Foundation
import InMemoryTracing
import Logging
import Metrics
import MetricsTestKit
import Testing
import Tracing

@testable import FoundationModelsSkills

/// Tests for `SkillsTracing`, the telemetry vocabulary of this package.
///
/// A name of the vocabulary is part of the observable surface of the package.
/// A dashboard, a query or an alert of a host application finds the records of
/// this package through the name. Thus each span name, each metric name and
/// each logger label starts with the module prefix, and each name is unique in
/// its group.
///
/// The suite also guards the one logging API of the package. It gives
/// `SwiftSourceScan` a test of a line, and fails on each line under
/// `Sources/` that imports `os`, names `os.Logger`, or names `OSSignposter`.
@Suite("Skills tracing")
struct SkillsTracingTests {
    /// What each span name, metric name and logger label starts with.
    private static let modulePrefix = "FoundationModelsSkills."

    /// Every span name of the vocabulary.
    private static let spanNames = [
        SkillsTracing.SpanName.search,
        SkillsTracing.SpanName.catalogLoad,
        SkillsTracing.SpanName.skillLoad,
    ]

    /// Every metric name of the vocabulary.
    private static let metricNames = [
        SkillsTracing.MetricName.searchDuration,
        SkillsTracing.MetricName.skillsLoaded,
    ]

    /// Every logger label of the vocabulary.
    private static let loggerLabels = [
        SkillsTracing.LoggerLabel.search,
        SkillsTracing.LoggerLabel.registry,
    ]

    /// Every span attribute key of the vocabulary.
    private static let attributeKeys = [
        SkillsTracing.AttributeKey.skillID,
        SkillsTracing.AttributeKey.skillCount,
        SkillsTracing.AttributeKey.searchLimit,
        SkillsTracing.AttributeKey.searchResultCount,
        SkillsTracing.AttributeKey.searchTier,
        SkillsTracing.AttributeKey.searchFallback,
        SkillsTracing.AttributeKey.diagnosticCount,
        SkillsTracing.AttributeKey.errorType,
    ]

    /// Every log metadata key of the vocabulary.
    private static let metadataKeys = [
        SkillsTracing.MetadataKey.errorType
    ]

    /// The text that opens a comment line.
    private static let commentMarker = "//"

    /// The keyword that opens an import declaration.
    private static let importKeyword = "import"

    /// The module name that no import may name.
    private static let osModule = "os"

    /// The names that no line of code may hold.
    private static let disallowedNames = ["os.Logger", "OSSignposter"]

    // MARK: - Prefix

    @Test(arguments: spanNames + metricNames + loggerLabels)
    func aSpanNameAMetricNameAndALoggerLabelStartWithTheModulePrefix(name: String) {
        #expect(name.hasPrefix(Self.modulePrefix))
        #expect(name.count > Self.modulePrefix.count)
    }

    // MARK: - Uniqueness

    @Test func eachSpanNameIsUnique() {
        #expect(Set(Self.spanNames).count == Self.spanNames.count)
    }

    @Test func eachMetricNameIsUnique() {
        #expect(Set(Self.metricNames).count == Self.metricNames.count)
    }

    @Test func eachLoggerLabelIsUnique() {
        #expect(Set(Self.loggerLabels).count == Self.loggerLabels.count)
    }

    @Test func eachAttributeKeyIsUnique() {
        #expect(Set(Self.attributeKeys).count == Self.attributeKeys.count)
    }

    // MARK: - Shared keys and values

    /// Shows that a log record and a span name the error type with one key.
    /// Thus a query can join a log record to the span of the same failure.
    @Test func theErrorTypeMetadataKeyIsTheErrorTypeAttributeKey() {
        #expect(Self.metadataKeys == [SkillsTracing.AttributeKey.errorType])
        #expect(SkillsTracing.AttributeKey.errorType == "error.type")
    }

    @Test func theSearchTierValuesAreSelectionAndRetrieval() {
        #expect(SkillsTracing.SearchTier.selection.rawValue == "selection")
        #expect(SkillsTracing.SearchTier.retrieval.rawValue == "retrieval")
    }

    // MARK: - Tracer

    @Test func anExplicitTracerIsTheTracerACallOpensItsSpanThrough() {
        let tracer = SkillsTracing.tracer(explicit: InMemoryTracer())

        #expect(tracer is InMemoryTracer)
    }

    @Test func noExplicitTracerGivesTheBootstrappedTracer() {
        let tracer = SkillsTracing.tracer(explicit: nil)

        #expect(!(tracer is InMemoryTracer))
        #expect(ObjectIdentifier(type(of: tracer)) == ObjectIdentifier(type(of: InstrumentationSystem.tracer)))
    }

    // MARK: - Telemetry

    @Test func theTelemetryGivesItsExplicitTracer() {
        let telemetry = SkillsTracing.Telemetry(tracer: InMemoryTracer())

        #expect(telemetry.tracer is InMemoryTracer)
    }

    @Test func theTelemetryGivesItsExplicitMetricsFactory() {
        let factory = TestMetrics()
        let telemetry = SkillsTracing.Telemetry(metricsFactory: factory)

        #expect((telemetry.metricsFactory as? TestMetrics) === factory)
    }

    /// Shows the resolve-late shape: with no explicit factory, the telemetry
    /// reads the factory of the current task when the call starts, thus a
    /// factory that `withMetricsFactory` binds is the factory of the call.
    @Test func theTelemetryWithNoExplicitFactoryReadsTheFactoryOfTheCurrentTask() {
        let factory = TestMetrics()
        let telemetry = SkillsTracing.Telemetry()

        let current = withMetricsFactory(factory) { telemetry.metricsFactory }

        #expect((current as? TestMetrics) === factory)
    }

    @Test func theTelemetryGivesItsExplicitLogger() {
        let explicit = Logger(label: Self.explicitLoggerLabel)
        let telemetry = SkillsTracing.Telemetry(logger: explicit)

        #expect(telemetry.logger(label: SkillsTracing.LoggerLabel.search).label == Self.explicitLoggerLabel)
    }

    @Test func theTelemetryWithNoExplicitLoggerMakesALoggerWithTheLabelOfTheCaller() {
        let telemetry = SkillsTracing.Telemetry()

        #expect(telemetry.logger(label: SkillsTracing.LoggerLabel.registry).label == SkillsTracing.LoggerLabel.registry)
    }

    /// The label of the explicit logger of the telemetry cases. It is not a
    /// label of the vocabulary, thus a case can tell the two loggers apart.
    private static let explicitLoggerLabel = "SkillsTracingTests.explicit"

    // MARK: - No os logging

    @Test(arguments: [
        "import os",
        "@preconcurrency import os",
        "import os.log",
        "import struct os.Logger",
        "let logger = os.Logger(subsystem: \"a\", category: \"b\")",
        "let signposter = OSSignposter()",
    ])
    func aLineThatUsesOsLoggingIsReported(line: String) {
        #expect(Self.usesOsLogging(line))
    }

    @Test(arguments: [
        "import Logging",
        "import osmium",
        "// import os",
        "/// The package never writes `import os`.",
        "let logger = Logger(label: SkillsTracing.LoggerLabel.search)",
    ])
    func aLineThatDoesNotUseOsLoggingIsNotReported(line: String) {
        #expect(!Self.usesOsLogging(line))
    }

    @Test func noSourceFileUsesOsLogging() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: "Sources", matching: Self.usesOsLogging)

        #expect(
            offenders.isEmpty,
            """
            No source file may import os, name os.Logger, or name OSSignposter. Log with \
            Logging.Logger (swift-log); found: \(offenders.joined(separator: ", "))
            """)
    }

    /// Tells whether `line` holds code that uses the logging of `os`.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: `true` when the line imports `os`, or names `os.Logger` or
    ///   `OSSignposter`.
    private static func usesOsLogging(_ line: String) -> Bool {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix(commentMarker) else { return false }
        return importsOs(code) || disallowedNames.contains { code.contains($0) }
    }

    /// Tells whether `code` is an import declaration that names `os` or a
    /// submodule or a symbol of `os`.
    ///
    /// - Parameter code: The line to read, with no leading white space.
    /// - Returns: `true` when a word after the `import` keyword is `os`, or
    ///   starts with `os.`.
    private static func importsOs(_ code: String) -> Bool {
        let words = code.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let keywordIndex = words.firstIndex(of: importKeyword) else { return false }
        return words[words.index(after: keywordIndex)...].contains {
            $0 == osModule || $0.hasPrefix(osModule + ".")
        }
    }
}
