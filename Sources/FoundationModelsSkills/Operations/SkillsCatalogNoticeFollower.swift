import FoundationModelsExtras

/// Posts one catalog-change notice for each registry reload that changes the
/// listed catalog, and stops as soon as it is released.
///
/// The `skills` tool lists its catalog in its description one time, when it
/// is made. The description never changes during a session, because the
/// transcripts need the same tool definition on each turn, and a change throws
/// away the cached prompt. Thus a session learns of a reload from a notice.
///
/// Each reload of `SkillsRegistry.onReload` gives the new catalog. This class
/// maps it to the entries of the list with
/// `SkillsToolDescription.catalogEntries(for:isListed:)`, and compares them
/// with the last entries. When the list shows a change, it posts one
/// `CatalogChangeNotice` to `board`. A change that the list does not show, for
/// example a body edit or a hidden skill, posts nothing.
///
/// Each session that mounts the tool with `ToolMounting.makeWrapped` joins
/// `board`. A session that mounts the tool after a reload does not get the
/// notice of that reload. Its description shows the catalog of the time the
/// tool was made.
///
/// ### Subscribe before you seed
///
/// `reloads` must be taken from the registry before the caller reads `seed`.
/// `onReload` carries each publication from the point of subscription on.
/// Thus a caller that reads the seed first can lose a reload in between.
///
/// ### The posting task captures no `self`
///
/// The task captures the stream, the predicate and the board, and never
/// `self`. A task that captured `self` would keep its follower alive for as
/// long as it runs. Then `deinit` would never run, and the task would post for
/// ever. `SkillsReloadFollower` records the same trap.
///
/// `final class ... Sendable`: each stored property is an immutable `let` of a
/// `Sendable` type. Thus this class holds no mutable state and needs no lock.
public final class SkillsCatalogNoticeFollower: Sendable {
    /// The board that each notice goes to. Each session that mounts the tool
    /// joins it.
    public let board: CatalogNoticeBoard

    /// The task that reads each publication and posts each notice.
    ///
    /// It is held for its lifetime only: nothing reads it back, and `deinit`
    /// cancels it.
    private let posting: Task<Void, Never>

    /// Creates a follower, and starts to follow at once.
    ///
    /// - Parameters:
    ///   - reloads: The reload stream, already subscribed: typically
    ///     `SkillsRegistry.onReload`. Read "Subscribe before you seed" above.
    ///   - seed: The catalog before the first reload, not filtered. The first
    ///     notice compares against it.
    ///   - visibilityPredicate: Which skills the list of the tool shows: the
    ///     predicate of the tool context.
    public init(
        reloads: AsyncStream<[SkillMetadata]>,
        seed: [SkillMetadata],
        visibilityPredicate: @escaping @Sendable (SkillMetadata) -> Bool
    ) {
        let board = CatalogNoticeBoard()
        self.board = board
        let seedEntries = SkillsToolDescription.catalogEntries(for: seed, isListed: visibilityPredicate)
        posting = Task {
            var last = seedEntries
            for await catalog in reloads {
                guard !Task.isCancelled else { return }
                let new = SkillsToolDescription.catalogEntries(for: catalog, isListed: visibilityPredicate)
                if let notice = CatalogChangeNotice(kind: .skills, from: last, to: new) {
                    await board.post(notice)
                }
                last = new
            }
        }
    }

    /// Cancels the posting task, thus no notice comes after its follower.
    ///
    /// An `AsyncStream` iterator can still give a value that was buffered
    /// before the cancel. Thus the task also checks `Task.isCancelled` before
    /// each post.
    deinit {
        posting.cancel()
    }
}
