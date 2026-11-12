import Foundation
import Testing

@testable import FoundationModelsSkills

/// Tests of `SkillsRegistry.stopWatching()`.
///
/// Each wait is on a condition: a value of `onReload` that names the new
/// skill. No test waits on a clock.
struct StopWatchingTests {
    /// Gives the ids of a catalog.
    private static func ids(_ metadata: [SkillMetadata]) -> [String] {
        metadata.map(\.id).sorted()
    }

    /// Two watched registries on one folder: after a stop of one, a new skill
    /// reaches the control registry but not the stopped registry.
    @Test
    func stoppedRegistryIgnoresANewSkillThatTheControlRegistrySees() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root)

        let stopped = SkillsRegistry(roots: [root], mode: .open, watch: true)
        let control = SkillsRegistry(roots: [root], mode: .open, watch: true)
        #expect(stopped.isFollowingChanges)
        #expect(control.isFollowingChanges)

        await stopped.stopWatching()
        #expect(!stopped.isFollowingChanges)
        let before = Self.ids(stopped.metadata())
        #expect(before == ["alpha"])

        let controlReloads = control.onReload
        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root)
        for await metadata in controlReloads where Self.ids(metadata).contains("bravo") {
            break
        }

        #expect(Self.ids(control.metadata()) == ["alpha", "bravo"])
        #expect(Self.ids(stopped.metadata()) == before)
        #expect(!stopped.isFollowingChanges)
    }

    /// A second call does nothing, the current skills stay readable, and an
    /// explicit `reload()` after the stop reads the new skill but does not
    /// start the watcher again.
    @Test
    func secondStopDoesNothingAndReloadStillWorks() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root)

        let registry = SkillsRegistry(roots: [root], mode: .open, watch: true)
        await registry.stopWatching()
        await registry.stopWatching()
        #expect(!registry.isFollowingChanges)
        #expect(Self.ids(registry.metadata()) == ["alpha"])

        try ReloadTestSupport.writeSkillFile(id: "bravo", in: root)
        registry.reload()

        #expect(Self.ids(registry.metadata()) == ["alpha", "bravo"])
        #expect(!registry.isFollowingChanges)
    }

    /// A registry with `watch: false` and no provider follows no change, and
    /// the call does nothing.
    @Test
    func unwatchedRegistryStopDoesNothing() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ReloadTestSupport.writeSkillFile(id: "alpha", in: root)

        let registry = SkillsRegistry(roots: [root], mode: .open)
        #expect(!registry.isFollowingChanges)
        await registry.stopWatching()
        #expect(!registry.isFollowingChanges)
        #expect(Self.ids(registry.metadata()) == ["alpha"])
    }
}
