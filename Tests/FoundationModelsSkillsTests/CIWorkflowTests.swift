import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape that the org test
/// contract (swissarmyhammer/workflows' README) asks for: one job, which
/// delegates to the shared `swift-ci.yaml` and passes it no input.
///
/// The unit job is the whole of CI for this repository. `swift test` at the
/// root runs every unit suite. The one gated suite, `HotReloadLiveTests`,
/// needs `SKILLS_INTEGRATION_TESTS=1` and an on-device model, so the unit job
/// does not run it. The shared workflow starts its integration job only when
/// an `integration-*` input is non-empty, thus the bare `uses:` call keeps
/// that job switched off until a later task wires the gated suite.
///
/// This suite pins four properties of that shape: the `uses:` line names the
/// shared workflow at `@main`; exactly one job exists and it has no `steps:`
/// key, thus every test run is delegated; the triggers are a push to `main`,
/// a pull request, and a manual dispatch; and a new run of the same ref
/// cancels the run before it. A later edit that points `uses:` somewhere
/// else, adds a repository-local job that runs tests, or drops a trigger,
/// makes this suite fail.
@Suite("CI workflow")
struct CIWorkflowTests {
    /// The full `uses:` value that `ci.yml` must delegate to, pinned to the
    /// `@main` ref the whole package family tracks.
    private static let sharedWorkflowReference =
        "uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main"

    /// The number of jobs `ci.yml` is allowed to declare. One job, and only
    /// one, keeps every test run inside the shared workflow.
    private static let allowedJobCount = 1

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
