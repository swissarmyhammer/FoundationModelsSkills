import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsSkills

/// The `changes(after:)` subscription and the root `cursor` of the `skills`
/// endpoint: rule 9 of EXTRAS-9, fed from the reloads of the registry.
///
/// A test of one file change uses ``WatchedFixture``: a registry that watches
/// its folder, thus a write to `SKILL.md` reloads it. A test that needs one
/// reload of several changes, or a reload that changes nothing, uses
/// ``ProviderFixture``: a registry that does not watch, and that reloads one
/// time for each ``ProviderFixture/reload()``, whatever the files hold then.
struct SkillsGraphChangesTests {
    // MARK: - Constants

    /// The skill that each fixture holds at the start.
    private static let firstSkillID = "alpha"

    /// The second skill that ``ProviderFixture`` holds at the start.
    private static let secondSkillID = "bravo"

    /// A skill that a test adds.
    private static let addedSkillID = "charlie"

    /// Another skill that a test adds after ``addedSkillID``.
    private static let laterSkillID = "delta"

    /// The code of a cursor that the endpoint cannot resume after.
    private static let resyncCode = "RESYNC_REQUIRED"

    /// A text that is not a cursor.
    private static let notACursor = "not-a-cursor"

    /// The text between the epoch and the sequence number of a cursor of the
    /// toolkit change log, whose wire form is `<epoch>:<sequence>`.
    private static let cursorSeparator: Character = ":"

    // MARK: - added, changed, removed

