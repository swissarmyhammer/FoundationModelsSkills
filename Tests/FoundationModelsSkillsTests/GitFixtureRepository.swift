import Foundation
import libgit2

@testable import FoundationModelsSkills

/// A git repository that a test builds with libgit2 only (marketplace.md §13).
///
/// The fixture never starts the `git` binary. It makes a bare repository in a
/// new temporary directory, writes blobs and trees from a map of paths,
/// commits them, moves branches, and adds tags. ``url`` gives the repository
/// as a `file://` URL, thus a test can use it as a git source with no network.
///
/// `HEAD` names ``defaultBranch`` whatever `init.defaultBranch` the host sets,
/// thus a test that reads `HEAD` does not depend on the host configuration.
/// The directory is removed when the fixture is released.
///
/// The fixture uses the libgit2 helpers of ``LibGit2Transport``: the one
/// library start, the bare-repository flag, the SHA format, and the last
/// error message.
final class GitFixtureRepository {
    /// One file in a fixture commit.
    enum Entry {
        /// A regular file (mode `100644`) with this text.
        case file(String)

        /// An executable file (mode `100755`) with this text.
        case executable(String)

        /// A symbolic link (mode `120000`) to this target path.
        case symlink(target: String)

        /// A submodule (mode `160000`) at the commit with this 40-hex SHA.
        /// The commit is not in the fixture repository, as for a real
        /// submodule.
        case submodule(commit: String)

        /// The tree entry mode of this entry.
        var mode: git_filemode_t {
            switch self {
            case .file:
                GIT_FILEMODE_BLOB
            case .executable:
                GIT_FILEMODE_BLOB_EXECUTABLE
            case .symlink:
                GIT_FILEMODE_LINK
            case .submodule:
                GIT_FILEMODE_COMMIT
            }
        }
    }

    /// A libgit2 call in the fixture failed.
    struct FixtureError: Error, CustomStringConvertible {
        /// The name of the libgit2 function that failed.
        let call: String

        /// The code that the call returned.
        let code: Int32

        /// The message of the last libgit2 error.
        let message: String

        /// Names the call, the code, and the message, thus a failed test says
        /// which fixture step broke.
        var description: String {
            "\(call) failed with code \(code): \(message)"
        }
    }

    /// The branch that `HEAD` names and that ``commit(files:on:message:)``
    /// uses when a test names no branch.
    static let defaultBranch = "main"

    /// The name that each fixture commit and annotated tag records.
    private static let signatureName = "Fixture"

    /// The email that each fixture commit and annotated tag records. The
    /// `.invalid` top-level domain can never be a real address.
    private static let signatureEmail = "fixture@example.invalid"

    /// The `force` flag value that lets `git_reference_create` replace an
    /// existing branch.
    private static let replaceExistingReference: Int32 = 1

    /// The `force` flag value that makes a tag call fail on an existing tag.
    private static let keepExistingTag: Int32 = 0

    /// The temporary directory that holds the bare repository.
    let directory: URL

    /// The open repository handle.
    private let repository: OpaquePointer

    /// The repository as a `file://` URL, the form a git source takes.
    var url: String {
        directory.absoluteString
    }

