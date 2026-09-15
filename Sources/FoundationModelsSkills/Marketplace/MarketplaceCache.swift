import Foundation

/// A value that the cache puts into a file path.
internal enum MarketplacePathValue: String, Sendable {
    /// The commit of a snapshot. It names a folder under `snapshots/`, and it
    /// is the target of the `current` symlink.
    case sha

    /// The branch or the tag. It names a file under `refs/`.
    case ref
}

/// Why the cache cannot finish a file operation (marketplace.md §7).
internal enum MarketplaceCacheError: Error, Equatable, Sendable {
    /// The cache cannot open or lock a file. The path names the file, and the
    /// code is the `errno` of the call.
    case cannotLock(path: String, code: Int32)

    /// The cache cannot put the new `current` symlink in place. The path names
    /// the symlink, and the code is the `errno` of `rename(2)`.
    case cannotSwap(path: String, code: Int32)

    /// A value cannot go into a cache path, because it is empty, it holds a
    /// path separator or a relative step, or it starts with a dot.
    case unsafePathValue(kind: MarketplacePathValue, value: String)

    /// A value is no commit, because it is not a hexadecimal object name.
    case notACommit(value: String)
}

extension MarketplaceCacheError: CustomStringConvertible {
    /// A sentence that tells the file and the error code.
    var description: String {
        switch self {
        case .cannotLock(let path, let code):
            #"Cannot lock "\#(path)": error code \#(code)."#
        case .cannotSwap(let path, let code):
            #"Cannot put the new snapshot link "\#(path)" in place: error code \#(code)."#
        case .unsafePathValue(let kind, let value):
            #"The \#(kind.rawValue) "\#(value)" cannot go into a cache path."#
        case .notACommit(let value):
            #"The sha "\#(value)" is no commit."#
        }
    }
}

/// The on-disk cache of one marketplace (marketplace.md §7.1, §7.2, §7.3, and
/// §7.6).
///
/// The cache does no network work. A caller fetches and materializes a
/// snapshot in a folder of its own, and then gives that folder to
/// ``install(snapshotAt:sha:ref:)``. The install puts the folder under
/// `snapshots/`, writes the ref file, and swaps the `current` symlink in one
/// `rename(2)`. Thus a reader sees the old snapshot or the new snapshot, and
/// never a folder that is half written.
///
/// ```
/// <cache>/
/// ├── state.json
/// └── <folderName>/
///     ├── repo.git/
///     ├── refs/<ref>
///     ├── snapshots/<sha>/
///     ├── current -> snapshots/<sha>
///     └── lock
/// ```
internal struct MarketplaceCache: Sendable {
    // MARK: - Names

    /// The environment variable that names the cache directory.
    static let cacheVariable = "SKILLS_MARKETPLACE_CACHE"

    /// The cache directory under the home folder, for an environment that
    /// does not name one.
    private static let homeCachePath = ".cache/skills/marketplaces"

    /// The name of the bare repository folder of one marketplace.
    private static let repositoryDirectoryName = "repo.git"

    /// The name of the folder that holds one file for each ref.
    private static let refsDirectoryName = "refs"

    /// The name of the folder that holds one folder for each snapshot.
    private static let snapshotsDirectoryName = "snapshots"

    /// The name of the symlink that names the snapshot the registry reads.
    private static let currentLinkName = "current"

    /// The name of the symlink that the swap makes before it renames the link
    /// over ``currentLinkName``.
    private static let stagedLinkName = "current.new"

    /// The name of the file that the writer lock holds.
    private static let lockFileName = "lock"

    /// The permissions of the lock file. Only the owner writes it.
    private static let lockFileMode: mode_t = 0o644

    // MARK: - Safe values in a path

    /// The characters of a hexadecimal object name.
    private static let hexDigits = Set("0123456789abcdefABCDEF")

    /// The number of hex digits of a SHA-1 object name.
    private static let sha1Length = 40

    /// The number of hex digits of a SHA-256 object name.
    private static let sha256Length = 64

    /// The lengths that the object name of a commit can have.
    private static let commitLengths: Set<Int> = [sha1Length, sha256Length]

    /// The relative step that walks to the parent folder.
    private static let relativeStep = ".."

    /// The characters that make a value more than one name.
    private static let pathSeparators: Set<Character> = ["/", "\\"]

    /// The character that starts a hidden name.
    private static let hiddenNamePrefix = "."

