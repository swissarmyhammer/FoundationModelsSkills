import Foundation
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import TelemetryTestSupport
import Testing

@testable import FoundationModelsSkills

/// The content-safety test of this package: rule 5 of the OpenTelemetry
/// design of 2026-09-28.
///
/// The case puts one unique marker in each kind of content that the package
/// touches: the search query, the arguments of a skill, the body of a skill
/// and the output of a script. It then runs a search whose selection tier
/// fails (thus the retrieval fallback and its log record run too), a skill
/// load that renders the body with the arguments and the script, and a hot
/// reload. `TelemetryCapture` of `FoundationModelsExtras` reads each span
/// name and attribute, each log message and metadata value, and each metric
/// name and dimension of the capture, and records an issue for each marker
/// that it finds.
@Suite("Telemetry content safety")
struct TelemetryContentSafetyTests {
    /// The marker of the search query.
    private static let queryMarker = "SEARCH-QUERY-CONTENT-4b1e"

    /// The marker of the arguments of the skill.
    private static let argumentMarker = "SKILL-ARGUMENT-CONTENT-9d2a"

    /// The marker of the body of the skill.
    private static let bodyMarker = "SKILL-BODY-CONTENT-3c7f"

    /// The marker of the output of the script. The script joins two halves
    /// with a hyphen, thus the body holds the two halves and never the whole
    /// marker: only the output of the script holds it.
    private static let scriptOutputMarker = "SCRIPT-OUTPUT-CONTENT-6e8d"

    /// The first half of ``scriptOutputMarker``, before the hyphen.
    private static let scriptOutputHead = "SCRIPT-OUTPUT"

    /// The second half of ``scriptOutputMarker``, after the hyphen.
    private static let scriptOutputTail = "CONTENT-6e8d"

    /// Each marker that no telemetry record may hold.
    private static let markers = [queryMarker, argumentMarker, bodyMarker, scriptOutputMarker]

    /// The skill that the case loads.
    private static let skillID = "content-skill"

    /// The skill that the reload adds.
    private static let reloadedSkillID = "reloaded-skill"

    /// The largest number of matches that the search asks for.
    private static let searchLimit = 10

    /// The body of the loaded skill: the body marker, the arguments, and one
    /// shell injection on its own line whose output is the script marker.
    private static let skillBody = """
        \(bodyMarker) $ARGUMENTS
        !`printf '%s-%s' \(scriptOutputHead) \(scriptOutputTail)`
        """

    @Test func noSpanLogRecordOrMetricOfASearchASkillLoadAndAReloadHoldsContent() async throws {
        let root = try WatcherTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: Self.skillID, in: root, body: Self.skillBody)

        try await TelemetryCapture.run(forbidding: Self.markers) { context in
            let telemetry = SkillsTracing.Telemetry(
                tracer: context.tracer, metricsFactory: context.metricsFactory, logger: context.logger)
            let registry = SkillsRegistry(
                layers: [DotfolderStack.Layer(source: .project, root: root)], policy: RenderPolicy(), watch: true,
                telemetry: telemetry)

            try await Self.search(registry: registry, telemetry: telemetry)
            let rendered = try await registry.call(id: Self.skillID, arguments: [Self.argumentMarker])
            try await Self.reload(registry: registry, root: root)

            #expect(rendered.contains(Self.argumentMarker))
            #expect(rendered.contains(Self.scriptOutputMarker))
            #expect(
                Self.packageSpanNames(context.spans.map(\.operationName))
                    == [SkillsTracing.SpanName.search, SkillsTracing.SpanName.skillLoad, SkillsTracing.SpanName.catalogLoad])
        }
    }

    /// Selects the span names of this package from the span names of a
    /// capture.
    ///
    /// The capture also holds the spans of a dependency, for example the
    /// search spans of `FoundationModelsMetadataRegistry`. Those names are not
    /// the contract of this package, thus the comparison reads only the names
    /// that start with ``SkillsTracing/prefix``.
    ///
    /// - Parameter names: The operation name of each captured span.
    /// - Returns: Each distinct name that starts with the prefix of this
    ///   package.
    private static func packageSpanNames(_ names: [String]) -> Set<String> {
        Set(names.filter { $0.hasPrefix(SkillsTracing.prefix) })
    }

    /// Runs one search for the query marker. The selection tier has no
    /// model, thus it fails, and the retrieval fallback answers.
    ///
    /// - Parameters:
    ///   - registry: The registry whose catalog the search ranks.
    ///   - telemetry: The telemetry of the search agent.
    private static func search(registry: SkillsRegistry, telemetry: SkillsTracing.Telemetry) async throws {
        let items = registry.metadata()
        let agent = SkillSearchAgent(
            searcher: MetadataSearcher(items: items, mode: .selection),
            retrievalFallback: MetadataSearcher(items: items, mode: .retrieval),
            visibilityPredicate: { $0.isModelVisible }, telemetry: telemetry)
        _ = try await agent.answer(query: "\(skillID) \(queryMarker)", limit: searchLimit)
    }

    /// Adds one skill whose body holds the body marker, and waits for the
    /// one reload that the change gives.
    ///
    /// - Parameters:
    ///   - registry: The registry that watches `root`.
    ///   - root: The layer root to write the skill under.
    private static func reload(registry: SkillsRegistry, root: URL) async throws {
        let tally = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(registry.onReload, into: tally)
        defer { subscription.cancel() }
        try ReloadTestSupport.writeSkillFile(id: reloadedSkillID, in: root, body: bodyMarker)
        await ReloadTestSupport.expectExactlyOneEvent(tally)
    }
}
