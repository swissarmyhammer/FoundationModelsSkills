import Foundation
import FoundationModelsExtras

/// Directory-shaped skill discovery over the ordered layers of a
/// `DotfolderStack` (plan.md §3, §4).
///
/// An id is the name of a child directory of the union of the layer roots,
/// and it is a skill when a minimum of one layer gives that directory a
/// `SKILL.md`. The unit of override is the file: the highest layer that holds
/// a file gives that file, and each layer directory of the id contributes the
/// files that no higher layer holds. `discover()` reports every one of them
/// on `DiscoveredSkill.contributingDirectories`.
///
/// `DotfolderStack` gives the combined view and does each walk of the disk
/// (`childDirectories(of:)`, `locate(_:)`), thus this type opens no directory
/// of its own. No YAML parsing happens here; discovery is purely structural,
/// and construction does no I/O -- only `discover()` touches disk.
public struct SkillDiscovery: Sendable {
    /// The filename a layer directory must hold for its id to be a skill.
    /// ``SkillMarketplaceLayout/skills`` gives the same name to the
    /// marketplace reader, thus a marketplace snapshot holds the same shape.
    internal static let skillFileName = "SKILL.md"

    /// Directory names never treated as skill candidates, checked against
    /// the child directories of the layer roots.
    /// ``SkillMarketplaceLayout/skills`` gives the same names to the
    /// marketplace reader, thus its scan skips the same directories.
    internal static let excludedDirectoryNames: Set<String> = [".git", "node_modules"]

    /// The layers to discover over, lowest precedence first.
    public var layers: [DotfolderStack.Layer]

    /// Creates a `SkillDiscovery` over an explicit, ordered list of layers.
    ///
    /// Performs no I/O; a layer whose root does not exist on disk simply
    /// gives nothing once `discover()` runs.
    ///
    /// - Parameter layers: The layers to discover over, lowest precedence
    ///   first.
    public init(layers: [DotfolderStack.Layer]) {
        self.layers = layers
    }

    /// Creates a `SkillDiscovery` over bare layer roots, for a host that has
    /// roots and no layers.
    ///
    /// Each root becomes a `.project` layer, the source `SkillsRegistry`
    /// gives a bare root as well: a bare `[URL]` carries no trust signal of
    /// its own, and `.project` is the local source that the render policy of
    /// the host then gates.
    ///
    /// - Parameter roots: The layer roots to discover over, lowest precedence
    ///   first.
    public init(roots: [URL]) {
        self.init(layers: roots.map { DotfolderStack.Layer(source: .project, root: $0) })
    }

    /// Creates a `SkillDiscovery` over the layers of a `DotfolderStack`.
    ///
    /// `DotfolderStack.layers` is already ordered lowest precedence first
    /// (`defaults < user < project`), which is the order `discover()` expects,
    /// thus this is a direct projection with no reordering.
    ///
    /// - Parameter stack: The dotfolder stack to take the layers from.
    public init(stack: DotfolderStack) {
        self.init(layers: stack.layers)
    }

    /// Discovers every skill of the combined view of `layers`.
    ///
    /// Takes each child directory name of the union of the layer roots
    /// (skipping `.git` and `node_modules`), and keeps the names that a
    /// minimum of one layer gives a `SKILL.md`. The highest such layer gives
    /// the `SKILL.md` of the skill; each layer directory of the name, that
    /// layer included, is a contributing directory.
    ///
    /// - Returns: One `DiscoveredSkill` per distinct id found, sorted by id.
    public func discover() -> [DiscoveredSkill] {
        let stack = DotfolderStack(layers: layers)
        return stack.childDirectories()
            .filter { name, _ in !Self.excludedDirectoryNames.contains(name) }
            .compactMap { name, holdingLayers in
                discoveredSkill(id: name, holdingLayers: holdingLayers, in: stack)
            }
            .sorted { $0.id < $1.id }
    }

    /// Builds the record of one id, or gives `nil` when no layer of the id
    /// holds a `SKILL.md`.
    ///
    /// - Parameters:
    ///   - id: The child directory name of the union of the layer roots.
    ///   - holdingLayers: The layers that hold a directory of that name,
    ///     lowest precedence first.
    ///   - stack: The stack of `layers`, which locates the `SKILL.md` copies.
    /// - Returns: The record of the id, or `nil` when the id is no skill.
    private func discoveredSkill(
        id: String, holdingLayers: [DotfolderStack.Layer], in stack: DotfolderStack
    ) -> DiscoveredSkill? {
        let skillFilePaths = Set(stack.locate("\(id)/\(Self.skillFileName)").map(\.path))
        let contributingDirectories = Self.contributingDirectories(
            id: id, holdingLayers: holdingLayers, layers: layers)
        let winner = contributingDirectories.last {
            skillFilePaths.contains(Self.skillFileURL(in: $0.skillDirectory).path)
        }
        guard let winner else { return nil }
        return DiscoveredSkill(
            id: id, skillDirectory: winner.skillDirectory,
            skillFileURL: Self.skillFileURL(in: winner.skillDirectory),
            rootIndex: winner.rootIndex, root: winner.root,
            contributingDirectories: contributingDirectories)
    }

    /// The layer directories of `id`, lowest precedence first.
    ///
    /// `holdingLayers` names which layers hold the directory; `layers` gives
    /// each of them the position that `DiscoveredSkill.rootIndex` and the
    /// marketplace provenance of `SkillsRegistry` are keyed by.
    ///
    /// - Parameters:
    ///   - id: The child directory name of the union of the layer roots.
    ///   - holdingLayers: The layers that hold a directory of that name.
    ///   - layers: Every layer, lowest precedence first.
    /// - Returns: One contributing directory per holding layer, lowest
    ///   precedence first.
    private static func contributingDirectories(
        id: String, holdingLayers: [DotfolderStack.Layer], layers: [DotfolderStack.Layer]
    ) -> [DiscoveredSkill.ContributingDirectory] {
        let holdingRootPaths = Set(holdingLayers.map(\.root.path))
        return layers.enumerated()
            .filter { holdingRootPaths.contains($0.element.root.path) }
            .map { rootIndex, layer in
                DiscoveredSkill.ContributingDirectory(
                    rootIndex: rootIndex, root: layer.root,
                    skillDirectory: layer.root.appendingPathComponent(id, isDirectory: true))
            }
    }

    /// The `SKILL.md` of one skill directory.
    ///
    /// - Parameter skillDirectory: A layer directory of a skill.
    /// - Returns: The `SKILL.md` file of that directory, whether or not it
    ///   exists on disk.
    private static func skillFileURL(in skillDirectory: URL) -> URL {
        skillDirectory.appendingPathComponent(Self.skillFileName)
    }
}
