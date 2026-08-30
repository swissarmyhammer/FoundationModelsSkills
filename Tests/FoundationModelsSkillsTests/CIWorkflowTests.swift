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
///
/// Two more cases pin the reader that the input assertions use, and not the
/// workflow file: ``inputValues(forKey:in:)`` finds a key in whichever case
/// the file spells it, and in whichever case a test asks for it. GitHub
/// Actions does the same, thus a reader that keeps the case lets a forbidden
/// input spelled `Integration-Skip:` go through this suite without a report.
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

    /// A `with:` block that spells every input this suite reads in a case
    /// that no lowercase text match finds.
    ///
    /// GitHub Actions resolves a `with:` key against the called workflow's
    /// `inputs:` without regard to case. Thus `Integration-Skip:` reaches the
    /// same input as `integration-skip:` does. This fixture is the proof that
    /// ``inputValues(forKey:in:)`` reads such a line, because a reader that
    /// misses it lets a forbidden input go through
    /// ``passesTheLiveSuiteSelectors()`` without a report.
    ///
    /// The value on each line is different from the others. Thus a match
    /// against the wrong line is visible in the failure message.
    private static let mixedCaseInputFixture = """
        jobs:
          ci:
            with:
              Test-Skip: mixed-case-test-skip
              INTEGRATION-FILTER: mixed-case-integration-filter
              Integration-Package-Path: mixed-case-integration-package-path
              Integration-Skip: mixed-case-integration-skip
              INTEGRATION-GATE-ENV: mixed-case-integration-gate-env
        """

    /// The lowercase input name of each line of ``mixedCaseInputFixture``,
    /// with the value that line carries.
    ///
    /// The list holds every name of ``requiredLiveSuiteInputs`` and of
    /// ``forbiddenIntegrationInputs``. Thus each assertion of
    /// ``passesTheLiveSuiteSelectors()`` has its key covered.
    private static let mixedCaseFixtureExpectations = [
        (input: "test-skip", value: "mixed-case-test-skip"),
        (input: "integration-filter", value: "mixed-case-integration-filter"),
        (input: "integration-package-path", value: "mixed-case-integration-package-path"),
        (input: "integration-skip", value: "mixed-case-integration-skip"),
        (input: "integration-gate-env", value: "mixed-case-integration-gate-env"),
    ]

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

    @Test("an input key resolves in whichever case the workflow file spells it")
    func readsAnInputKeyThatTheFileSpellsInMixedCase() {
        let fixture = Self.lines(of: Self.mixedCaseInputFixture)
        for (input, value) in Self.mixedCaseFixtureExpectations {
            let values = Self.inputValues(forKey: input, in: fixture)
            #expect(
                values == [value],
                """
                GitHub Actions accepts a `with:` key in any case, thus "\(input)" must read the \
                mixed-case line of the fixture. A reader that keeps the case of the file lets a \
                forbidden input spelled "Integration-Skip:" go through the assertions above \
                without a report; found: \(values)
                """
            )
        }
    }

    @Test("an input key resolves in whichever case a test asks for it")
    func readsAnInputKeyThatTheTestAsksForInMixedCase() throws {
        let lines = try Self.workflowLines()

        // ci.yml spells its own keys in lower case, thus this is the other
        // half of the same contract: the asked key may carry any case.
        for key in Self.requiredLiveSuiteInputs {
            for spelling in [key.uppercased(), key.capitalized] {
                let values = Self.inputValues(forKey: spelling, in: lines)
                #expect(
                    values == [Self.liveSuiteSelector],
                    """
                    An input name is case-insensitive on both sides, thus "\(spelling)" must read \
                    the "\(key)" line of ci.yml. A reader that keeps the case of the asked key \
                    makes each assertion above depend on one spelling; found: \(values)
                    """
                )
            }
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
        return Self.lines(of: try String(contentsOf: workflow, encoding: .utf8))
    }

    /// Cuts workflow text into lines.
    ///
    /// ``workflowLines()`` and the in-test fixtures both go through here, thus
    /// a fixture has the same shape as the real file. An empty line stays,
    /// because a reader must step over it as the file has it.
    ///
    /// - Parameter text: The text of a workflow file, or of a fixture.
    /// - Returns: Each line of that text.
    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
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
