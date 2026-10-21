import FoundationModelsExtras

/// Feeds the change log of the `skills` endpoint from the reloads of one
/// registry: one `ChangedIDs` event for each reload that adds, changes or
/// removes a skill, and no event for a reload that changes nothing.
///
/// Each reload of `SkillsRegistry.onReload` swaps in a whole catalog
/// generation. The feed compares the content of each skill in it, the skills
/// that are off included, with the content of the generation before, by id.
///
/// The feed task captures the `onReload` stream, the `detachedReader` of the
/// registry and the change log, and never the endpoint or the feed: the
/// endpoint owns the feed, and the deinit of the feed cancels the task. The
/// `detachedReader` holds no reference to the reload coordinator of the
/// registry, thus the task does not keep the watcher alive either, as
/// `SkillsRegistry.commandUpdates` documents.
///
/// A client that reads the skills and then the cursor can read a generation
/// whose event the feed did not append yet. That client gets the event after
/// the cursor, thus it sees the change two times and never misses it.
final class SkillChangeFeed: Sendable {
    /// The task that appends the events, or `nil` for a registry that never
    /// reloads.
    private let task: Task<Void, Never>?

    /// Starts to feed a change log from the reloads of a registry.
    ///
    /// The feed subscribes to `onReload` before it reads the first snapshot,
    /// thus a reload between the two still reaches the diff.
    ///
    /// - Parameters:
    ///   - registry: The registry whose reloads feed the log.
    ///   - changeLog: The change log that gets one event for each reload that
    ///     changes a skill.
    init(registry: SkillsRegistry, changeLog: ChangeLog<ChangedIDs>) {
        guard let reloads = registry.onReload else {
            task = nil
            return
        }
        let reader = registry.detachedReader
        let seed = reader.skillContents()
        task = Task {
            var previous = seed
            for await _ in reloads {
                let next = reader.skillContents()
                if let event = SkillChangeFeed.changes(from: previous, to: next) {
                    await changeLog.append(event)
                }
                previous = next
            }
        }
    }

    /// Stops the feed: the task ends at its next wait on `onReload`.
    deinit {
        task?.cancel()
    }

    /// Gives the change between two snapshots, by id.
    ///
    /// - Parameters:
    ///   - previous: The content of each skill before, keyed by id.
    ///   - next: The content of each skill after, keyed by id.
    /// - Returns: The ids that `next` adds, changes and removes, each list
    ///   sorted, or `nil` when the two snapshots are equal.
    static func changes<Content: Equatable>(
        from previous: [String: Content], to next: [String: Content]
    ) -> ChangedIDs? {
        let added = next.keys.filter { id in previous[id] == nil }.sorted()
        let removed = previous.keys.filter { id in next[id] == nil }.sorted()
        let changed = next.compactMap { id, content in
            previous[id].flatMap { earlier in earlier == content ? nil : id }
        }.sorted()
        guard !(added.isEmpty && changed.isEmpty && removed.isEmpty) else {
            return nil
        }
        return ChangedIDs(added: added, changed: changed, removed: removed)
    }
}
