import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// Tests for the session template context of a host: the structured values
/// that `SkillsRegistry` gives to pass 3, thus a skill can branch on the tool
/// configuration of the session, for example
/// `{% if tools.kanban.enabled %}…{% endif %}`.
///
/// Each case runs through a real registry over a temporary layer, thus the
/// body render, the description render and an include of a file of the skill
/// all go through the same `StencilPass`.
struct TemplateContextRenderTests {
    /// The id of the skill that each case writes.
    private static let skillID = "do-task"

    /// The conditional text under test.
    private static let conditional = "{% if tools.kanban.enabled %}K{% endif %}"

    /// The path of the reference file, relative to the directory of the skill.
    private static let referencePath = "references/code.md"

    /// A context that turns the kanban tool group on or off.
    ///
    /// - Parameter enabled: Whether the kanban group is on.
    /// - Returns: The context `tools.kanban.enabled = enabled`.
    private static func kanbanContext(enabled: Bool) -> [String: TemplateValue] {
        ["tools": .dictionary(["kanban": .dictionary(["enabled": .bool(enabled)])])]
    }

    /// A registry over one project layer that holds the skill with `body`,
    /// a quoted `description`, and the reference file.
    ///
    /// - Parameters:
    ///   - body: The body of `SKILL.md`.
    ///   - description: The description of the skill, written quoted.
    ///   - reference: The text of the reference file.
    ///   - argumentNames: The `arguments:` names of the skill.
    ///   - templateContext: The session template context of the registry.
    /// - Returns: The registry and the temporary root, which the caller
    ///   removes.
    private static func registry(
        body: String, description: String = "fixture.", reference: String = "",
        argumentNames: [String] = [], templateContext: [String: TemplateValue]
    ) throws -> (registry: SkillsRegistry, root: URL) {
        let arguments = argumentNames.isEmpty ? "" : "arguments: [\(argumentNames.joined(separator: ", "))]\n"
        let root = try MarketplaceTestSupport.makeTempDirectory(withFiles: [
            "\(skillID)/SKILL.md": "---\nname: \(skillID)\ndescription: \"\(description)\"\n\(arguments)---\n\(body)",
            "\(skillID)/\(referencePath)": reference,
        ])
        let registry = SkillsRegistry(
            layers: [DotfolderStack.Layer(source: .project, root: root)], mode: .open, templateContext: templateContext)
        return (registry, root)
    }

    /// The context cases: the context, and the text the conditional renders.
    private static let contextCases: [(context: [String: TemplateValue], expected: String)] = [
        (kanbanContext(enabled: true), "K"),
        (kanbanContext(enabled: false), ""),
        ([:], ""),
    ]

    @Test(arguments: 0..<contextCases.count)
    func aBodyConditionalFollowsTheContext(caseIndex: Int) async throws {
        let (context, expected) = Self.contextCases[caseIndex]
        let (registry, root) = try Self.registry(body: Self.conditional, templateContext: context)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await registry.call(id: Self.skillID) == expected)
    }

    @Test(arguments: 0..<contextCases.count)
    func anIncludedFileOfTheSkillRendersWithTheSameContext(caseIndex: Int) async throws {
        let (context, expected) = Self.contextCases[caseIndex]
        let (registry, root) = try Self.registry(
            body: "{% include \"\(Self.referencePath)\" %}", reference: Self.conditional, templateContext: context)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await registry.call(id: Self.skillID) == expected)
    }

    @Test(arguments: 0..<contextCases.count)
    func aDescriptionConditionalFollowsTheContext(caseIndex: Int) throws {
        let (context, expected) = Self.contextCases[caseIndex]
        let (registry, root) = try Self.registry(
            body: "", description: "D\(Self.conditional)", templateContext: context)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(registry.metadata().first { $0.id == Self.skillID }?.description == "D\(expected)")
    }

    @Test func aNamedArgumentBeatsAContextValueOfTheSameName() async throws {
        let (registry, root) = try Self.registry(
            body: "{{ tools }}|$ARGUMENTS", argumentNames: ["tools"],
            templateContext: Self.kanbanContext(enabled: true))
        defer { try? FileManager.default.removeItem(at: root) }

        // `$ARGUMENTS` in the body keeps the registry from appending its own
        // `ARGUMENTS:` line.
        #expect(try await registry.call(id: Self.skillID, arguments: ["given"]) == "given|given")
    }

    @Test func aContextValueBeatsAnEnvironmentValueOfTheSameName() throws {
        let pass = StencilPass(
            environment: ["HOME": "/from/environment"], templateContext: ["HOME": .string("context")])
        let request = RenderRequest(
            text: "{{ HOME }}", skillDirectory: URL(fileURLWithPath: "/tmp/skill", isDirectory: true),
            winningLayer: DotfolderStack.Layer(source: .project, root: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            policy: RenderPolicy())

        let rendered = try pass.render(QuarantinedText(original: request.text), request: request).flattened

        #expect(rendered == "context")
    }
}
