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
/// The `DotfolderStack` of `FoundationModelsExtras` walks the disk for
/// `entries()`, finds the winning copy for `resolve(_:)`, and reads a file for
/// `size(of:)`, `data(_:in:)` and `isExecutable(_:)`; `confines(_:)` asks the
/// `PathConfinement` of that same package. Thus this type opens no directory
/// and no file of its own.
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
    /// Does no I/O; only `resolve(_:)`, `entries()`, `size(of:)`,
    /// `data(_:in:)` and `isExecutable(_:)` touch disk.
    ///
    /// - Parameter directories: The layer directories of the skill, lowest
    ///   precedence first.
    internal init(directories: [URL]) {
        self.directories = directories
    }

    /// The winning copy of `relativePath`, and which layer directory gave it.
    ///
    /// Only a copy that exists resolves. The stack of one directory applies
    /// the confinement rule itself, thus a path that leaves its directory, and
    /// a path that no directory holds, give `nil` alike. A caller tells the
    /// two apart with `confines(_:)`.
    ///
    /// - Parameter relativePath: A path relative to a layer directory, e.g.
    ///   `"references/notes.md"`.
    /// - Returns: The URL of the winning copy and the position of its
    ///   directory in `directories`, or `nil` when no directory holds a
    ///   confined copy of the path.
    internal func resolve(_ relativePath: String) -> (url: URL, directoryIndex: Int)? {
        for index in directories.indices.reversed() {
            guard let url = Self.stack(over: [directories[index]]).nearest(relativePath) else { continue }
            return (url: url, directoryIndex: index)
        }
        return nil
    }

    /// Whether `relativePath` is well formed and stays inside the highest
    /// layer directory of the skill.
    ///
    /// The check opens no file of this package: the text half is
    /// `ResourcePathRules.isWellFormedRelativePath(_:)`, and the filesystem
    /// half is `PathConfinement.isConfined(_:to:)` of
    /// `FoundationModelsExtras`, the same rule each lookup of the stack
    /// applies. A caller asks this after `resolve(_:)` gave `nil`, to tell a
    /// path that no directory holds from a path that leaves the skill.
    ///
    /// - Parameter relativePath: A path relative to a layer directory.
    /// - Returns: Whether the path may name a file of the skill.
    internal func confines(_ relativePath: String) -> Bool {
        guard ResourcePathRules.isWellFormedRelativePath(relativePath),
            let highestDirectory = directories.last
        else {
            return false
        }
        return PathConfinement.isConfined(
            highestDirectory.appendingPathComponent(relativePath), to: highestDirectory)
    }

    /// Every file path of the skill, at every depth, each with its winning
    /// copy.
    ///
    /// The union of the layer directories: a path that only a lower directory
    /// holds is in the result, with the copy of that directory.
    ///
    /// The stack reads no file to make this view, thus a file whose bytes are
    /// not UTF-8 text -- an image under `assets/`, a compiled helper under
    /// `scripts/` -- is in the result as well. A caller that needs the bytes
    /// of such a file asks `data(_:in:)` for them.
    ///
    /// - Returns: A dictionary from the file path, relative to a layer
    ///   directory, to the URL of the winning copy. A directory that does not
    ///   exist adds nothing, and a file that leaves its own directory adds
    ///   nothing.
    internal func entries() -> [String: URL] {
        stack.urls().mapValues(\.url)
    }

    /// The size in bytes of the winning copy of `relativePath`.
    ///
    /// The stack reads the size, thus a caller that lists or reads a file of
    /// the skill opens no file of its own.
    ///
    /// - Parameter relativePath: A path relative to a layer directory.
    /// - Returns: The size of the winning copy, or `nil` when no directory
    ///   holds the path or the copy cannot be read.
    internal func size(of relativePath: String) -> Int? {
        stack.size(of: relativePath)
    }

    /// A part of the winning copy of `relativePath`, for a caller that pages a
    /// large file.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to a layer directory.
    ///   - range: The byte offsets to read. The result is shorter than `range`
    ///     when the file ends inside it, and empty when `range` starts at or
    ///     after the end of the file.
    /// - Returns: The bytes of the winning copy in `range`, or `nil` when no
    ///   directory holds the path or the copy cannot be read.
    internal func data(_ relativePath: String, in range: Range<Int>) -> Data? {
        stack.data(relativePath, in: range)
    }

    /// Whether the winning copy of `relativePath` carries the execute bit.
    ///
    /// The stack reads the mode, thus a caller that lists the files of the
    /// skill, or that runs a script of it, opens no file of its own. The copy
    /// of the highest layer directory that holds the path gives the answer,
    /// the same copy that `resolve(_:)` and `data(_:in:)` read.
    ///
    /// - Parameter relativePath: A path relative to a layer directory.
    /// - Returns: Whether the current user may run the winning copy. `false`
    ///   when no directory holds the path as well.
    internal func isExecutable(_ relativePath: String) -> Bool {
        stack.isExecutable(relativePath)
    }

    /// Every layer directory as one `DotfolderStack`, which gives the union of
    /// the paths, the size of a file, the bytes of a file and the execute bit
    /// of a file.
    private var stack: DotfolderStack {
        Self.stack(over: directories)
    }

    /// A `DotfolderStack` over `directories`.
    ///
    /// The whole overlay reads one stack of every directory, and `resolve(_:)`
    /// reads one stack of each single directory in turn, thus both make the
    /// stack here and neither one builds a layer of its own.
    ///
    /// The stack reads the root of a layer only, thus the source carries no
    /// meaning here. `.project` is the local source, the same source
    /// `SkillDiscovery.init(roots:)` gives a bare root. Making a stack opens no
    /// file; each lookup reads the disk at the time of the call.
    ///
    /// - Parameter directories: The layer directories, lowest precedence
    ///   first, which is the order the stack reads.
    /// - Returns: The stack over those directories.
    private static func stack(over directories: [URL]) -> DotfolderStack {
        DotfolderStack(layers: directories.map { DotfolderStack.Layer(source: .project, root: $0) })
    }
}