    /// A new `SKILL.md` in the watched folder gives one event with its id in
    /// `added`.
    @Test func addingASkillFileGivesItsIDInAdded() async throws {
        let fixture = try WatchedFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()

        try ReloadTestSupport.writeSkillFile(id: Self.addedSkillID, in: fixture.root)
        let event = try await fixture.endpoint.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(added: [Self.addedSkillID]))
    }

    /// An edit of a `SKILL.md` in the watched folder gives one event with
    /// its id in `changed`.
    @Test func editingASkillFileGivesItsIDInChanged() async throws {
        let fixture = try WatchedFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()

        try ReloadTestSupport.writeSkillFile(id: Self.firstSkillID, in: fixture.root, body: "An edited body.")
        let event = try await fixture.endpoint.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(changed: [Self.firstSkillID]))
    }

    /// The removal of a skill folder from the watched folder gives one event
    /// with its id in `removed`.
    @Test func removingASkillFolderGivesItsIDInRemoved() async throws {
        let fixture = try WatchedFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()

        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(Self.firstSkillID))
        let event = try await fixture.endpoint.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(removed: [Self.firstSkillID]))
    }

    /// A skill that its `enabled` key turns off is still a skill of the
    /// endpoint, thus turning it off changes it and removes nothing.
    @Test func turningASkillOffGivesItsIDInChanged() async throws {
        let fixture = try WatchedFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()

        try ReloadTestSupport.writeSkillFile(
            id: Self.firstSkillID, in: fixture.root, extraFrontmatter: "enabled: false\n")
        let event = try await fixture.endpoint.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(changed: [Self.firstSkillID]))
    }

    // MARK: - One event for each reload

    /// One reload of several changes gives one event that lists each of
    /// them, and no second event.
    @Test func oneReloadOfSeveralChangesGivesOneEvent() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()

        try ReloadTestSupport.writeSkillFile(id: Self.addedSkillID, in: fixture.root)
        try ReloadTestSupport.writeSkillFile(id: Self.firstSkillID, in: fixture.root, body: "An edited body.")
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(Self.secondSkillID))
        fixture.reload()
        let event = try await fixture.endpoint.firstEvent(after: start)

        #expect(
            event.ids
                == ChangedIDs(
                    added: [Self.addedSkillID], changed: [Self.firstSkillID], removed: [Self.secondSkillID]))
        #expect(try await fixture.endpoint.cursor() == event.cursor)
    }

    /// A reload that changes no skill gives no event: the first event after
    /// it is the one of the next reload that changes a skill.
    @Test func aReloadWithNoDifferenceGivesNoEvent() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()
        let reloads = ReloadTestSupport.EventTally()
        let subscription = ReloadTestSupport.tally(fixture.registry.onReload, into: reloads)
        defer { subscription.cancel() }

        fixture.reload()
        await ReloadTestSupport.expectExactlyOneEvent(reloads)
        try ReloadTestSupport.writeSkillFile(id: Self.addedSkillID, in: fixture.root)
        fixture.reload()
        let event = try await fixture.endpoint.firstEvent(after: start)

        #expect(event.ids == ChangedIDs(added: [Self.addedSkillID]))
    }

    // MARK: - Resume after a cursor

    /// `changes(after:)` gives only the events after the cursor.
    @Test func changesAfterACursorGivesOnlyTheLaterEvents() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()
        try ReloadTestSupport.writeSkillFile(id: Self.addedSkillID, in: fixture.root)
        fixture.reload()
        let earlier = try await fixture.endpoint.firstEvent(after: start)

        try ReloadTestSupport.writeSkillFile(id: Self.laterSkillID, in: fixture.root)
        fixture.reload()
        let later = try await fixture.endpoint.firstEvent(after: earlier.cursor)

        #expect(later.ids == ChangedIDs(added: [Self.laterSkillID]))
    }

    /// `skillChanges` is an alias of `changes`, and the response reports the
    /// rewrite.
    @Test func skillChangesIsAnAliasOfChanges() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()
        try ReloadTestSupport.writeSkillFile(id: Self.addedSkillID, in: fixture.root)
        fixture.reload()
        _ = try await fixture.endpoint.firstEvent(after: start)

        let response = try await fixture.endpoint.firstResponse(
            of: "subscription { skillChanges(after: \"\(start)\") { added } }")

        #expect(try ChangeEvent.ids(in: response, at: "skillChanges") == ChangedIDs(added: [Self.addedSkillID]))
        #expect(try ResponseText.rewrites(response) == ["skillChanges→changes"])
    }

    // MARK: - RESYNC_REQUIRED

    /// A text that is not a cursor gives `RESYNC_REQUIRED`.
    @Test func aTextThatIsNotACursorGivesResyncRequired() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }

        let codes = try await fixture.endpoint.codes(after: Self.notACursor)

        #expect(codes == [Self.resyncCode])
    }

    /// A cursor of another endpoint instance has another epoch, and gives
    /// `RESYNC_REQUIRED`.
    @Test func aCursorOfAnotherEpochGivesResyncRequired() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        let other = Endpoint(graph: try SkillsGraph(registry: fixture.registry))

        let codes = try await fixture.endpoint.codes(after: try await other.cursor())

        #expect(codes == [Self.resyncCode])
    }

    /// A cursor after the newest event gives `RESYNC_REQUIRED`.
    @Test func aCursorAfterTheNewestEventGivesResyncRequired() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        let newest = try await fixture.endpoint.cursor()

        let codes = try await fixture.endpoint.codes(after: try Self.cursor(after: newest))

        #expect(codes == [Self.resyncCode])
    }

    /// A cursor whose later events left the buffer of the change log gives
    /// `RESYNC_REQUIRED`.
    @Test func aCursorTooOldForTheBufferGivesResyncRequired() async throws {
        let fixture = try ProviderFixture(changeLog: ChangeLog(capacity: 1))
        defer { fixture.remove() }
        let start = try await fixture.endpoint.cursor()
        try ReloadTestSupport.writeSkillFile(id: Self.addedSkillID, in: fixture.root)
        fixture.reload()
        let earlier = try await fixture.endpoint.firstEvent(after: start)
        try ReloadTestSupport.writeSkillFile(id: Self.laterSkillID, in: fixture.root)
        fixture.reload()
        _ = try await fixture.endpoint.firstEvent(after: earlier.cursor)

        let codes = try await fixture.endpoint.codes(after: start)

        #expect(codes == [Self.resyncCode])
    }

    // MARK: - Lifetime

    /// The task that feeds the change log holds no reference to the endpoint,
    /// thus the endpoint goes away with its last holder, also over a registry
    /// that reloads.
    @Test func theEndpointOfAReloadingRegistryIsReleased() throws {
        let fixture = try ProviderFixture()
        defer { fixture.remove() }
        weak var released: SkillsGraph?

        do {
            let graph = try SkillsGraph(registry: fixture.registry)
            released = graph
        }

        #expect(released == nil)
    }

    // MARK: - The diff

    /// The diff of two snapshots lists each added, changed and removed id,
    /// sorted.
    @Test func theDiffListsEachKindOfChangeSorted() {
        let previous = ["b": 1, "c": 1, "x": 1, "y": 1]
        let next = ["a": 1, "b": 2, "c": 2, "d": 1]

        let event = SkillChangeFeed.changes(from: previous, to: next)

        #expect(event == ChangedIDs(added: ["a", "d"], changed: ["b", "c"], removed: ["x", "y"]))
    }

    /// The diff of two equal snapshots is no event.
    @Test func theDiffOfEqualSnapshotsIsNoEvent() {
        let snapshot = ["a": 1, "b": 2]

        #expect(SkillChangeFeed.changes(from: snapshot, to: snapshot) == nil)
    }

    // MARK: - Helpers

    /// Gives a cursor after another one: the same epoch, and the next
    /// sequence number.
    ///
    /// The cursor is opaque to a client. This test reads the wire form of
    /// the toolkit change log, `<epoch>:<sequence>`, only to make a cursor
    /// that no event has yet.
    ///
    /// - Parameter cursor: The cursor.
    /// - Returns: The cursor of the next sequence number.
    /// - Throws: A failure of `#require` when the text is not of that form.
    private static func cursor(after cursor: String) throws -> String {
        let separator = try #require(cursor.lastIndex(of: cursorSeparator))
        let sequence = try #require(UInt64(cursor[cursor.index(after: separator)...]))
        return "\(cursor[..<separator])\(cursorSeparator)\(sequence + 1)"
    }

    /// The text of one GraphQL response.
    private enum ResponseText {
        /// Reads a response as a JSON object.
        ///
        /// - Parameter text: The JSON text.
        /// - Returns: The object.
        /// - Throws: A failure of `#require` when the text is not an object.
        static func object(_ text: String) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }

        /// Gives the `extensions.code` of each error of a response.
        ///
        /// - Parameter text: The JSON text.
        /// - Returns: The codes, in order.
        /// - Throws: A failure of `#require` when the text is not an object.
        static func codes(_ text: String) throws -> [String] {
            let errors = try object(text)["errors"] as? [[String: Any]] ?? []
            return errors.compactMap { error in (error["extensions"] as? [String: Any])?["code"] as? String }
        }

        /// Gives each `extensions.rewrites` entry of a response as
        /// `from→to`.
        ///
        /// - Parameter text: The JSON text.
        /// - Returns: The rewrites, in order.
        /// - Throws: A failure of `#require` when the text is not an object.
        static func rewrites(_ text: String) throws -> [String] {
            let extensions = try object(text)["extensions"] as? [String: Any]
            let rewrites = extensions?["rewrites"] as? [[String: Any]] ?? []
            return rewrites.map { rewrite in "\(rewrite["from"] ?? "")→\(rewrite["to"] ?? "")" }
        }
    }

    /// One event of the `changes` subscription.
    private struct ChangeEvent {
        /// The cursor that resumes after the event.
        let cursor: String

        /// The ids of the event.
        let ids: ChangedIDs

        /// Reads the event of a response.
        ///
        /// - Parameter text: The JSON text of the response.
        /// - Throws: A failure of `#require` when the response has no event.
        init(response text: String) throws {
            let event = try Self.event(in: text, at: "changes")
            cursor = try #require(event["cursor"] as? String)
            _ = try #require(event["at"] as? String)
            ids = Self.ids(of: event)
        }

        /// Reads the ids of the event of a response.
        ///
        /// - Parameters:
        ///   - text: The JSON text of the response.
        ///   - key: The response key of the subscription field.
        /// - Returns: The ids.
        /// - Throws: A failure of `#require` when the response has no event.
        static func ids(in text: String, at key: String) throws -> ChangedIDs {
            try ids(of: event(in: text, at: key))
        }

        /// Reads the event object of a response.
        ///
        /// - Parameters:
        ///   - text: The JSON text of the response.
        ///   - key: The response key of the subscription field.
        /// - Returns: The event object.
        /// - Throws: A failure of `#require` when the response has no event.
        private static func event(in text: String, at key: String) throws -> [String: Any] {
            let data = try #require(try ResponseText.object(text)["data"] as? [String: Any])
            return try #require(data[key] as? [String: Any])
        }

        /// Reads the ids of an event object.
        ///
        /// - Parameter event: The event object.
        /// - Returns: The ids.
        private static func ids(of event: [String: Any]) -> ChangedIDs {
            ChangedIDs(
                added: event["added"] as? [String] ?? [], changed: event["changed"] as? [String] ?? [],
                removed: event["removed"] as? [String] ?? [])
        }
    }

    /// The endpoint under test, with the calls that the tests make.
    private struct Endpoint {
        /// The selection of each field of a `SkillChange`.
        private static let eventFields = "cursor at added changed removed"

        /// The endpoint.
        let graph: SkillsGraph

        /// Queries the root `cursor`.
        ///
        /// - Returns: The cursor of the newest event.
        /// - Throws: An error of the endpoint, or a failure of `#require`.
        func cursor() async throws -> String {
            let response = try await graph.execute(query: "{ cursor }", variables: [:], operationName: nil, viewer: nil)
            let data = try #require(try ResponseText.object(response)["data"] as? [String: Any])
            return try #require(data["cursor"] as? String)
        }

        /// Waits for an event after a cursor, then gives the first one.
        ///
        /// The root `cursor` changes when the change log takes an event, thus
        /// the wait polls it, and the subscription then replays the event
        /// with no wait.
        ///
        /// - Parameter start: The cursor to resume after.
        /// - Returns: The first event after the cursor.
        /// - Throws: An error of the endpoint, or a failure of `#require`.
        func firstEvent(after start: String) async throws -> ChangeEvent {
            let newest = await ReloadTestSupport.poll(
                { (try? await cursor()) ?? start }, until: { cursor in cursor != start },
                timeout: ReloadTestSupport.expectedSignalTimeout)
            try #require(newest != start)
            return try await ChangeEvent(
                response: firstResponse(of: "subscription { changes(after: \"\(start)\") { \(Self.eventFields) } }"))
        }

        /// Gives the error codes of a subscription after a cursor.
        ///
        /// - Parameter cursor: The cursor to resume after.
        /// - Returns: The `extensions.code` of each error of the first
        ///   response.
        /// - Throws: An error of the endpoint, or a failure of `#require`.
        func codes(after cursor: String) async throws -> [String] {
            try await ResponseText.codes(firstResponse(of: "subscription { changes(after: \"\(cursor)\") { cursor } }"))
        }

        /// Starts a subscription, and gives its first response.
        ///
        /// - Parameter query: The subscription document.
        /// - Returns: The JSON text of the first response.
        /// - Throws: An error of the endpoint, or a failure of `#require`
        ///   when the stream ends with no response.
        func firstResponse(of query: String) async throws -> String {
            let stream = try await graph.subscribe(query: query, variables: [:], operationName: nil, viewer: nil)
            var iterator = stream.makeAsyncIterator()
            return try #require(try await iterator.next())
        }
    }

    /// A temporary folder with ``firstSkillID``, a registry that watches it,
    /// and the endpoint over that registry.
    private struct WatchedFixture {
        /// The temporary layer root.
        let root: URL

        /// The endpoint under test.
        let endpoint: Endpoint

        /// Writes the skill into a new root, and builds the endpoint.
        ///
        /// - Throws: Whatever the directory, the file write, or the schema
        ///   builder throws.
        init() throws {
            root = try WatcherTestSupport.makeTempDirectory()
            try ReloadTestSupport.writeSkillFile(id: SkillsGraphChangesTests.firstSkillID, in: root)
            endpoint = Endpoint(graph: try SkillsGraph(registry: SkillsRegistry(roots: [root], watch: true)))
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A temporary folder with ``firstSkillID`` and ``secondSkillID``, a
    /// registry over it that reloads one time for each ``reload()``, and the
    /// endpoint over that registry.
    ///
    /// The registry does not watch the folder. A fake marketplace provider
    /// with no layer backs it, and each update of the provider runs the same
    /// rebuild that a file change runs. Thus several file changes give one
    /// reload, and a reload with no file change gives a reload that changes
    /// nothing.
    private struct ProviderFixture {
        /// The temporary layer root.
        let root: URL

        /// The provider whose updates reload the registry.
        let provider = FakeMarketplaceProvider(layers: [])

        /// The registry under the endpoint.
        let registry: SkillsRegistry

        /// The endpoint under test.
        let endpoint: Endpoint

        /// Writes the skills into a new root, and builds the endpoint.
        ///
        /// - Parameter changeLog: The change log of the endpoint. The default
        ///   is a log of the default size.
        /// - Throws: Whatever the directory, a file write, or the schema
        ///   builder throws.
        init(changeLog: ChangeLog<ChangedIDs> = ChangeLog()) throws {
            root = try WatcherTestSupport.makeTempDirectory()
            try ReloadTestSupport.writeSkillFile(id: SkillsGraphChangesTests.firstSkillID, in: root)
            try ReloadTestSupport.writeSkillFile(id: SkillsGraphChangesTests.secondSkillID, in: root)
            var stack = DotfolderStack(name: "skills", workingDirectory: root, environment: [:])
            stack.layers = [DotfolderStack.Layer(source: .project, root: root)]
            registry = SkillsRegistry(marketplaces: provider, stack: stack)
            endpoint = Endpoint(graph: try SkillsGraph(registry: registry, changeLog: changeLog))
        }

        /// Reloads the registry one time.
        func reload() {
            provider.publish(layers: [])
        }

        /// Deletes the temporary root.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
