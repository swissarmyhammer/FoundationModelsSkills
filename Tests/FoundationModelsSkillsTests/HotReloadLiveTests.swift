import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Testing

/// The gated, live-model twin of `HotReloadTests` (plan.md §13's last
/// paragraph): the same add/remove burst, this time against a `.selection`-
/// mode `MetadataSearcher` backed by a genuinely live model session, not a
/// scripted fake.
///
/// **Deviation from a literal Router-backed twin, disclosed:** plan.md's
/// text names "a live Router selection session," mirroring
/// `FoundationModelsMetadataRegistry`'s own gated
/// `RouterIntegrationTests.swift`, which resolves tiny `mlx-community`
/// models through `FoundationModelsRouter` + MLX + Hugging Face. Wiring that
/// same machinery here would mean adding `FoundationModelsRouter`,
/// `MLXHuggingFace`, `MLXLMCommon`, `HuggingFace`, and `Tokenizers` as new
/// test-target-only dependencies -- several hundred lines of tiny-model
/// resolution/download plumbing -- solely for one gated file this package
/// has never otherwise needed. This package's real dependency graph already
/// gives every `AgentSession` conformer a genuinely live alternative with
/// zero new dependencies: `FoundationModelsRanker`'s
/// `LanguageModelSession: AgentSession` conformance (re-exported here via
/// `FoundationModelsMetadataRegistry`'s `@_exported import
/// FoundationModelsRanker`), which adapts Apple's own on-device
/// `SystemLanguageModel` to the same `AgentSession` seam `RoutedAgentSession`
/// implements for Router. This suite drives that conformer instead --
/// `SelectionConfig.model`'s closure ignores the `Grammar` argument (a plain
/// `LanguageModelSession` relies on its own native guided generation, not an
/// externally supplied grammar; see `LanguageModelSessionSupport.swift`'s doc
/// comment), so this file never needs to name `Grammar` and therefore never
/// needs to `import FoundationModelsRouter` at all. The scenario itself --
/// the MCP-style add/remove burst against a real selection session -- is
/// unchanged; only which live model backs it differs.
///
/// Gated exactly like `FoundationModelsMCPTests.E2ETests` (mirroring its
/// two-part gate): the ``skillsIntegrationEnvVar`` environment variable must
/// be `"1"`, and even then `SystemLanguageModel.default.isAvailable` must be
/// `true` -- both surfaced as a Swift Testing skip, never a failure and never
/// a silent no-op.
@Suite("Gated live-model hot-reload twin (plan.md §13)")
struct HotReloadLiveTests {
    /// The environment variable that must be set to exactly `"1"` to enable
    /// this gated suite.
    private static let skillsIntegrationEnvVar = "SKILLS_INTEGRATION_TESTS"

    /// Whether ``skillsIntegrationEnvVar`` is set to `"1"` in this process's
    /// environment.
    private static var isIntegrationFlagSet: Bool {
        ProcessInfo.processInfo.environment[skillsIntegrationEnvVar] == "1"
    }

    /// Whether it's safe to proceed past the model-availability gate.
    ///
    /// `true` whenever ``isIntegrationFlagSet`` is `false`, without ever
    /// touching `SystemLanguageModel` -- so the default (ungated) `swift
    /// test` run never probes on-device model availability at all, only this
    /// suite's own environment-variable check. Only once
    /// ``isIntegrationFlagSet`` is `true` does this actually consult
    /// `SystemLanguageModel.default.isAvailable`.
    private static var modelAvailabilityGatePasses: Bool {
        !Self.isIntegrationFlagSet || SystemLanguageModel.default.isAvailable
    }

    @Test(
        "an MCP-style add/remove burst stays searchable through a real .selection MetadataSearcher backed by the on-device model",
        .enabled(
            if: Self.isIntegrationFlagSet,
            "Set SKILLS_INTEGRATION_TESTS=1 to run this gated live-model test."
        ),
        .enabled(
            if: Self.modelAvailabilityGatePasses,
            "SystemLanguageModel is unavailable on this host (see SystemLanguageModel.default.isAvailable); this test requires an on-device Apple Intelligence model."
        )
    )
    func addAndRemoveBurstStaysSearchableThroughARealSelectionSession() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeSkillFile(id: "toolA", in: root, descriptionSuffix: "reads a file from disk")

        let config = SelectionConfig(model: { instructions, _ in
            LanguageModelSession(model: .default, instructions: instructions)
        })
        let registry = SkillsRegistry(roots: [root])
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible), mode: .selection, selection: config)
        let agent = SkillSearchAgent(searcher: searcher)

        // The MCP-style burst pattern `HotReloadTests`' deterministic
        // scenario and `FoundationModelsMetadataRegistryTests.HotReloadTests
        // .mcpStyleAddAndRemoveBurstStaysSearchableAndEmbedsOnlyNetNewItems()`
        // both exercise: forward every catalog change straight to
        // `update(items:)`, without coalescing.
        try Self.writeSkillFile(id: "toolB", in: root, descriptionSuffix: "writes a file to disk")
        await agent.update(items: registry.metadata().filter(\.isModelVisible))

        let matches = try await agent.search(query: "read the contents of a file", limit: 5)
        #expect(matches.contains { $0.id == "toolA" })

        try FileManager.default.removeItem(at: root.appendingPathComponent("toolA", isDirectory: true))
        await agent.update(items: registry.metadata().filter(\.isModelVisible))

        let afterRemoval = try await agent.search(query: "read the contents of a file", limit: 5)
        #expect(!afterRemoval.contains { $0.id == "toolA" })
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
