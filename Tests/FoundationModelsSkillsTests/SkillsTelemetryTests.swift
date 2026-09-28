import Foundation
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import InMemoryTracing
import MetricsTestKit
import Testing
import Tracing

@testable import FoundationModelsSkills

/// Tests for the spans, the "enter" log records and the metrics of a skill
/// search, a skill load and a catalog load.
///
/// Each case gives an explicit `InMemoryTracer`, `TestMetrics` and recording
/// logger to the code under test, and reads the records back. The telemetry is
/// explicit, not task-local, because the rebuild of a hot reload runs on the
/// queue of the watcher, where no task-local value reaches.
@Suite("Skills telemetry")
struct SkillsTelemetryTests {
    /// The project layer of the fixture library.
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// The largest number of matches that the search case asks for.
    private static let searchLimit = 10

    /// A query that the retrieval rank of the fixture catalog matches to one
    /// skill.
    private static let commitQuery = "commit"

    /// A skill of the fixture library that renders with no argument.
    private static let commitSkillID = "commit"

    /// An id that no catalog holds.
    private static let unknownSkillID = "no-such-skill"

    /// The skills of the catalog-load case before the reload.
    private static let skillIDsBeforeReload = ["first-skill"]

    /// The skills of the catalog-load case after the reload.
    private static let skillIDsAfterReload = ["first-skill", "second-skill"]

    // MARK: - Search

    @Test func oneAnswerGivesOneSearchSpanOneEnterRecordAndOneDurationValue() async throws {
        let capture = TelemetryRecording()
        let registry = SkillsRegistry(roots: [Self.projectSkillsRoot])
        let agent = SkillSearchAgent(
            searcher: MetadataSearcher(items: registry.metadata().filter(\.isModelVisible)),
            retrievalFallback: nil, visibilityPredicate: { $0.isModelVisible }, telemetry: capture.telemetry)

        let answer = try await agent.answer(query: Self.commitQuery, limit: Self.searchLimit)

        let spans = capture.spans(named: SkillsTracing.SpanName.search)
        let span = try #require(spans.first)
        let tier = SkillsTracing.SearchTier.retrieval.rawValue
        #expect(spans.count == 1)
        #expect(span.attributes.get(SkillsTracing.AttributeKey.searchLimit) == Self.searchLimit.toSpanAttribute())
        #expect(
            span.attributes.get(SkillsTracing.AttributeKey.searchResultCount)
                == answer.matches.count.toSpanAttribute())
        #expect(span.attributes.get(SkillsTracing.AttributeKey.searchTier) == tier.toSpanAttribute())
        #expect(span.attributes.get(SkillsTracing.AttributeKey.searchFallback) == false.toSpanAttribute())
        #expect(capture.enterRecords(ofSpanNamed: SkillsTracing.SpanName.search).count == 1)
        let timer = try capture.metrics.expectTimer(
            SkillsTracing.MetricName.searchDuration, [(SkillsTracing.AttributeKey.searchTier, tier)])
        #expect(timer.values.count == 1)
    }

    // MARK: - Skill load

    @Test func oneCallGivesOneSkillLoadSpanWithTheSkillIDAndOneEnterRecord() async throws {
        let capture = TelemetryRecording()
        let registry = Self.fixtureRegistry(telemetry: capture.telemetry)

        _ = try await registry.call(id: Self.commitSkillID)

        let spans = capture.spans(named: SkillsTracing.SpanName.skillLoad)
        let span = try #require(spans.first)
        #expect(spans.count == 1)
        #expect(span.attributes.get(SkillsTracing.AttributeKey.skillID) == Self.commitSkillID.toSpanAttribute())
        #expect(span.errors.isEmpty)
        #expect(capture.enterRecords(ofSpanNamed: SkillsTracing.SpanName.skillLoad).count == 1)
    }

    @Test func aCallThatThrowsRecordsTheErrorOnTheSkillLoadSpan() async throws {
        let capture = TelemetryRecording()
        let registry = Self.fixtureRegistry(telemetry: capture.telemetry)

        await #expect(throws: UnknownSkillError.self) {
            try await registry.call(id: Self.unknownSkillID)
        }

        let spans = capture.spans(named: SkillsTracing.SpanName.skillLoad)
        let span = try #require(spans.first)
        #expect(spans.count == 1)
        #expect(span.errors.count == 1)
        #expect(span.errors.first?.error is UnknownSkillError)
    }

    // MARK: - Catalog load and hot reload

    /// Shows that the build at the start of a registry and the rebuild of a
    /// hot reload each give one catalog-load span and one value of the gauge,
    /// and that each value is the skill count of that build.
    @Test func eachCatalogBuildGivesOneCatalogLoadSpanAndOneSkillsLoadedValue() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for id in Self.skillIDsBeforeReload {
            try ReloadTestSupport.writeSkillFile(id: id, in: root)
        }
        let capture = TelemetryRecording()
        let registry = SkillsRegistry(
            layers: [DotfolderStack.Layer(source: .project, root: root)], policy: RenderPolicy(), watch: true,
            telemetry: capture.telemetry)
        let initialSpans = capture.spans(named: SkillsTracing.SpanName.catalogLoad)
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(registry.onReload, into: tally)
        defer { subscription.cancel() }

        for id in Self.skillIDsAfterReload where !Self.skillIDsBeforeReload.contains(id) {
            try ReloadTestSupport.writeSkillFile(id: id, in: root)
        }
        await ReloadTestSupport.expectExactlyOneEvent(tally)

        let spans = capture.spans(named: SkillsTracing.SpanName.catalogLoad)
        let counts = [Self.skillIDsBeforeReload.count, Self.skillIDsAfterReload.count]
        #expect(initialSpans.count == 1)
        #expect(spans.map { $0.attributes.get(SkillsTracing.AttributeKey.skillCount) } == counts.map { $0.toSpanAttribute() })
        #expect(spans.allSatisfy { $0.attributes.get(SkillsTracing.AttributeKey.diagnosticCount) == 0.toSpanAttribute() })
        let gauge = try capture.metrics.expectGauge(SkillsTracing.MetricName.skillsLoaded)
        #expect(gauge.values == counts.map(Double.init))
    }

    // MARK: - Support

    /// Makes a registry over the fixture library, with a static catalog.
    ///
    /// - Parameter telemetry: The telemetry of the registry.
    /// - Returns: The registry.
    private static func fixtureRegistry(telemetry: SkillsTracing.Telemetry) -> SkillsRegistry {
        SkillsRegistry(layers: FixtureLibrary.stack().layers, policy: RenderPolicy(), watch: false, telemetry: telemetry)
    }
}

