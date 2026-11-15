import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Testing

/// The live-model twin of `HotReloadTests` (a unit suite of the root package):
/// the same MCP-style add and remove burst, this time against a
/// `.selection`-mode `MetadataSearcher` that a real model session backs, not
/// a scripted fake.
///
/// The model is Apple's own on-device `SystemLanguageModel.default`.
/// `SelectionConfig` takes it directly. For each prompt, the selection tier
/// makes a plain `LanguageModelSession` on that model, and the session uses
/// its own native guided generation for the answer. Thus this suite needs no
/// new dependency, and it never names a grammar.
///
/// **One gate: `SystemLanguageModel.default.isAvailable`.** A host with no
/// on-device Apple Intelligence model reports each test here as a Swift
/// Testing skip -- never a failure, and never a silent no-op.
///
/// **Where this suite runs.** It is in the nested `IntegrationTests`
/// package, not in the root test target. Thus a plain `swift test` at the
/// repository root never runs it, and
/// `swift test --package-path IntegrationTests` runs it. In CI, the
/// `integration-package-path` input of `.github/workflows/ci.yml` makes the
/// integration job of the shared workflow run this package, on a runner that
/// has Apple Intelligence.
@Suite("Gated live-model hot-reload twin")
struct HotReloadLiveTests {
    @Test(
        "an MCP-style add/remove burst stays searchable through a real .selection MetadataSearcher backed by the on-device model",
        .enabled(
            if: SystemLanguageModel.default.isAvailable,
            "SystemLanguageModel is unavailable on this host (see SystemLanguageModel.default.isAvailable); this test requires an on-device Apple Intelligence model."
        )
    )
    func addAndRemoveBurstStaysSearchableThroughARealSelectionSession() async throws {
        let root = try TemporaryDirectory.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "toolA", in: root, descriptionSuffix: "reads a file from disk")

        let config = SelectionConfig(model: SystemLanguageModel.default)
        // `watch: true` -- the twin's whole point is to drive a REAL reload
        // through the registry, not to read a catalog frozen at construction
        // time. `SkillsRegistry(roots:mode:)` alone defaults to `watch: false`
        // (`metadata()` never changes after `init`, regardless of later
        // filesystem writes). With a frozen catalog, `toolA` stays in the
        // catalog, and the removal assertion below proves nothing.
        let registry = SkillsRegistry(roots: [root], mode: .open, watch: true)
        let searcher = MetadataSearcher(
            items: registry.metadata().filter(\.isModelVisible), mode: .selection, selection: config)
        let agent = SkillSearchAgent(searcher: searcher)
        var reloads = registry.onReload.makeAsyncIterator()

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
