import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsSkills

/// Tests of the template values of one agent run: `call(id:templateContext:)`,
/// `SkillsRegistry.with(templateContext:)` and
/// `SkillsCatalogTool.with(templateContext:)`.
///
/// Each case uses one registry whose own values turn the shell group off,
/// and gives the run values that turn it on, or the other way.
struct PerRunTemplateContextTests {
    /// The id of the skill that each case writes.
    private static let skillID = "run-task"

    /// The body under test: one text for each branch.
    private static let body = "{% if tools.shell.enabled %}SHELL-ON{% else %}SHELL-OFF{% endif %}"

    /// A context that turns the shell tool group on or off.
    ///
    /// - Parameter enabled: Whether the shell group is on.
    /// - Returns: The context `tools.shell.enabled = enabled`.
    private static func shellContext(enabled: Bool) -> [String: TemplateValue] {
        ["tools": .dictionary(["shell": .dictionary(["enabled": .bool(enabled)])])]
    }

    /// A registry over one project layer that holds the skill, with
    /// `templateContext` as its own values.
    ///
    /// - Parameter templateContext: The template values of the registry.
    /// - Returns: The registry and the temporary root, which the caller
    ///   removes.
    private static func registry(
        templateContext: [String: TemplateValue]
    ) throws -> (registry: SkillsRegistry, root: URL) {
        let root = try MarketplaceTestSupport.makeTempDirectory(withFiles: [
            "\(skillID)/SKILL.md": "---\nname: \(skillID)\ndescription: \"fixture.\"\n---\n\(body)"
        ])
        let registry = SkillsRegistry(
            layers: [DotfolderStack.Layer(source: .project, root: root)], mode: .open, templateContext: templateContext)
        return (registry, root)
    }

    /// The text that the registry gives with no run values, and the text
    /// with the opposite run values.
    private static let cases: [(registryEnabled: Bool, runEnabled: Bool, registryText: String, runText: String)] = [
        (false, true, "SHELL-OFF", "SHELL-ON"),
        (true, false, "SHELL-ON", "SHELL-OFF"),
    ]

    @Test(arguments: 0..<cases.count)
    func callRendersEachBranchFromThePerCallValues(caseIndex: Int) async throws {
        let item = Self.cases[caseIndex]
        let (registry, root) = try Self.registry(templateContext: Self.shellContext(enabled: item.registryEnabled))
        defer { try? FileManager.default.removeItem(at: root) }

        let runText = try await registry.call(
            id: Self.skillID, templateContext: Self.shellContext(enabled: item.runEnabled))

        #expect(runText == item.runText)
    }

    @Test(arguments: 0..<cases.count)
    func nilKeepsTheRegistryValues(caseIndex: Int) async throws {
        let item = Self.cases[caseIndex]
        let (registry, root) = try Self.registry(templateContext: Self.shellContext(enabled: item.registryEnabled))
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await registry.call(id: Self.skillID, templateContext: nil) == item.registryText)
        #expect(try await registry.call(id: Self.skillID) == item.registryText)
    }

    @Test func givenValuesReplaceTheRegistryValuesAndDoNotMerge() async throws {
        let (registry, root) = try Self.registry(templateContext: Self.shellContext(enabled: true))
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await registry.call(id: Self.skillID, templateContext: [:]) == "SHELL-OFF")
    }

    @Test func registryViewSharesTheCatalogAndTheReload() async throws {
        let (registry, root) = try Self.registry(templateContext: Self.shellContext(enabled: false))
        defer { try? FileManager.default.removeItem(at: root) }
        let view = registry.with(templateContext: Self.shellContext(enabled: true))

        try ReloadTestSupport.writeSkillFile(id: "added", in: root)
        registry.reload()

        #expect(view.metadata().map(\.id).sorted() == ["added", Self.skillID].sorted())
        #expect(try await view.call(id: Self.skillID) == "SHELL-ON")
        #expect(try await registry.call(id: Self.skillID) == "SHELL-OFF")
    }

    @Test(arguments: 0..<cases.count)
    func useSkillOfTheRunToolRendersWithTheRunValues(caseIndex: Int) async throws {
        let item = Self.cases[caseIndex]
        let (registry, root) = try Self.registry(templateContext: Self.shellContext(enabled: item.registryEnabled))
        defer { try? FileManager.default.removeItem(at: root) }
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        let shared = try SkillsTool.make(
            context: SkillsToolContext(
                registry: registry, searchAgent: SkillSearchAgent(searcher: searcher), mode: registry.mode,
                sandboxProbe: .fixed(false)))
        let run = try shared.with(templateContext: Self.shellContext(enabled: item.runEnabled))
        let use = GeneratedContent(properties: ["op": "use skill", "id": Self.skillID])

        let runAnswer = try await run.call(arguments: use)
        let sharedAnswer = try await shared.call(arguments: use)

        #expect(runAnswer.contains(item.runText))
        #expect(!runAnswer.contains(item.registryText))
        #expect(sharedAnswer.contains(item.registryText))
        #expect(!sharedAnswer.contains(item.runText))
        #expect(run.description == shared.description)
        #expect(run.skillIDs == shared.skillIDs)
        #expect(run.catalogNoticeBoard === shared.catalogNoticeBoard)
    }
}
