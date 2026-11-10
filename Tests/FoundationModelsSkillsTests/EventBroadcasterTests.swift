import Testing

@testable import FoundationModelsSkills

/// Tests for `EventBroadcaster`: what a subscriber sees after `finishAll()`.
///
/// A read-only view of a `SkillsRegistry` shares the broadcaster of its
/// registry and can outlive the registry. A subscription that the view makes
/// after the registry finished the broadcaster must end, and not wait for
/// ever.
struct EventBroadcasterTests {
    /// A subscription after `finishAll()` is a stream that is already
    /// finished. The time limit ends the test when the stream waits for
    /// ever instead.
    @Test(.timeLimit(.minutes(1))) func aSubscriptionAfterFinishAllIsAlreadyFinished() async {
        let broadcaster = EventBroadcaster<Int>()
        broadcaster.finishAll()

        var iterator = broadcaster.subscribe().makeAsyncIterator()

        #expect(await iterator.next() == nil)
    }
}