    /// Checks a value before it goes into a cache path (marketplace.md §7.2).
    ///
    /// Each path of the cache is one name inside the folder of the
    /// marketplace. Thus a value that is empty, that holds a separator or the
    /// relative step, that starts with a dot, or that holds a control
    /// character, can leave the cache folder, and the call refuses it.
    ///
    /// - Parameters:
    ///   - value: The value to check.
    ///   - kind: What the value names. The error tells it.
    /// - Returns: The value, which is now safe in a path.
    /// - Throws: ``MarketplaceCacheError/unsafePathValue(kind:value:)`` when
    ///   the value can leave the cache folder.
    static func validated(pathValue value: String, kind: MarketplacePathValue) throws -> String {
        let safe =
            !value.isEmpty
            && !value.hasPrefix(hiddenNamePrefix)
            && !value.contains(relativeStep)
            && !value.contains(where: pathSeparators.contains)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        guard safe else {
            throw MarketplaceCacheError.unsafePathValue(kind: kind, value: value)
        }
        return value
    }

    /// Checks a commit before it names a snapshot folder or a symlink target.
    ///
    /// A commit is a hexadecimal object name, so it is safe in a path and it
    /// holds no separator. The call proves both.
    ///
    /// - Parameter sha: The commit to check.
    /// - Returns: The commit, which is now safe in a path.
    /// - Throws: ``MarketplaceCacheError/unsafePathValue(kind:value:)`` or
    ///   ``MarketplaceCacheError/notACommit(value:)``.
    static func validated(sha: String) throws -> String {
        let value = try validated(pathValue: sha, kind: .sha)
        guard commitLengths.contains(value.count), value.allSatisfy(hexDigits.contains) else {
            throw MarketplaceCacheError.notACommit(value: value)
        }
        return value
    }

    /// Checks a branch or a tag before it names a file under `refs/`.
    ///
    /// The ref is one file name, so it holds no separator. A ref name with a
    /// `/` in it is refused.
    ///
    /// - Parameter ref: The branch or the tag to check.
    /// - Returns: The ref, which is now safe in a path.
    /// - Throws: ``MarketplaceCacheError/unsafePathValue(kind:value:)`` when
    ///   the ref can leave the cache folder.
    static func validated(ref: String) throws -> String {
        try validated(pathValue: ref, kind: .ref)
    }

    /// Whether a name is the object name of a commit.
    ///
    /// - Parameter name: The name to read, such as a folder name that the
    ///   file system gave.
    /// - Returns: `true` when the name is a commit that is safe in a path.
    private static func isCommit(name: String) -> Bool {
        (try? validated(sha: name)) != nil
    }

    // MARK: - Location

