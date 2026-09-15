import Darwin
import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import Operations
import Testing

@testable import FoundationModelsSkills

/// Tests for the `run script` operation (plan.md §7.3.1): the triple gate,
/// unknown/model-hidden id correctives, the two path guards (`scripts/`
/// prefix, then confinement), the direct-exec eligibility check
/// (executable bit + shebang), process-group timeout kill, the
/// `ScriptProcessRunner` failed-to-spawn branch, the `generatedContent`
/// round trip, and a golden result against the static `release-notes`
/// fixture.
struct RunScriptTests {
    // MARK: - Fixture root (mirrors ResourceOpsTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// A non-default `timeout` for the round-trip tests, chosen so a decoded
    /// value equal to `RunScript.defaultTimeoutSeconds` could not pass by
    /// accident.
    private static let sampleTimeoutSeconds = 5

    /// The timeout for the failed-to-spawn test. A spawn that fails gives a
    /// result at once, so a short timeout makes a hang fail the test fast
    /// instead of waiting for `RunScript.defaultTimeoutSeconds`.
    private static let failedToSpawnTimeoutSeconds: TimeInterval = 1

    /// Builds a `SkillsToolContext` over `roots` under `policy`, via the
    /// shared `ResourceTestSupport.makeContext(roots:policy:)` --
    /// `ResourceOpsTests` builds one the identical way, minus this `policy`
    /// parameter.
    ///
    /// - Parameters:
    ///   - roots: The registry roots to build over. Defaults to the §11
    ///     fixture library.
    ///   - policy: The render policy the registry is constructed with.
    ///     Defaults to the permissive `RenderPolicy()`.
    /// - Returns: The assembled context.
    private static func makeContext(
        roots: [URL] = [Self.projectSkillsRoot], policy: RenderPolicy = RenderPolicy()
    ) -> SkillsToolContext {
        ResourceTestSupport.makeContext(roots: roots, policy: policy)
    }

    // MARK: - Gate matrix (plan.md §13)

    @Test func runScriptSucceedsWhenGranted() async throws {
        let output = try await RunScript(id: "release-notes", path: "scripts/build.sh").execute(in: Self.makeContext())

        guard case .success(let result) = output else {
            Issue.record("expected a success outcome, got \(output)")
            return
        }
        #expect(result.status == "completed")
        #expect(result.exitCode == 0)
    }