/// An explicit tracer, metrics factory and recording logger, and the records
/// that they hold.
private struct TelemetryRecording {
    /// The tracer. It keeps each span that ends.
    let tracer = InMemoryTracer()

    /// The metrics factory. It keeps each metric that the code makes.
    let metrics = TestMetrics()

    /// The log records of `telemetry.logger`.
    let logs = Recorder<LogRecord>()

    /// The label of the recording logger. It is not a label of the
    /// vocabulary, because one logger records for each component of a case.
    private static let loggerLabel = "SkillsTelemetryTests"

    /// The telemetry to give to the code under test.
    var telemetry: SkillsTracing.Telemetry {
        SkillsTracing.Telemetry(
            tracer: tracer, metricsFactory: metrics,
            logger: RecordingLogHandler.makeLogger(label: Self.loggerLabel, recorder: logs))
    }

    /// The spans with the name `name` that ended, in the order of their end.
    ///
    /// - Parameter name: The span name.
    /// - Returns: The spans.
    func spans(named name: String) -> [FinishedInMemorySpan] {
        tracer.finishedSpans.filter { $0.operationName == name }
    }

    /// The "enter" records of the spans with the name `name`.
    ///
    /// - Parameter name: The span name.
    /// - Returns: Each record at the level of an "enter" record whose message
    ///   ends with the span name.
    func enterRecords(ofSpanNamed name: String) -> [LogRecord] {
        logs.recorded.filter { $0.level == TracedCall.enterLevel && $0.message.hasSuffix(name) }
    }
}
