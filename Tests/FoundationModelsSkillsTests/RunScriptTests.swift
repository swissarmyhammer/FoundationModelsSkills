import Darwin
import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing

/// Tests for the `run script` operation (plan.md §7.3.1): the triple gate,
/// unknown/model-hidden id correctives, the direct-exec eligibility check
/// (executable bit + shebang), process-group timeout kill, and a golden
/// result against the static `release-notes` fixture.
struct RunScriptTests {
    // MARK: - Fixture root (mirrors ResourceOpsTests)

    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")

    /// Builds a `SkillsToolContext` over `roots` under `policy`.
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
        let registry = SkillsRegistry(roots: roots, policy: policy)
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
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

    @Test func runScriptRefusesWithNoGrantAtAll() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMinimalSkillFile(id: "no-grant", in: root, allowedTools: nil)
        try Self.writeExecutableShebangScript(named: "run.sh", inSkillID: "no-grant", under: root)

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
        try Self.writeMinimalSkillFile(id: "narrow-grant", in: root, allowedTools: "Script(scripts/other/*)")
        try Self.writeExecutableShebangScript(named: "run.sh", inSkillID: "narrow-grant", under: root)

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

    // MARK: - Direct-exec eligibility: executable bit + shebang

    @Test func runScriptRefusesANonExecutableFile() async throws {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMinimalSkillFile(id: "not-executable", in: root, allowedTools: "Script")
        let scriptURL = try Self.scriptsDirectory(inSkillID: "not-executable", under: root)
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
        try Self.writeMinimalSkillFile(id: "no-shebang", in: root, allowedTools: "Script")
        let scriptURL = try Self.scriptsDirectory(inSkillID: "no-shebang", under: root)
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
        try Self.writeMinimalSkillFile(id: "sleeper", in: root, allowedTools: "Script")
        let scriptURL = try Self.scriptsDirectory(inSkillID: "sleeper", under: root)
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
    }

    // MARK: - Fixture helpers

    /// Writes a minimal, always-valid `id/SKILL.md` under `directory`,
    /// creating the skill's own subdirectory first.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - directory: The root to write under.
    ///   - allowedTools: The raw `allowed-tools:` frontmatter value to
    ///     write, or `nil` to omit the field entirely.
    /// - Returns: The created skill directory.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    @discardableResult
    private static func writeMinimalSkillFile(id: String, in directory: URL, allowedTools: String?) throws -> URL {
        let skillDirectory = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let allowedToolsLine = allowedTools.map { "allowed-tools: \"\($0)\"\n" } ?? ""
        try "---\nname: \(id)\ndescription: run-script fixture.\n\(allowedToolsLine)---\nBody text for \(id).\n"
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return skillDirectory
    }

    /// The `scripts/` subdirectory under `id`'s skill directory, created if
    /// it does not already exist.
    ///
    /// - Parameters:
    ///   - id: The owning skill id.
    ///   - directory: The root the skill lives under.
    /// - Returns: The `scripts/` directory.
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    private static func scriptsDirectory(inSkillID id: String, under directory: URL) throws -> URL {
        let scriptsDirectory = directory.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        return scriptsDirectory
    }

    /// Writes an executable, shebang-carrying script named `name` under
    /// `id`'s `scripts/` directory.
    ///
    /// - Parameters:
    ///   - name: The script's file name.
    ///   - id: The owning skill id.
    ///   - directory: The root the skill lives under.
    /// - Throws: Whatever `FileManager.createDirectory`, `String.write`, or
    ///   `FileManager.setAttributes` throws.
    private static func writeExecutableShebangScript(named name: String, inSkillID id: String, under directory: URL)
        throws
    {
        let scriptURL = try Self.scriptsDirectory(inSkillID: id, under: directory).appendingPathComponent(name)
        try "#!/bin/sh\necho hi\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }
}
