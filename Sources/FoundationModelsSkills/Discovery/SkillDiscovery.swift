import Foundation
import FoundationModelsExtras

/// Directory-shaped skill discovery over an ordered list of host-supplied
/// layer roots (plan.md §3, §4; decisions #3/#19/#29).
///
/// Walks each root's immediate subdirectories for a `SKILL.md` -- `name/SKILL.md`,
/// one level below the root, never recursed further -- and folds the results
/// by directory name, last root wins (decision #3's full-replace rule). This
/// type names no directory convention of its own: `roots` is entirely the
/// host's choice, lowest precedence first (decision #29, amended
/// 2026-07-28). `DotfolderStack` is one convenience for computing such a
/// list, not the interface -- `init(stack:)` adapts it in one step. No YAML
/// parsing happens here; discovery is purely structural, and construction
/// does no I/O of its own -- only `discover()` touches disk.
public struct SkillDiscovery: Sendable {
    /// The filename every skill directory must contain to be discovered.
    private static let skillFileName = "SKILL.md"

    /// Directory names never treated as skill candidates, checked against
    /// each root's immediate subdirectories.
    private static let excludedDirectoryNames: Set<String> = [".git", "node_modules"]

    /// The layer roots to discover over, lowest precedence first.
    public var roots: [URL]

    /// Creates a `SkillDiscovery` over an explicit, ordered list of layer
    /// roots.
    ///
    /// Performs no I/O; a root that does not exist on disk is simply skipped
    /// once `discover()` runs.
    ///
    /// - Parameter roots: The layer roots to discover over, lowest precedence
    ///   first.
    public init(roots: [URL]) {
        self.roots = roots
    }

    /// Creates a `SkillDiscovery` over the roots a `DotfolderStack` derives.
    ///
    /// A one-line convenience over `init(roots:)` for hosts that already use
    /// `DotfolderStack` to compute their layer roots -- equivalent to
    /// `init(roots: Self.roots(from: stack))`.
    ///
    /// - Parameter stack: The dotfolder stack to derive layer roots from.
    public init(stack: DotfolderStack) {
        self.init(roots: Self.roots(from: stack))
    }

    /// Maps a `DotfolderStack`'s layers to an ordered list of layer roots.
    ///
    /// `DotfolderStack.layers` is already ordered lowest precedence first
    /// (`defaults < user < project`), matching what `discover()` expects, so
    /// this is a direct projection with no reordering.
    ///
    /// - Parameter stack: The dotfolder stack to derive layer roots from.
    /// - Returns: `stack`'s layer roots, lowest precedence first.
    public static func roots(from stack: DotfolderStack) -> [URL] {
        stack.layers.map(\.root)
    }

    /// Discovers every skill directory across `roots`.
    ///
    /// For each root, in order, enumerates its immediate subdirectories and
    /// keeps the ones containing a `SKILL.md` (skipping `.git` and
    /// `node_modules` by name, and any root that does not exist or cannot be
    /// read). A later root's copy of an id fully replaces an earlier root's
    /// copy of the same id (decision #3); the replaced copy is recorded on
    /// the surviving record's `shadowedCandidates` rather than discarded.
    ///
    /// - Returns: One `DiscoveredSkill` per distinct id found, sorted by id.
    public func discover() -> [DiscoveredSkill] {
        var discoveredByID: [String: DiscoveredSkill] = [:]

        for (rootIndex, root) in roots.enumerated() {
            for skillDirectory in Self.candidateSkillDirectories(under: root) {
                let skillFileURL = skillDirectory.appendingPathComponent(Self.skillFileName)
                guard FileManager.default.fileExists(atPath: skillFileURL.path) else { continue }

                let id = skillDirectory.lastPathComponent
                discoveredByID[id] = Self.fold(
                    previous: discoveredByID[id],
                    id: id, skillDirectory: skillDirectory, skillFileURL: skillFileURL,
                    rootIndex: rootIndex, root: root)
            }
        }

        return discoveredByID.values.sorted { $0.id < $1.id }
    }

    /// Builds the `DiscoveredSkill` a newly found candidate replaces
    /// `previous` with, carrying `previous` forward onto
    /// `shadowedCandidates` when there was one.
    ///
    /// - Parameters:
    ///   - previous: The current record for this id, if a lower-precedence
    ///     root already contributed one; `nil` on a first sighting.
    ///   - id: The candidate's id.
    ///   - skillDirectory: The candidate's own skill directory.
    ///   - skillFileURL: The candidate's `SKILL.md` file.
    ///   - rootIndex: The candidate's root's position in `roots`.
    ///   - root: The candidate's root.
    /// - Returns: The new winning record for `id`.
    private static func fold(
        previous: DiscoveredSkill?,
        id: String, skillDirectory: URL, skillFileURL: URL, rootIndex: Int, root: URL
    ) -> DiscoveredSkill {
        var shadowedCandidates = previous?.shadowedCandidates ?? []
        if let previous {
            shadowedCandidates.append(
                DiscoveredSkill.ShadowedCandidate(
                    rootIndex: previous.rootIndex, root: previous.root, skillDirectory: previous.skillDirectory))
        }
        return DiscoveredSkill(
            id: id, skillDirectory: skillDirectory, skillFileURL: skillFileURL,
            rootIndex: rootIndex, root: root, shadowedCandidates: shadowedCandidates)
    }

    /// Lists `root`'s immediate subdirectories eligible to be skill
    /// candidates: real directories, excluding `.git` and `node_modules` by
    /// name.
    ///
    /// Never recurses past this one level, and never fails: a `root` that
    /// does not exist, or cannot be read, contributes no candidates.
    ///
    /// - Parameter root: The layer root to scan.
    /// - Returns: `root`'s eligible immediate subdirectories, in whatever
    ///   order `FileManager` returns them.
    private static func candidateSkillDirectories(under root: URL) -> [URL] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else {
            return []
        }
        return entries.filter(Self.isEligibleSkillDirectoryCandidate)
    }

    /// Reports whether `entry` is an immediate root subdirectory eligible to
    /// be a skill candidate.
    ///
    /// - Parameter entry: One entry `FileManager.contentsOfDirectory` returned
    ///   for a layer root.
    /// - Returns: `true` if `entry` is a real directory whose name is not in
    ///   `excludedDirectoryNames`.
    private static func isEligibleSkillDirectoryCandidate(_ entry: URL) -> Bool {
        guard !Self.excludedDirectoryNames.contains(entry.lastPathComponent) else { return false }
        return (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
