import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Testing

/// The live-model twin of `HotReloadTests` (plan.md §13's last paragraph):
/// the same MCP-style add and remove burst, this time against a
/// `.selection`-mode `MetadataSearcher` that a real model session backs, not
/// a scripted fake.
///
/// The session is a plain `LanguageModelSession`, which
/// `FoundationModelsRanker` makes conform to `AgentSession` and
/// `FoundationModelsMetadataRegistry` re-exports. That conformer adapts
/// Apple's own on-device `SystemLanguageModel` to the same `AgentSession`
/// seam every other conformer implements, thus this suite needs no new
/// dependency. `SelectionConfig.model`'s closure takes only the instructions
/// text and returns the bare session, and the session then uses its own
/// native guided generation instead of an externally supplied grammar (see
/// `LanguageModelSessionSupport.swift`), thus this file never names `Grammar`
/// and never imports `FoundationModelsRouter`.
///
/// **One gate: `SystemLanguageModel.default.isAvailable`.** A host with no
/// on-device Apple Intelligence model reports each test here as a Swift
/// Testing skip -- never a failure, and never a silent no-op.
///
/// **The default developer run changed, and the change is deliberate.** An
/// environment variable used to gate this suite as well, thus a plain `swift
/// test` never probed on-device model availability at all. Model
/// availability is now the only gate, thus a plain `swift test` on a machine
/// that has Apple Intelligence runs this suite by default. That is the trade,
/// and it is taken on purpose: the suite is one add and one remove burst,
/// thus it costs little, and a live path that nobody ever runs is a live path
/// that rots. CI makes the same split by test target instead of by
/// environment -- `.github/workflows/ci.yml` holds this suite out of the unit
/// job with `test-skip`, and runs it, and only it, in the integration job
/// with `integration-filter`.
@Suite("Gated live-model hot-reload twin (plan.md §13)")
struct HotReloadLiveTests {
    @Test(
        "an MCP-style add/remove burst stays searchable through a real .selection MetadataSearcher backed by the on-device model",
        .enabled(
            if: SystemLanguageModel.default.isAvailable,
            "SystemLanguageModel is unavailable on this host (see SystemLanguageModel.default.isAvailable); this test requires an on-device Apple Intelligence model."
        )
    )
    func addAndRemoveBurstStaysSearchableThroughARealSelectionSession() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "toolA", in: root, descriptionSuffix: "reads a file from disk")

        let config = SelectionConfig(model: { instructions in
            LanguageModelSession(model: .default, instructions: instructions)
        })
        // `watch: true` -- the twin's whole point is to drive a REAL reload
        // through the registry, not to read a catalog frozen at construction
        // time. `SkillsRegistry(roots:)` alone defaults to `watch: false`
        // (`metadata()` never changes after `init`, regardless of later
        // filesystem writes); this was the M4 regression the removal
        // assertion below silently passed against -- `toolA` was still in
        // the frozen catalog the whole time, so its "removal" was never
        // actually exercised.
        let registry = SkillsRegistry(roots: [root], watch: true)
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible), mode: .selection, selection: config)
        let agent = SkillSearchAgent(searcher: searcher)
        let reloadStream = try #require(registry.onReload, "watch: true must publish onReload")
        var reloads = reloadStream.makeAsyncIterator()

        // The MCP-style burst pattern `HotReloadTests`' deterministic
        // scenario and `FoundationModelsMetadataRegistryTests.HotReloadTests
        // .mcpStyleAddAndRemoveBurstStaysSearchableAndEmbedsOnlyNetNewItems()`
        // both exercise: forward every catalog change straight to
        // `update(items:)`. Awaiting one real `onReload` publication per
        // write -- rather than reading `registry.metadata()` immediately
        // after the write -- makes each forward wait for the watcher's
        // actual (debounced) reload, not a stale pre-reload snapshot.
        try Self.writeSkillFile(id: "toolB", in: root, descriptionSuffix: "writes a file to disk")
        let afterAdd = try #require(await reloads.next(), "expected a reload publication after adding toolB")
        await agent.update(items: afterAdd.filter(\.isModelVisible))

        let matches = try await agent.search(query: "read the contents of a file", limit: 5)
        #expect(matches.contains { $0.id == "toolA" })

        try FileManager.default.removeItem(at: root.appendingPathComponent("toolA", isDirectory: true))
        let afterRemoval = try #require(await reloads.next(), "expected a reload publication after removing toolA")
        await agent.update(items: afterRemoval.filter(\.isModelVisible))

        let afterRemovalMatches = try await agent.search(query: "read the contents of a file", limit: 5)
        #expect(!afterRemovalMatches.contains { $0.id == "toolA" })
    }

    // MARK: - Fixture file helpers

    /// Writes `id/SKILL.md` directly under `directory`, creating the skill's
    /// own subdirectory first if it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - descriptionSuffix: Text appended to `description:` -- the field
    ///     `SkillMetadata.renderBlock()` indexes.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFile(id: String, in directory: URL, descriptionSuffix: String) throws {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "---\nname: \(id)\ndescription: \(descriptionSuffix)\n---\nBody text for \(id).\n"
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
