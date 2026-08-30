import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape that the org test
/// contract (swissarmyhammer/workflows' README) asks for: one job, which
/// delegates to the shared `swift-ci.yaml` and selects the tests by test
/// target.
///
/// `swift test` at the root runs every suite of the single
/// `FoundationModelsSkillsTests` target. All but one are unit tests. The
/// exception is `HotReloadLiveTests`, which drives a real on-device model,
/// thus `test-skip` holds that suite out of the unit job and
/// `integration-filter` runs it, and only it, in the integration job.
///
/// This suite pins six properties of that shape: the `uses:` line names the
/// shared workflow at `@main`; exactly one job exists and it has no `steps:`
/// key, thus every test run is delegated; the two selectors above name the
/// live-model suite; no other `integration-*` input is present; no source,
/// test, or workflow file names the environment variable that used to gate
/// the live-model suite; the triggers are a push to `main`, a pull request,
/// and a manual dispatch; and a new run of the same ref cancels the run
/// before it. A later edit that points `uses:` somewhere else, adds a
/// repository-local job that runs tests, drops a selector, or drops a
/// trigger, makes this suite fail.
@Suite("CI workflow")
struct CIWorkflowTests {
    /// The full `uses:` value that `ci.yml` must delegate to, pinned to the
    /// `@main` ref the whole package family tracks.
    private static let sharedWorkflowReference =
        "uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main"

    /// The number of jobs `ci.yml` is allowed to declare. One job, and only
    /// one, keeps every test run inside the shared workflow.
    private static let allowedJobCount = 1

    /// The selector that names the live-model suite, in the
    /// `<test-target>.<test-case>/<test>` form the shared workflow's
    /// `test-filter` input describes. `test-skip` holds the suite out of the
    /// unit job, and `integration-filter` runs that same suite, and only it,
    /// in the integration job.
    private static let liveSuiteSelector = "FoundationModelsSkillsTests.HotReloadLiveTests"

    /// The two inputs that `ci.yml` must pass, each with
    /// ``liveSuiteSelector`` as its value. `test-skip` holds the live-model
    /// suite out of the unit job, and `integration-filter` runs it, and only
    /// it, in the integration job.
    private static let requiredLiveSuiteInputs = ["test-skip", "integration-filter"]

    /// The `integration-*` inputs that `ci.yml` must never pass.
    ///
    /// `integration-filter` alone starts the integration job and selects the
    /// live-model suite. `integration-gate-env` is the legacy path, and the
    /// shared workflow stops the job when it arrives beside a selector.
    /// `integration-skip` and `integration-package-path` describe a split this
    /// package does not have: one test target, and one gated suite inside it.
    private static let forbiddenIntegrationInputs = [
        "integration-package-path",
        "integration-skip",
        "integration-gate-env",
    ]

    /// The directories the removed-gate walk reads: this package's own
    /// sources, its tests, and its CI definition. The kanban records under
    /// `.kanban/` are history, and they keep the old name on purpose.
    private static let scannedDirectories = ["Sources", "Tests", ".github"]

    /// The environment variable that used to gate the live-model suite, and
    /// that no file may name any more.
    ///
    /// The name is joined from two parts so that this file, which the walk
    /// itself reads, does not hold the whole name and report itself.
    private static let removedEnvironmentGate = "SKILLS_INTEGRATION" + "_TESTS"

