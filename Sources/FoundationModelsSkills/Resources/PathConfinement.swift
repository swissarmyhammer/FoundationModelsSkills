import Foundation

/// The path-confinement invariant every resource operation enforces
/// (plan.md §7.3): a skill-relative path, symlinks resolved, must land
/// inside a layer directory of the skill.
///
/// Shared by `ListResource` (per enumerated entry) and `ReadResource` (its
/// `path` parameter) so the two operations can never drift on what counts
/// as an escape.
///
/// The unit of override is the file, thus a skill has more than one layer
/// directory and a legal file can be in a lower one. The list form reads each
/// of them; the one-directory form is that same form over a list of one, thus
/// the two can never differ.
internal enum PathConfinement {
    /// Resolves `relativePath` against `skillDirectory`, enforcing
    /// confinement.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to `skillDirectory`, e.g.
    ///     `"references/notes.md"`.
    ///   - skillDirectory: The skill's root directory.
    /// - Returns: The resolved, symlink-free URL, or `nil` when
    ///   `relativePath` is empty, absolute, `..`-traversing, or resolves --
    ///   directly or through a symlink -- outside `skillDirectory`.
    internal static func resolvedURL(relativePath: String, in skillDirectory: URL) -> URL? {
        Self.resolvedURL(relativePath: relativePath, in: [skillDirectory])
    }

    /// Resolves `relativePath` against the layer directories of one skill,
    /// enforcing confinement in each of them.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to a layer directory, e.g.
    ///     `"references/notes.md"`.
    ///   - directories: The layer directories of the skill, **highest
    ///     precedence first**. `SkillOverlay` gives them in that order.
    /// - Returns: The resolved, symlink-free URL of the winning copy, or
    ///   `nil` when `relativePath` is empty, absolute, `..`-traversing, or
    ///   resolves -- directly or through a symlink -- outside each of
    ///   `directories`.
    internal static func resolvedURL(relativePath: String, in directories: [URL]) -> URL? {
        Self.winningCopy(relativePath: relativePath, in: directories)?.url
    }

    /// The winning copy of `relativePath`, and which directory gave it.
    ///
    /// Reads `directories` in order and gives the first copy that exists and
    /// that is inside its own directory. When no directory holds the path,
    /// gives the resolved location in the first directory that confines it: a
    /// caller then reports that the file could not be read, and not that the
    /// path is denied.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to a layer directory.
    ///   - directories: The layer directories of the skill, highest
    ///     precedence first.
    /// - Returns: The URL of the winning copy and the position of its
    ///   directory in `directories`, or `nil` when no directory confines the
    ///   path.
    internal static func winningCopy(
        relativePath: String, in directories: [URL]
    ) -> (url: URL, directoryIndex: Int)? {
        guard Self.isWellFormedRelativePath(relativePath) else { return nil }
        let confinedCopies = directories.enumerated().compactMap { index, directory in
            Self.confinedURL(relativePath: relativePath, in: directory)
                .map { (url: $0, directoryIndex: index) }
        }
        let existing = confinedCopies.first { FileManager.default.fileExists(atPath: $0.url.path) }
        return existing ?? confinedCopies.first
    }

    /// The resolved location of `relativePath` in one directory, whether or
    /// not a file is there.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to `directory`, already checked by
    ///     `isWellFormedRelativePath(_:)`.
    ///   - directory: The layer directory to resolve against.
    /// - Returns: The resolved, symlink-free URL, or `nil` when it leaves
    ///   `directory`.
    private static func confinedURL(relativePath: String, in directory: URL) -> URL? {
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = Self.resolvingSymlinksOfExistingPrefix(
            directory.appendingPathComponent(relativePath))

        guard Self.isContained(resolvedCandidate, in: resolvedDirectory) else { return nil }
        return resolvedCandidate
    }

    /// Resolves the symlinks of the longest prefix of `url` that exists, and
    /// appends the remaining components unchanged.
    ///
    /// `resolvingSymlinksInPath()` normalizes a path that exists (on macOS
    /// it removes the `/private` prefix) but leaves a path that does not
    /// exist -- a missing file, a dangling symbolic link -- untouched. The
    /// skill directory always exists, so the candidate must be normalized
    /// through the same call on a path that exists, or the two paths do not
    /// share a prefix and every missing path reads as an escape.
    ///
    /// - Parameter url: The candidate URL.
    /// - Returns: The resolved, standardized URL.
    private static func resolvingSymlinksOfExistingPrefix(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var trailingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            trailingComponents.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath().standardizedFileURL
        for component in trailingComponents {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    /// Whether `path` is non-empty, genuinely relative, and free of `..`
    /// traversal -- checked on the literal string before any filesystem
    /// resolution, so `../x` and `/etc/passwd` are rejected even when
    /// nothing at that path exists to resolve.
    ///
    /// `CatalogPath` uses the same check for the paths of a marketplace
    /// catalog, so the two can never drift on what counts as relative.
    ///
    /// - Parameter path: The candidate path.
    /// - Returns: Whether `path` is well-formed.
    internal static func isWellFormedRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    /// Whether `candidate` is `root` itself or lives somewhere beneath it,
    /// comparing already-standardized, symlink-resolved paths.
    ///
    /// - Parameters:
    ///   - candidate: The resolved candidate path.
    ///   - root: The resolved root directory.
    /// - Returns: Whether `candidate` is contained within `root`.
    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    /// The corrective message for a `path` that `resolvedURL(relativePath:in:)`
    /// rejected -- shared by every resource operation that enforces
    /// confinement (`ReadResource`, `RunScript`), so they can never drift on
    /// its wording.
    ///
    /// - Parameter path: The path that was rejected.
    /// - Returns: The corrective message.
    internal static func deniedMessage(path: String) -> String {
        "The path `\(path)` is not accessible: it must resolve to a location inside the skill directory."
    }
}