    /// Makes an empty bare repository in a new temporary directory.
    ///
    /// - Throws: ``FixtureError`` when libgit2 cannot make the repository, or
    ///   the error of `WatcherTestSupport.makeTempDirectory()`.
    init() throws {
        let directory = try WatcherTestSupport.makeTempDirectory()
        do {
            repository = try Self.makeBareRepository(at: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        self.directory = directory
    }

    deinit {
        git_repository_free(repository)
        try? FileManager.default.removeItem(at: directory)
    }

    /// Commits `files` as the whole tree of a new commit on `branch`.
    ///
    /// The tip of `branch` becomes the parent. A branch that does not exist
    /// yet gets a root commit.
    ///
    /// - Parameters:
    ///   - files: The tree, one entry for each path. A path can hold `/`
    ///     separators, which make subtrees.
    ///   - branch: The branch to move to the new commit.
    ///   - message: The commit message.
    /// - Returns: The 40-hex SHA of the new commit.
    /// - Throws: ``FixtureError`` when a libgit2 call fails.
    @discardableResult
    func commit(
        files: [String: Entry], on branch: String = defaultBranch, message: String = "Fixture commit"
    ) throws -> String {
        var treeID = try writeTree(of: Self.nodes(from: files.map { (Self.components(of: $0.key), $0.value) }))
        var tree: OpaquePointer?
        try Self.check(status: git_tree_lookup(&tree, repository, &treeID), of: "git_tree_lookup")
        defer { git_tree_free(tree) }
        let parent = try tipCommit(of: branch)
        defer { git_commit_free(parent) }
        var parents: [OpaquePointer?] = parent.map { [$0] } ?? []
        var commitID = git_oid()
        try withSignature { signature in
            try Self.check(
                status: git_commit_create(
                    &commitID, repository, Self.branchReference(named: branch), signature, signature, nil, message,
                    tree, parents.count, &parents),
                of: "git_commit_create")
        }
        return LibGit2Transport.hex(of: commitID)
    }

    /// Points `branch` at the commit `sha`, and makes the branch when it
    /// does not exist.
    ///
    /// - Parameters:
    ///   - branch: The branch to move.
    ///   - sha: The 40-hex SHA of the target commit.
    /// - Throws: ``FixtureError`` when a libgit2 call fails.
    func moveBranch(named branch: String, to sha: String) throws {
        var target = try Self.objectID(of: sha)
        var reference: OpaquePointer?
        try Self.check(
            status: git_reference_create(
                &reference, repository, Self.branchReference(named: branch), &target, Self.replaceExistingReference,
                nil),
            of: "git_reference_create")
        git_reference_free(reference)
    }

    /// Adds the lightweight tag `name` at the commit `sha`.
    ///
    /// - Parameters:
    ///   - name: The tag name, without `refs/tags/`.
    ///   - sha: The 40-hex SHA of the tagged commit.
    /// - Throws: ``FixtureError`` when a libgit2 call fails.
    func addLightweightTag(named name: String, at sha: String) throws {
        try withCommitObject(sha: sha) { commit in
            var tagID = git_oid()
            try Self.check(
                status: git_tag_create_lightweight(&tagID, repository, name, commit, Self.keepExistingTag),
                of: "git_tag_create_lightweight")
        }
    }

    /// Adds the annotated tag `name` at the commit `sha`.
    ///
    /// An annotated tag is its own object. A remote advertises the tag object
    /// and, with a `^{}` suffix, the commit that it peels to.
    ///
    /// - Parameters:
    ///   - name: The tag name, without `refs/tags/`.
    ///   - sha: The 40-hex SHA of the tagged commit.
    /// - Throws: ``FixtureError`` when a libgit2 call fails.
    func addAnnotatedTag(named name: String, at sha: String) throws {
        try withCommitObject(sha: sha) { commit in
            var tagID = git_oid()
            try withSignature { signature in
                try Self.check(
                    status: git_tag_create(
                        &tagID, repository, name, commit, signature, "Fixture tag", Self.keepExistingTag),
                    of: "git_tag_create")
            }
        }
    }

    /// Tells whether the bare repository at `repositoryURL` holds the commit
    /// `sha`.
    ///
    /// - Parameters:
    ///   - sha: The 40-hex SHA to look up.
    ///   - repositoryURL: The directory of a bare repository.
    /// - Returns: `true` when the commit object is in the repository.
    /// - Throws: ``FixtureError`` when the repository cannot be opened.
    static func containsCommit(sha: String, inRepositoryAt repositoryURL: URL) throws -> Bool {
        var repository: OpaquePointer?
        try check(status: git_repository_open_bare(&repository, repositoryURL.path), of: "git_repository_open_bare")
        defer { git_repository_free(repository) }
        var commitID = try objectID(of: sha)
        var commit: OpaquePointer?
        let status = git_commit_lookup(&commit, repository, &commitID)
        git_commit_free(commit)
        return status == GIT_OK.rawValue
    }

    // MARK: - Trees

    /// One node of a tree that the fixture writes.
    private indirect enum Node {
        /// A file, an executable file, a symbolic link, or a submodule.
        case entry(Entry)

        /// A subtree, one node for each name.
        case directory([String: Node])
    }

    /// Splits `path` at each `/`.
    private static func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    /// Groups each path by its first component into a tree of nodes.
    ///
    /// - Parameter files: Each path, split into components, with its entry.
    /// - Returns: One node for each first component.
    private static func nodes(from files: [([String], Entry)]) -> [String: Node] {
        Dictionary(grouping: files) { $0.0.first ?? "" }.mapValues { group in
            if let only = group.first, group.count == 1, only.0.count == 1 {
                return .entry(only.1)
            }
            return .directory(nodes(from: group.map { (Array($0.0.dropFirst()), $0.1) }))
        }
    }

    /// Writes `nodes` as one tree object.
    ///
    /// - Returns: The id of the tree.
    private func writeTree(of nodes: [String: Node]) throws -> git_oid {
        var builder: OpaquePointer?
        try Self.check(status: git_treebuilder_new(&builder, repository, nil), of: "git_treebuilder_new")
        defer { git_treebuilder_free(builder) }
        for (name, node) in nodes {
            var (objectID, mode) = try write(node: node)
            try Self.check(
                status: git_treebuilder_insert(nil, builder, name, &objectID, mode), of: "git_treebuilder_insert")
        }
        var treeID = git_oid()
        try Self.check(status: git_treebuilder_write(&treeID, builder), of: "git_treebuilder_write")
        return treeID
    }

    /// Writes one node, and gives the id and mode of its tree entry.
    private func write(node: Node) throws -> (git_oid, git_filemode_t) {
        switch node {
        case .directory(let children):
            (try writeTree(of: children), GIT_FILEMODE_TREE)
        case .entry(let entry):
            (try writeObject(for: entry), entry.mode)
        }
    }

    /// Gives the object id of one entry, and writes its blob when it has one.
    ///
    /// A file, an executable file, and a symbolic link each store their text
    /// as a blob; a symbolic link stores its target path. A submodule names
    /// its commit, which has no object in the repository.
    ///
    /// - Parameter entry: The entry.
    /// - Returns: The id that the tree entry holds.
    private func writeObject(for entry: Entry) throws -> git_oid {
        switch entry {
        case .file(let text), .executable(let text), .symlink(let text):
            try writeBlob(contents: text)
        case .submodule(let commit):
            try Self.objectID(of: commit)
        }
    }

    /// Writes `contents` as one blob object.
    private func writeBlob(contents: String) throws -> git_oid {
        var blobID = git_oid()
        let bytes = Array(contents.utf8)
        try Self.check(
            status: git_blob_create_from_buffer(&blobID, repository, bytes, bytes.count),
            of: "git_blob_create_from_buffer")
        return blobID
    }

    // MARK: - Objects and references

    /// Starts libgit2 through ``LibGit2Transport``, makes the bare
    /// repository, and points `HEAD` at ``defaultBranch``.
    private static func makeBareRepository(at directory: URL) throws -> OpaquePointer {
        try check(status: LibGit2Transport.libraryStartCount, of: "git_libgit2_init")
        var repository: OpaquePointer?
        try check(
            status: git_repository_init(&repository, directory.path, LibGit2Transport.bareRepositoryFlag),
            of: "git_repository_init")
        let status = git_repository_set_head(repository, branchReference(named: defaultBranch))
        if let repository, status == GIT_OK.rawValue {
            return repository
        }
        let error = FixtureError(
            call: "git_repository_set_head", code: status, message: LibGit2Transport.lastErrorMessage())
        git_repository_free(repository)
        throw error
    }

    /// Looks up the tip commit of `branch`.
    ///
    /// - Returns: The commit, or `nil` when the branch does not exist yet.
    ///   The caller frees it.
    private func tipCommit(of branch: String) throws -> OpaquePointer? {
        var tipID = git_oid()
        if git_reference_name_to_id(&tipID, repository, Self.branchReference(named: branch)) != GIT_OK.rawValue {
            return nil
        }
        var commit: OpaquePointer?
        try Self.check(status: git_commit_lookup(&commit, repository, &tipID), of: "git_commit_lookup")
        return commit
    }

    /// Looks up the commit `sha` as a generic object, and gives it to `body`.
    private func withCommitObject(sha: String, body: (OpaquePointer?) throws -> Void) throws {
        var commitID = try Self.objectID(of: sha)
        var commit: OpaquePointer?
        try Self.check(
            status: git_object_lookup(&commit, repository, &commitID, GIT_OBJECT_COMMIT), of: "git_object_lookup")
        defer { git_object_free(commit) }
        try body(commit)
    }

    /// Makes the fixture signature with the time now, and gives it to `body`.
    private func withSignature(body: (UnsafeMutablePointer<git_signature>?) throws -> Void) throws {
        var signature: UnsafeMutablePointer<git_signature>?
        try Self.check(
            status: git_signature_now(&signature, Self.signatureName, Self.signatureEmail), of: "git_signature_now")
        defer { git_signature_free(signature) }
        try body(signature)
    }

    /// The full reference name of `branch`.
    private static func branchReference(named branch: String) -> String {
        "refs/heads/\(branch)"
    }

    /// Parses a 40-hex SHA.
    private static func objectID(of sha: String) throws -> git_oid {
        var objectID = git_oid()
        try check(status: git_oid_fromstr(&objectID, sha), of: "git_oid_fromstr")
        return objectID
    }

    /// Throws ``FixtureError`` when `status` is a libgit2 error code.
    ///
    /// - Parameters:
    ///   - status: The code that the libgit2 call returned.
    ///   - call: The name of the libgit2 function, for the error.
    private static func check(status: Int32, of call: String) throws {
        if status < GIT_OK.rawValue {
            throw FixtureError(call: call, code: status, message: LibGit2Transport.lastErrorMessage())
        }
    }
}