    @Test("ci.yml calls the shared swift-ci.yaml workflow at @main")
    func callsTheSharedWorkflow() throws {
        let lines = try Self.workflowLines()
        let callsShared = lines.contains { line in
            line.trimmingCharacters(in: .whitespaces) == Self.sharedWorkflowReference
        }
        #expect(
            callsShared,
            "ci.yml must contain \"\(Self.sharedWorkflowReference)\"."
        )
    }

    @Test("ci.yml declares exactly one job, and that job delegates instead of running steps")
    func declaresOneDelegatingJob() throws {
        let lines = try Self.workflowLines()
        let jobs = Self.block(under: "jobs:", in: lines)

        // A job key is two-space-indented, e.g. "  ci:". Only the lines below
        // "jobs:" are read, because the two-space-indented children of "on:"
        // (push:, pull_request:, ...) have the same shape and would otherwise
        // count as jobs.
        let jobKeyPattern = try Regex(#"^  [a-zA-Z0-9_-]+:$"#)
        let jobKeys = jobs.filter { $0.wholeMatch(of: jobKeyPattern) != nil }
        #expect(
            jobKeys.count == Self.allowedJobCount,
            """
            ci.yml must declare exactly \(Self.allowedJobCount) job, which delegates to the shared \
            workflow, not repository-local unit or integration jobs; found job keys: \(jobKeys)
            """
        )

        // A "steps:" key is what a repository-local job that runs its own
        // commands looks like. A job that delegates has none.
        let stepKeys = jobs.filter { $0.trimmingCharacters(in: .whitespaces) == "steps:" }
        #expect(
            stepKeys.isEmpty,
            """
            ci.yml must declare no "steps:" key. Every test run is delegated to the shared \
            workflow; found \(stepKeys.count) such key(s).
            """
        )
    }

    @Test("ci.yml holds the live-model suite out of the unit job and runs it in the integration job")
    func passesTheLiveSuiteSelectors() throws {
        let lines = try Self.workflowLines()

        for key in Self.requiredLiveSuiteInputs {
            let values = Self.inputValues(forKey: key, in: lines)
            #expect(
                values == [Self.liveSuiteSelector],
                """
                ci.yml must pass "\(key): \(Self.liveSuiteSelector)" exactly once; found: \(values)
                """
            )
        }

        for key in Self.forbiddenIntegrationInputs {
            let values = Self.inputValues(forKey: key, in: lines)
            #expect(
                values.isEmpty,
                """
                ci.yml must pass no "\(key)" input: integration-filter alone selects the gated \
                suite, and integration-gate-env cannot even be combined with it; found: \(values)
                """
            )
        }
    }

    @Test("no source, test, or workflow file names the removed environment gate")
    func namesNoRemovedEnvironmentGate() throws {
        let root = FixtureLibrary.packageRoot()
        var offenders: [String] = []
        for directory in Self.scannedDirectories {
            let base = root.appendingPathComponent(directory, isDirectory: true)
            guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                Issue.record("Cannot walk \(base.path).")
                continue
            }
            for case let url as URL in walk {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard text.contains(Self.removedEnvironmentGate) else { continue }
                offenders.append(url.path)
            }
        }
        #expect(
            offenders.isEmpty,
            """
            The environment gate is removed: \(Self.removedEnvironmentGate) selects no test any \
            more, and the shared workflow's integration-filter input selects the live-model suite \
            instead. No source, test, or workflow file may name it; found: \(offenders)
            """
        )
    }

    @Test("ci.yml runs on a push to main, on a pull request, and on a manual dispatch")
    func declaresTheExpectedTriggers() throws {
        let lines = try Self.workflowLines()
        let triggers = Self.block(under: "on:", in: lines)

        // Matched with the indentation kept, because the indentation is what
        // makes "branches: [main]" a child of "push:" and not of the "on:"
        // block itself.
        let expectedTriggerLines = [
            "  push:",
            "    branches: [main]",
            "  pull_request:",
            "  workflow_dispatch:",
        ]
        for expected in expectedTriggerLines {
            #expect(
                triggers.contains(Substring(expected)),
                """
                ci.yml must declare the line "\(expected)" in its "on:" block; found: \(triggers)
                """
            )
        }
    }

    @Test("ci.yml cancels a run that a newer run of the same ref supersedes")
    func declaresConcurrencyThatCancelsInProgress() throws {
        let lines = try Self.workflowLines()
        let concurrency = Self.block(under: "concurrency:", in: lines)

        // The group must vary with the ref. A constant group would cancel
        // runs of unrelated branches against each other.
        let groupIsPerRef = concurrency.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("group:") && trimmed.contains("github.ref")
        }
        #expect(
            groupIsPerRef,
            """
            ci.yml must set a "concurrency" group that varies with github.ref; found: \(concurrency)
            """
        )

        let cancelsInProgress = concurrency.contains { line in
            line.trimmingCharacters(in: .whitespaces) == "cancel-in-progress: true"
        }
        #expect(
            cancelsInProgress,
            """
            ci.yml must set "cancel-in-progress: true" in its "concurrency" block; found: \
            \(concurrency)
            """
        )
    }

    /// Reads `.github/workflows/ci.yml` from the package root.
    ///
    /// The root comes from ``FixtureLibrary/packageRoot(thisFile:)``, which
    /// walks up from this file's own `#filePath`. This test target resolves
    /// the package root only there, thus the workflow file is found the same
    /// way as every fixture.
    ///
    /// - Returns: Each line of the workflow file.
    /// - Throws: An error when the file cannot be read.
    private static func workflowLines() throws -> [Substring] {
        let workflow = FixtureLibrary.packageRoot()
            .appendingPathComponent(".github/workflows/ci.yml")
        let text = try String(contentsOf: workflow, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// The value of every `key: value` line of a workflow file whose key
    /// matches `key` without regard to case.
    ///
    /// The case-insensitive read is what GitHub Actions itself does: it
    /// resolves a `with:` key against the called workflow's `inputs:` without
    /// regard to case, so `Integration-Skip:` switches the integration job on
    /// exactly as `integration-skip:` does. A case-sensitive read would let
    /// that spelling through.
    ///
    /// A comment line does not match, because its key carries the leading
    /// `#`. Thus the header comment may name an input in prose.
    ///
    /// - Parameters:
    ///   - key: An input name, written without its colon, e.g.
    ///     `"integration-filter"`.
    ///   - lines: The lines of the workflow file.
    /// - Returns: The values, in file order, or an empty array when no line
    ///   carries that key.
    private static func inputValues(forKey key: String, in lines: [Substring]) -> [String] {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { return nil }
            guard trimmed[..<colon].lowercased() == key.lowercased() else { return nil }
            return trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
    }

    /// The lines nested below the top-level `key` of a workflow file.
    ///
    /// The block starts at the line after `key` and stops at the next line
    /// that has content in column one, that is, at the next top-level key.
    /// Blank lines stay in the block, because they do not end it.
    ///
    /// - Parameters:
    ///   - key: A top-level key, written with its colon, e.g. `"jobs:"`.
    ///   - lines: The lines of the workflow file.
    /// - Returns: The nested lines, or an empty array when `key` is absent.
    private static func block(under key: String, in lines: [Substring]) -> [Substring] {
        guard let keyIndex = lines.firstIndex(of: Substring(key)) else { return [] }
        let below = lines[lines.index(after: keyIndex)...]
        return Array(below.prefix { $0.isEmpty || $0.hasPrefix(" ") })
    }
}
