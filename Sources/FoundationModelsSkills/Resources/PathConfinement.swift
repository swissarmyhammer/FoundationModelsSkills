import Foundation

/// The path-confinement invariant every resource operation enforces
/// (plan.md §7.3): a skill-relative path, symlinks resolved, must land
/// inside the skill directory.
///
/// Shared by `ListResource` (per enumerated entry) and `ReadResource` (its
/// `path` parameter) so the two operations can never drift on what counts
/// as an escape.
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
        guard Self.isWellFormedRelativePath(relativePath) else { return nil }

        let resolvedDirectory = skillDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate =
            skillDirectory
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        guard Self.isContained(resolvedCandidate, in: resolvedDirectory) else { return nil }
        return resolvedCandidate
    }

    /// Whether `path` is non-empty, genuinely relative, and free of `..`
    /// traversal -- checked on the literal string before any filesystem
    /// resolution, so `../x` and `/etc/passwd` are rejected even when
    /// nothing at that path exists to resolve.
    ///
    /// - Parameter path: The candidate path.
    /// - Returns: Whether `path` is well-formed.
    private static func isWellFormedRelativePath(_ path: String) -> Bool {
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
