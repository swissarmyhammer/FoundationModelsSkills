import Foundation
import FoundationModelsExtras

/// The first step of an `{% include %}`: a file of the skill, before the
/// `_partials/` search.
///
/// An author writes `{% include "references/house-style.md" %}` in
/// `SKILL.md`, and the render puts the winning copy of that file of the skill
/// into the text. The search order is:
///
/// 1. a file of the skill, with the include name as a path relative to the
///    directory of the skill;
/// 2. the `_partials/` search of the stenciled stack.
///
/// Step 1 applies only to a name that ``isSkillFileName(_:)`` accepts, thus a
/// bare partial name such as `"header"` always goes to step 2.
///
/// Step 1 searches only the directories of the skill whose layer is in the
/// partial scope of the winning layer: the winning marketplace layer plus the
/// local layers, or the local layers only. That is the same scope that the
/// stenciled stack applies to the `_partials/` search. Thus a trusted
/// `.defaults` skill never includes a file that only a marketplace layer
/// gives.
///
/// This type opens no file. The resolver asks a `DotfolderStack` of
/// `FoundationModelsExtras` for the text, and that stack applies its text
/// check and its symbolic-link confinement to each read. The stenciled stack
/// renders the text of the resolver the same as a partial: the same
/// variables, trust, limits and include-depth limit.
internal enum SkillFileInclude {
    /// The separator of the components of an include name.
    private static let pathSeparator: Character = "/"

    /// The resolver that gives the text of a file of the skill that an
    /// `{% include %}` names.
    ///
    /// - Parameter request: The render request that gives the layer
    ///   directories of the skill and the winning layer.
    /// - Returns: The resolver, or `nil` when no directory of the skill is in
    ///   the partial scope of the winning layer. The resolver gives `nil` for
    ///   a name that ``isSkillFileName(_:)`` refuses and for a file that no
    ///   directory in scope holds, thus the `_partials/` search then runs.
    internal static func resolver(for request: RenderRequest) -> StenciledDotfolderStack.IncludeResolver? {
        let directories = directoriesInScope(
            of: request.winningLayer, among: request.contributingDirectories)
        guard !directories.isEmpty else { return nil }
        let stack = DotfolderStack(
            layers: directories.map { DotfolderStack.Layer(source: $0.layer.source, root: $0.directory) })
        return { name in
            guard isSkillFileName(name) else { return nil }
            return stack.content(name)
        }
    }

    /// Whether an include name may name a file of the skill.
    ///
    /// The name must:
    ///
    /// - pass `ResourcePathRules.isWellFormedRelativePath(_:)` (not empty,
    ///   not absolute, no `..` component);
    /// - hold a minimum of one `/`, thus a bare partial name never names a
    ///   file of the skill;
    /// - not name `SKILL.md` of the skill;
    /// - hold no hidden path component (a component that starts with `.`),
    ///   the rule of `ResourcePathRules.hasHiddenComponent(_:)`.
    ///
    /// - Parameter name: The include name as the template wrote it.
    /// - Returns: Whether step 1 may search for `name`.
    internal static func isSkillFileName(_ name: String) -> Bool {
        guard ResourcePathRules.isWellFormedRelativePath(name), name.contains(pathSeparator) else {
            return false
        }
        let components = name.split(separator: pathSeparator).map(String.init)
        guard components != [SkillDiscovery.skillFileName] else { return false }
        return !ResourcePathRules.hasHiddenComponent(name)
    }

    /// The directories of the skill whose layer is in the partial scope of
    /// `winningLayer`.
    ///
    /// A skill of a `.marketplace` layer sees its own marketplace layer and
    /// each local layer. A skill of a local layer sees the local layers only.
    ///
    /// - Parameters:
    ///   - winningLayer: The layer that gives `SKILL.md`.
    ///   - directories: Every layer directory of the skill, lowest
    ///     precedence first.
    /// - Returns: The directories in scope, in the same order.
    private static func directoriesInScope(
        of winningLayer: DotfolderStack.Layer, among directories: [SkillsRegistry.ContributingDirectory]
    ) -> [SkillsRegistry.ContributingDirectory] {
        directories.filter { directory in
            guard directory.layer.source == .marketplace else { return true }
            return winningLayer.source == .marketplace
                && directory.layer.root.standardizedFileURL == winningLayer.root.standardizedFileURL
        }
    }
}
