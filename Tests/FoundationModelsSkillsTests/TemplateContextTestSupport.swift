import Foundation
import FoundationModelsExtras

@testable import FoundationModelsSkills

/// The fixture of the template context suites: one registry over one
/// project layer that holds one skill.
///
/// `TemplateContextRenderTests` and `PerRunTemplateContextTests` both call
/// it, thus the two suites build the same fixture.
enum TemplateContextTestSupport {
    /// A registry over one project layer that holds the skill `skillID`
    /// with `body`, a quoted `description`, and `files`.
    ///
    /// - Parameters:
    ///   - skillID: The id of the skill.
    ///   - body: The body of `SKILL.md`.
    ///   - description: The description of the skill, written quoted.
    ///     Defaults to `fixture.`.
    ///   - files: More files of the skill, by path relative to the directory
    ///     of the skill. Defaults to none.
    ///   - argumentNames: The `arguments:` names of the skill. Defaults to
    ///     none.
    ///   - templateContext: The template values of the registry.
    /// - Throws: Whatever `MarketplaceTestSupport.makeTempDirectory(withFiles:)`
    ///   throws.
    /// - Returns: The registry and the temporary root, which the caller
    ///   removes.
    static func registry(
        skillID: String, body: String, description: String = "fixture.", files: [String: String] = [:],
        argumentNames: [String] = [], templateContext: [String: TemplateValue]
    ) throws -> (registry: SkillsRegistry, root: URL) {
        let arguments = argumentNames.isEmpty ? "" : "arguments: [\(argumentNames.joined(separator: ", "))]\n"
        let skillFile = "---\nname: \(skillID)\ndescription: \"\(description)\"\n\(arguments)---\n\(body)"
        let layerFiles = ["\(skillID)/SKILL.md": skillFile].merging(
            files.map { ("\(skillID)/\($0.key)", $0.value) }
        ) { _, more in more }
        let root = try MarketplaceTestSupport.makeTempDirectory(withFiles: layerFiles)
        let registry = SkillsRegistry(
            layers: [DotfolderStack.Layer(source: .project, root: root)], mode: .open, templateContext: templateContext)
        return (registry, root)
    }
}