    @Test func runScriptRefusesWhenHostPolicyDisablesScriptExecution() async throws {
        let context = Self.makeContext(policy: RenderPolicy(isScriptExecutionDisabled: true))
        let output = try await RunScript(id: "release-notes", path: "scripts/build.sh").execute(in: context)

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("disabled"))
    }

    // MARK: - Policy-first ordering (^zbv0t4j): gate 1 precedes id lookup/path resolution

    @Test(
        "with scripts disabled, ANY path (valid, unknown id, escaping) draws the identical policy corrective",
        arguments: [
            (name: "a valid id and path", id: "release-notes", path: "scripts/build.sh"),
            (name: "an unknown id", id: "does-not-exist", path: "scripts/build.sh"),
            (name: "a path not under scripts/", id: "release-notes", path: "references/changelog.md"),
            (name: "a path confinement escape", id: "release-notes", path: "../../etc/passwd"),
        ])
    func hostPolicyGateFiresBeforeAnyIDOrPathResolution(name: String, id: String, path: String) async throws {
        let context = Self.makeContext(policy: RenderPolicy(isScriptExecutionDisabled: true))

        let output = try await RunScript(id: id, path: path).execute(in: context)

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message == "Script execution is disabled for this registry.", "\(name)")
    }

    @Test func runScriptRefusesWithNoGrantAtAll() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "no-grant", in: root, allowedTools: nil)
        try ResourceTestSupport.writeExecutableShebangScript(named: "run.sh", inSkillID: "no-grant", under: root)

        let output = try await RunScript(id: "no-grant", path: "scripts/run.sh").execute(
            in: Self.makeContext(roots: [root]))

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("not pre-approved"))
    }

    @Test func runScriptRefusesWithANonMatchingGlob() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "narrow-grant", in: root, allowedTools: "Script(scripts/other/*)")
        try ResourceTestSupport.writeExecutableShebangScript(named: "run.sh", inSkillID: "narrow-grant", under: root)

        let output = try await RunScript(id: "narrow-grant", path: "scripts/run.sh").execute(
            in: Self.makeContext(roots: [root]))

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("not pre-approved"))
    }

    // MARK: - Unknown / model-hidden id (decision #22)

    @Test func runScriptOnAnUnknownIDDrawsACorrective() async throws {
        let output = try await RunScript(id: "nonexistent", path: "scripts/build.sh").execute(in: Self.makeContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("not currently usable"))
    }

    @Test func runScriptOnAModelHiddenIDDrawsACorrective() async throws {
        // `deploy` carries `disable-model-invocation: true` -- present on
        // the user `/` menu but not usable via this model-only operation.
        let output = try await RunScript(id: "deploy", path: "scripts/build.sh").execute(in: Self.makeContext())

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("deploy"))
    }

    // MARK: - Path guards: the `scripts/` prefix check precedes confinement

    /// Both guards sit past gate 1 (host policy), the id lookup, and before
    /// the grant check, so the fixture enables script execution (the default
    /// `RenderPolicy()`) and grants every script via a bare `Script`. Each
    /// guard reads the `path` string before any filesystem access, so no
    /// script file needs to exist for either corrective to fire.
    @Test(
        "under a full grant, a path outside scripts/ draws the not-runnable corrective, and a scripts/-prefixed escape draws the confinement one",
        arguments: [
            (
                name: "a script at the skill root, not under scripts/",
                path: "hello.sh",
                expected: "The path `hello.sh` is not runnable: `run script` only executes files under `scripts/`."
            ),
            (
                name: "a scripts/-prefixed path that escapes the skill directory",
                path: "scripts/../../outside.sh",
                expected:
                    "The path `scripts/../../outside.sh` is not accessible: it must resolve to a location inside the skill directory."
            ),
        ])
    func pathGuardsFireInOrderUnderAFullGrant(name: String, path: String, expected: String) async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "path-guards", in: root, allowedTools: "Script")

        let output = try await RunScript(id: "path-guards", path: path).execute(in: Self.makeContext(roots: [root]))

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message == expected, "\(name)")
    }

    // MARK: - Direct-exec eligibility: executable bit + shebang

    @Test func runScriptRefusesANonExecutableFile() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "not-executable", in: root, allowedTools: "Script")
        let scriptURL = try ResourceTestSupport.scriptsDirectory(inSkillID: "not-executable", under: root)
            .appendingPathComponent("run.sh")
        try "#!/bin/sh\necho hi\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        // Deliberately not marked executable.

        let output = try await RunScript(id: "not-executable", path: "scripts/run.sh").execute(
            in: Self.makeContext(roots: [root]))

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("executable bit"))
    }

    @Test func runScriptRefusesAFileWithNoShebang() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "no-shebang", in: root, allowedTools: "Script")
        let scriptURL = try ResourceTestSupport.scriptsDirectory(inSkillID: "no-shebang", under: root)
            .appendingPathComponent("run.sh")
        try "echo hi\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let output = try await RunScript(id: "no-shebang", path: "scripts/run.sh").execute(
            in: Self.makeContext(roots: [root]))

        guard case .corrective(let message) = output else {
            Issue.record("expected a corrective outcome, got \(output)")
            return
        }
        #expect(message.contains("shebang"))
    }

    // MARK: - Timeout + process-group kill

    @Test func runScriptTimesOutAndKillsTheWholeProcessGroup() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "sleeper", in: root, allowedTools: "Script")
        let scriptURL = try ResourceTestSupport.scriptsDirectory(inSkillID: "sleeper", under: root)
            .appendingPathComponent("sleep-and-background.sh")
        try """
            #!/bin/sh
            sleep 100 &
            echo "child pid: $!"
            wait
            """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let output = try await RunScript(id: "sleeper", path: "scripts/sleep-and-background.sh", timeout: 1).execute(
            in: Self.makeContext(roots: [root]))

        guard case .success(let result) = output else {
            Issue.record("expected a success outcome carrying a timed_out status, got \(output)")
            return
        }
        #expect(result.status == "timed_out")
        #expect(result.exitCode == nil)

        let childPIDLine = try #require(result.output.first { $0.contains("child pid:") })
        let childPIDText = childPIDLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
        let childPID = try #require(childPIDText.flatMap(pid_t.init))

        // The direct child (the `#!/bin/sh` interpreter) and everything it
        // spawned share its process group -- give the kernel a moment to
        // finish reaping after the group-wide SIGKILL before checking.
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(childPID, 0) == -1, "the backgrounded grandchild should have died with the whole process group")
    }

    // MARK: - ScriptProcessRunner: the failed-to-spawn branch

    /// `RunScript` gates on the executable bit and on a shebang line before
    /// it calls the runner, so a script that passes both gates and still
    /// fails to exec is the one shape that reaches `ScriptProcessRunner`'s
    /// `posix_spawn` failure branch. A shebang naming an interpreter that
    /// does not exist makes the kernel refuse the exec, so `posix_spawn`
    /// itself fails and the runner gives back `failedToSpawn`.
    @Test(.timeLimit(.minutes(1)))
    func scriptProcessRunnerReportsFailedToSpawnWhenTheInterpreterDoesNotExist() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = try ResourceTestSupport.writeExecutableShebangScript(
            named: "no-interpreter.sh", inSkillID: "no-interpreter", under: root,
            contents: "#!/nonexistent/interpreter\necho hi\n")

        let outcome = await ScriptProcessRunner.run(
            executableURL: scriptURL, arguments: [], workingDirectory: root,
            timeout: Self.failedToSpawnTimeoutSeconds)

        #expect(outcome.status == .failed)
        #expect(outcome.exitCode == nil)
        #expect(outcome.durationMs == 0)
        #expect(outcome.lines == 0)
        #expect(outcome.output.isEmpty)
    }

    // MARK: - Golden result

    @Test func goldenRunScriptResultAgainstTheReleaseNotesFixture() async throws {
        let output = try await RunScript(id: "release-notes", path: "scripts/build.sh").execute(in: Self.makeContext())

        guard case .success(let result) = output else {
            Issue.record("expected a success outcome, got \(output)")
            return
        }
        #expect(result.id == "release-notes")
        #expect(result.path == "scripts/build.sh")
        #expect(result.status == "completed")
        #expect(result.exitCode == 0)
        #expect(result.lines == 1)
        #expect(result.output == ["1: building release notes"])
        // No upper bound here: a wall-clock ceiling is a hard-coded time
        // budget, and the load of the host must never decide a pass or a
        // fail. This proves only the shape of the result: `durationMs` is
        // a real, non-negative measurement. The specific truncation bug
        // that would silently drop the sub-second remainder is pinned in
        // `durationMsReportsTheSubSecondRemainderNotJustWholeSeconds`
        // below, with an assertion that does not depend on wall-clock
        // speed either.
        #expect(result.durationMs >= 0)
    }

    // MARK: - durationMs sub-second precision

    /// `ScriptProcessRunner.run(...)`'s duration previously converted via
    /// `Int(elapsed.components.seconds * 1000)` alone, silently discarding
    /// the `.attoseconds` remainder -- a genuinely ~300ms run would report
    /// `durationMs == 0`. A `sleep 0.3` fixture pins the fix. No wall-clock
    /// window is asserted -- the load of the host must never decide a pass
    /// or a fail. Instead this proves the remainder itself survived: the
    /// truncating conversion always lands on a whole multiple of 1000 (in
    /// fact exactly 0 for a sub-second sleep), while a duration that keeps
    /// its sub-second term essentially never does, on any host speed.
    @Test func durationMsReportsTheSubSecondRemainderNotJustWholeSeconds() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResourceTestSupport.writeMinimalSkillFile(id: "sub-second-sleeper", in: root, allowedTools: "Script")
        try ResourceTestSupport.writeExecutableShebangScript(
            named: "sleep-a-bit.sh", inSkillID: "sub-second-sleeper", under: root,
            contents: "#!/bin/sh\nsleep 0.3\necho done\n")

        let output = try await RunScript(id: "sub-second-sleeper", path: "scripts/sleep-a-bit.sh").execute(
            in: Self.makeContext(roots: [root]))

        guard case .success(let result) = output else {
            Issue.record("expected a success outcome, got \(output)")
            return
        }
        #expect(result.status == "completed")
        // A whole-seconds-only conversion of a sub-second sleep always
        // reports an exact multiple of 1000 (0, here). A duration that
        // keeps its sub-second remainder does not, regardless of how fast
        // or slow the host actually ran the sleep.
        #expect(result.durationMs % 1000 != 0)
    }

    // MARK: - generatedContent / init(_:) round trips

    @Test func roundTripsThroughGeneratedContentWithArgumentsAndTimeoutPresent() throws {
        let original = RunScript(
            id: "release-notes", path: "scripts/build.sh", arguments: ["--verbose", "v2"],
            timeout: Self.sampleTimeoutSeconds)

        let decoded = try RunScript(original.generatedContent)

        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.arguments == original.arguments)
        #expect(decoded.timeout == original.timeout)
    }

    @Test func roundTripsThroughGeneratedContentWithNoArgumentsOrTimeout() throws {
        let original = RunScript(id: "release-notes", path: "scripts/build.sh")

        let content = original.generatedContent
        let decoded = try RunScript(content)

        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.arguments == nil)
        #expect(decoded.timeout == nil)
        #expect(!content.jsonString.contains("\"arguments\""))
        #expect(!content.jsonString.contains("\"timeout\""))
    }
}
