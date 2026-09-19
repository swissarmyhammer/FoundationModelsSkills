import Foundation
import FoundationModelsExtras

/// The combined view of one skill over the layer directories that contribute
/// to it (plan.md §3, §7.3).
///
/// The unit of override is the file: for a path of the skill, the copy in the
/// highest layer directory that holds it wins, and a file that only a lower
/// directory holds stays visible. Each resource operation reads the files of a
/// skill through this type, thus `list resource`, `read resource` and
/// `run script` can never differ on which copy of a file they give.
///
/// `DotfolderStack` walks the disk for `entries()`, and `PathConfinement`
/// resolves one path for `resolve(_:)`, thus this type opens no directory of
/// its own.
internal struct SkillOverlay: Sendable {
    /// The layer directories of the skill, lowest precedence first.
    ///
    /// The order is the order of `DiscoveredSkill.contributingDirectories`,
    /// thus the `directoryIndex` that `resolve(_:)` gives is the position of
    /// that contributing directory, and a caller reads the layer of the copy
    /// from it.
    internal var directories: [URL]

    /// Creates an overlay over the layer directories of one skill.
    ///
    /// Does no I/O; only `resolve(_:)` and `entries()` touch disk.
    ///
    /// - Parameter directories: The layer directories of the skill, lowest
    ///   precedence first.
    internal init(directories: [URL]) {
        self.directories = directories
    }

    /// The winning copy of `relativePath`, and which layer directory gave it.
    ///
    /// A path that no directory holds still resolves, in the highest
    /// directory that confines it: the caller then reports that the file
    /// could not be read, and not that the path is denied.
    ///
    /// - Parameter relativePath: A path relative to a layer directory, e.g.
    ///   `"references/notes.md"`.
    /// - Returns: The URL of the winning copy and the position of its
    ///   directory in `directories`, or `nil` when the path is empty,
    ///   absolute, `..`-traversing, or leaves each of the directories.
    internal func resolve(_ relativePath: String) -> (url: URL, directoryIndex: Int)? {
        PathConfinement.winningCopy(relativePath: relativePath, in: highestFirstDirectories)
            .map { (url: $0.url, directoryIndex: lowestFirstIndex(of: $0.directoryIndex)) }
    }

    /// Every file path of the skill, at every depth, each with its winning
    /// copy.
    ///
    /// The union of the layer directories: a path that only a lower directory
    /// holds is in the result, with the copy of that directory.
    ///
    /// - Returns: A dictionary from the file path, relative to a layer
    ///   directory, to the URL of the winning copy. A directory that does not
    ///   exist adds nothing, and a file that leaves its own directory adds
    ///   nothing.
    internal func entries() -> [String: URL] {
        DotfolderStack(layers: layers).tree().mapValues(\.url)
    }

    /// The layer directories as the layers of a `DotfolderStack`, lowest
    /// precedence first, which is the order the stack reads.
    ///
    /// The stack reads the root of a layer only, thus the source carries no
    /// meaning here. `.project` is the local source, the same source
    /// `SkillDiscovery.init(roots:)` gives a bare root.
    private var layers: [DotfolderStack.Layer] {
        directories.map { DotfolderStack.Layer(source: .project, root: $0) }
    }

    /// The layer directories highest precedence first, which is the order
    /// `PathConfinement` reads.
    private var highestFirstDirectories: [URL] {
        directories.reversed()
    }

    /// Turns a position of `highestFirstDirectories` into a position of
    /// `directories`.
    ///
    /// - Parameter highestFirstIndex: The position of a directory in
    ///   `highestFirstDirectories`.
    /// - Returns: The position of that same directory in `directories`.
    private func lowestFirstIndex(of highestFirstIndex: Int) -> Int {
        directories.count - 1 - highestFirstIndex
    }
}
