import Foundation

/// Resolves paths into the fixture skill library at `Examples/skill-library`,
/// relative to the calling test file's own location on disk.
///
/// Hermetic by construction (plan.md §11): resolution walks up from the
/// calling source file's `#filePath`, so it never depends on -- and can never
/// resolve into -- the real home directory or `$XDG_CONFIG_HOME`, regardless
/// of the environment the test suite runs in. Mirrors the family's
/// `#filePath`-relative resolution convention (see `FoundationModelsExtras`'s
/// and `FoundationModelsShelltool`'s own `PackageRootValidation.packageRoot`),
/// kept internal to this single test target rather than split into a
/// separate `TestSupport` module.
enum FixtureLibrary {
    /// The package root directory, derived from the caller's own source-file
    /// path: three levels up from
    /// `Tests/FoundationModelsSkillsTests/<file>.swift`.
    ///
    /// The `thisFile` default (`#filePath`) expands at the *call site*, so it
    /// names whichever test file invokes this. Every file in this test
    /// target lives in `Tests/FoundationModelsSkillsTests/`, so the
    /// three-levels-up derivation is identical regardless of caller.
    /// `thisFile` is injectable for tests.
    ///
    /// - Parameter thisFile: The calling source file's path; defaults to the
    ///   call site's `#filePath`.
    /// - Returns: The package root URL.
    static func packageRoot(thisFile: String = #filePath) -> URL {
        URL(fileURLWithPath: thisFile)
            .deletingLastPathComponent()  // <file>.swift -> FoundationModelsSkillsTests/
            .deletingLastPathComponent()  // FoundationModelsSkillsTests/ -> Tests/
            .deletingLastPathComponent()  // Tests/ -> package root
    }

    /// The root of the fixture skill library: `Examples/skill-library`, the
    /// three-layer `.skills` dotfolder stack (plan.md §11) plus its sibling
    /// `broken/` fixtures for lenient-validation tests.
    ///
    /// - Parameter thisFile: Forwarded to `packageRoot(thisFile:)`.
    /// - Returns: The `Examples/skill-library` directory URL.
    static func root(thisFile: String = #filePath) -> URL {
        packageRoot(thisFile: thisFile)
            .appendingPathComponent("Examples", isDirectory: true)
            .appendingPathComponent("skill-library", isDirectory: true)
    }

    /// Resolves `relativePath` (e.g. `"defaults/base-style/SKILL.md"`)
    /// against `root(thisFile:)`.
    ///
    /// `relativePath` must be a genuinely relative path with no `..`
    /// components and no `/` or `~` prefix, since this is test-support code
    /// that builds filesystem paths from caller-supplied strings -- rejecting
    /// traversal keeps every resolved fixture URL under `root(thisFile:)`.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to `Examples/skill-library`, with no
    ///     `..` traversal and no leading `/` or `~`.
    ///   - thisFile: Forwarded to `root(thisFile:)`.
    /// - Returns: The resolved fixture URL.
    static func url(relativePath: String, thisFile: String = #filePath) -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        precondition(
            !relativePath.hasPrefix("/") && !relativePath.hasPrefix("~")
                && !components.contains(".."),
            "FixtureLibrary.url: relativePath must not be absolute or contain \"..\" "
                + "traversal, got \"\(relativePath)\""
        )
        return root(thisFile: thisFile).appendingPathComponent(relativePath)
    }
}