    /// The cache directory that `environment` names (marketplace.md §7.1).
    ///
    /// This is the pattern of `ModelResolver.hubCacheDirectory(environment:)`:
    /// the variable when it is set and not empty, else the standard folder
    /// under the home folder. The call is a pure function of the environment,
    /// so a test gives its own.
    ///
    /// - Parameter environment: The environment to read.
    /// - Returns: The cache directory.
    static func cacheDirectory(environment: [String: String]) -> URL {
        if let configured = environment[cacheVariable], !configured.isEmpty {
            return URL(
                fileURLWithPath: NSString(string: configured).expandingTildeInPath,
                isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(homeCachePath, isDirectory: true)
    }

    /// The state file of a cache directory.
    ///
    /// - Parameter root: The cache directory.
    /// - Returns: `<root>/state.json`.
    static func stateFile(inCacheDirectory root: URL) -> URL {
        root.appendingPathComponent(MarketplaceState.fileName)
    }

    // MARK: - The folder of one marketplace

    /// The cache directory that holds `state.json` and every marketplace
    /// folder.
    let root: URL

    /// The folder name of this marketplace, from
    /// ``MarketplaceIdentity/cacheFolderName(key:normalizedURL:)``.
    let folderName: String

    /// The folder of this marketplace: `<root>/<folderName>`.
    var folder: URL {
        root.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The bare repository that the fetch writes.
    var repositoryDirectory: URL {
        folder.appendingPathComponent(Self.repositoryDirectoryName, isDirectory: true)
    }

    /// The folder that holds one file for each ref.
    var refsDirectory: URL {
        folder.appendingPathComponent(Self.refsDirectoryName, isDirectory: true)
    }

    /// The folder that holds one folder for each snapshot.
    var snapshotsDirectory: URL {
        folder.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
    }

    /// The symlink that names the snapshot the registry reads.
    var currentLink: URL {
        folder.appendingPathComponent(Self.currentLinkName)
    }

    /// The file that the writer lock holds.
    var lockFile: URL {
        folder.appendingPathComponent(Self.lockFileName)
    }

    /// The folder of one snapshot.
    ///
    /// - Parameter sha: The commit of the snapshot.
    /// - Returns: `<folder>/snapshots/<sha>`.
    /// - Throws: ``MarketplaceCacheError`` when `sha` is no commit that is
    ///   safe in a path.
    func snapshotDirectory(forSha sha: String) throws -> URL {
        snapshotDirectory(forValidatedSha: try Self.validated(sha: sha))
    }

    /// The folder of one snapshot whose commit ``validated(sha:)`` already
    /// checked.
    ///
    /// - Parameter sha: The checked commit of the snapshot.
    /// - Returns: `<folder>/snapshots/<sha>`.
    private func snapshotDirectory(forValidatedSha sha: String) -> URL {
        snapshotsDirectory.appendingPathComponent(sha, isDirectory: true)
    }

    // MARK: - Reading

    /// The commit that `current` names.
    ///
    /// The symlink is a file that another program can write, so the call
    /// checks its target in the same way as a value of a caller.
    ///
    /// - Returns: The commit, or `nil` when there is no `current` symlink, or
    ///   when the target of the symlink is no commit.
    func currentSha() -> String? {
        guard
            let target = try? FileManager.default.destinationOfSymbolicLink(
                atPath: currentLink.path),
            let sha = try? Self.validated(sha: (target as NSString).lastPathComponent)
        else {
            return nil
        }
        return sha
    }

    /// The snapshot folder that `current` names.
    ///
    /// - Returns: The folder, or `nil` when there is no `current` symlink, or
    ///   when the target of the symlink is no commit.
    func currentSnapshot() -> URL? {
        currentSha().map { snapshotDirectory(forValidatedSha: $0) }
    }

    /// The commits of the snapshots that the folder holds, in order.
    ///
    /// A name that is no commit is not a snapshot, so the call drops it and
    /// cleanup never deletes it.
    ///
    /// - Returns: The commits, or an empty list before the first install.
    /// - Throws: The error of the folder read.
    func installedShas() throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: snapshotsDirectory.path) else {
            return []
        }
        return try manager.contentsOfDirectory(atPath: snapshotsDirectory.path)
            .filter { Self.isCommit(name: $0) }
            .sorted()
    }

    /// The commit that a ref file names.
    ///
    /// - Parameter ref: The branch or the tag.
    /// - Returns: The commit, or `nil` when there is no file for that ref.
    /// - Throws: ``MarketplaceCacheError`` when `ref` is not safe in a path,
    ///   else the error of the file read.
    func sha(forRef ref: String) throws -> String? {
        let file = refsDirectory.appendingPathComponent(try Self.validated(ref: ref))
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        return try String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Installing

    /// Puts a materialized snapshot in place and makes `current` name it
    /// (marketplace.md §7.3 steps 5 to 7).
    ///
    /// The whole call holds the writer lock, so one writer works on the folder
    /// at a time, also across processes. The steps are: move the staged folder
    /// to `snapshots/<sha>`, write `refs/<ref>`, make the `current.new`
    /// symlink and rename it over `current`, then clean up.
    ///
    /// The call checks `sha` and `ref` before it makes one folder, so a value
    /// that can leave the cache folder writes nothing at all.
    ///
    /// - Parameters:
    ///   - temporary: The folder that holds the materialized snapshot. The
    ///     call moves it, so the caller must not read it afterwards. It must
    ///     be on the same volume as the cache.
    ///   - sha: The commit of the snapshot.
    ///   - ref: The branch or the tag that resolved to `sha`, or `nil` for a
    ///     pinned commit, which has no ref file.
    /// - Throws: ``MarketplaceCacheError`` when the lock or the swap fails,
    ///   else the error of the file work.
    func install(snapshotAt temporary: URL, sha: String, ref: String?) throws {
        let checkedSha = try Self.validated(sha: sha)
        let checkedRef = try ref.map { try Self.validated(ref: $0) }
        try makeFolders()
        try withWriterLock {
            let previous = currentSha()
            try publish(snapshotAt: temporary, validatedSha: checkedSha)
            if let checkedRef {
                try write(sha: checkedSha, toValidatedRef: checkedRef)
            }
            try swapCurrent(toValidatedSha: checkedSha)
            try removeUnusedSnapshots(keeping: [checkedSha, previous].compactMap { $0 })
        }
    }

    /// Makes the folders that an install writes into.
    ///
    /// - Throws: The error of the folder.
    private func makeFolders() throws {
        for directory in [folder, refsDirectory, snapshotsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Moves the staged folder to `snapshots/<sha>`.
    ///
    /// A snapshot that is already there holds the same commit, and the content
    /// of a commit never changes. Thus the call drops the staged copy and
    /// keeps the folder that readers may already hold open.
    ///
    /// - Parameters:
    ///   - temporary: The staged folder.
    ///   - sha: The checked commit of the snapshot.
    /// - Throws: The error of the move or of the delete.
    private func publish(snapshotAt temporary: URL, validatedSha sha: String) throws {
        let manager = FileManager.default
        let destination = snapshotDirectory(forValidatedSha: sha)
        guard !manager.fileExists(atPath: destination.path) else {
            try manager.removeItem(at: temporary)
            return
        }
        try manager.moveItem(at: temporary, to: destination)
    }

    /// Writes the commit that a ref resolved to.
    ///
    /// - Parameters:
    ///   - sha: The commit.
    ///   - ref: The checked branch or tag. It is one name, so the file goes
    ///     straight into `refs/`.
    /// - Throws: The error of the file write.
    private func write(sha: String, toValidatedRef ref: String) throws {
        try sha.write(
            to: refsDirectory.appendingPathComponent(ref), atomically: true, encoding: .utf8)
    }

    /// Makes `current` name one snapshot, in one atomic step.
    ///
    /// The call makes a second symlink and renames it over `current`, because
    /// `rename(2)` replaces the name in one operation. Deleting `current` and
    /// making it again would give a reader a window with no link.
    ///
    /// - Parameter sha: The checked commit of the snapshot. The target of the
    ///   symlink holds it, so only a checked value goes in.
    /// - Throws: ``MarketplaceCacheError/cannotSwap(path:code:)`` when the
    ///   rename fails, else the error of the symlink.
    private func swapCurrent(toValidatedSha sha: String) throws {
        let manager = FileManager.default
        let staged = folder.appendingPathComponent(Self.stagedLinkName)
        // A link that an interrupted install left behind is not an error.
        try? manager.removeItem(at: staged)
        try manager.createSymbolicLink(
            atPath: staged.path,
            withDestinationPath: "\(Self.snapshotsDirectoryName)/\(sha)")
        guard rename(staged.path, currentLink.path) == 0 else {
            throw MarketplaceCacheError.cannotSwap(path: currentLink.path, code: errno)
        }
    }

    // MARK: - Cleanup

    /// Deletes every snapshot that the keep list does not name and that no
    /// reader holds (marketplace.md §7.6).
    ///
    /// Cleanup counts; it reads no age and no time. The keep list holds the
    /// snapshot that `current` names and the one before it, for rollback.
    ///
    /// - Parameter kept: The commits to keep.
    /// - Throws: The error of the folder read or of a delete.
    private func removeUnusedSnapshots(keeping kept: [String]) throws {
        let keptShas = Set(kept)
        for sha in try installedShas() where !keptShas.contains(sha) {
            try removeSnapshot(validatedSha: sha)
        }
    }

    /// Deletes one snapshot, unless a reader holds a shared lock on it.
    ///
    /// - Parameter sha: The checked commit of the snapshot, which
    ///   ``installedShas()`` gave.
    /// - Throws: The error of the delete.
    private func removeSnapshot(validatedSha sha: String) throws {
        let directory = snapshotDirectory(forValidatedSha: sha)
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            // Another writer of the same cache already deleted the folder.
            return
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            // A reader is using this snapshot. It stays until the next
            // cleanup.
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Locks

    /// Runs `body` while this process holds the exclusive writer lock of the
    /// marketplace folder (marketplace.md §7.6).
    ///
    /// - Parameter body: The work to do under the lock.
    /// - Returns: What `body` gives.
    /// - Throws: ``MarketplaceCacheError/cannotLock(path:code:)`` when the
    ///   lock fails, else what `body` throws.
    func withWriterLock<Value>(_ body: () throws -> Value) throws -> Value {
        let descriptor = open(lockFile.path, O_CREAT | O_RDWR, Self.lockFileMode)
        guard descriptor >= 0 else {
            throw MarketplaceCacheError.cannotLock(path: lockFile.path, code: errno)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw MarketplaceCacheError.cannotLock(path: lockFile.path, code: errno)
        }
        return try body()
    }

    /// Runs `body` while this process holds a shared lock on one snapshot, so
    /// that cleanup does not delete the folder the caller is reading.
    ///
    /// The lock is on the snapshot folder itself, so the layer root gets no
    /// extra file that skill discovery would see.
    ///
    /// - Parameters:
    ///   - sha: The commit of the snapshot.
    ///   - body: The work to do with the snapshot folder.
    /// - Returns: What `body` gives.
    /// - Throws: ``MarketplaceCacheError`` when `sha` is no commit, when the
    ///   folder does not open, or when the lock fails, else what `body`
    ///   throws.
    func withSnapshotInUse<Value>(sha: String, _ body: (URL) throws -> Value) throws -> Value {
        let directory = try snapshotDirectory(forSha: sha)
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw MarketplaceCacheError.cannotLock(path: directory.path, code: errno)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_SH) == 0 else {
            throw MarketplaceCacheError.cannotLock(path: directory.path, code: errno)
        }
        return try body(directory)
    }
}
