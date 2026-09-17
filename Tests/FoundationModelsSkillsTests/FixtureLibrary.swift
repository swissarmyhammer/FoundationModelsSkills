import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsSkills

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

    /// The root folder of one marketplace catalog fixture:
    /// `Examples/marketplace-fixtures/catalogs/<name>` (marketplace.md §13).
    ///
    /// Each fixture is a small hand-written copy of a catalog tree. The
    /// resolution walks up from `#filePath`, as ``packageRoot(thisFile:)``
    /// does, so it never reads a real marketplace or the network.
    ///
    /// - Parameters:
    ///   - name: The folder name of the fixture, one path component.
    ///   - thisFile: Forwarded to `packageRoot(thisFile:)`.
    /// - Returns: The fixture folder URL.
    static func marketplaceCatalog(named name: String, thisFile: String = #filePath) -> URL {
        precondition(
            !name.contains("/") && name != "..",
            "FixtureLibrary.marketplaceCatalog: name must be one path component, got \"\(name)\"")
        return packageRoot(thisFile: thisFile)
            .appendingPathComponent("Examples", isDirectory: true)
            .appendingPathComponent("marketplace-fixtures", isDirectory: true)
            .appendingPathComponent("catalogs", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// The three-layer dotfolder stack over the fixture library:
    /// `defaults/`, `user/`, and the `project/` working directory.
    ///
    /// Mirrors the `Examples/skills-demo` target's own `FixtureStack.make()`,
    /// but from this test target, and with an empty environment. An empty
    /// environment keeps `SKILLS_DEFAULTS_DIR` and `XDG_CONFIG_HOME` from
    /// moving a layer onto a real host directory, thus the stack stays
    /// hermetic (plan.md §11).
    ///
    /// - Parameter thisFile: Forwarded to `root(thisFile:)`.
    /// - Returns: The fixture stack, ready for `SkillsRegistry(stack:)`.
    static func stack(thisFile: String = #filePath) -> DotfolderStack {
        let libraryRoot = root(thisFile: thisFile)
        return DotfolderStack(
            name: "skills",
            workingDirectory: libraryRoot.appendingPathComponent("project", isDirectory: true),
            defaultsDirectory: libraryRoot.appendingPathComponent("defaults", isDirectory: true),
            userDirectory: libraryRoot.appendingPathComponent("user", isDirectory: true),
            environment: [:])
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
        resolve(relativePath: relativePath, under: root(thisFile: thisFile))
    }

    /// Reads the file at `relativePath` -- e.g. `"docs/marketplaces.md"` --
    /// resolved against `packageRoot(thisFile:)`, as UTF-8 text.
    ///
    /// The one file reader of this test target. Suites that hold the
    /// documentation and the manifests of this package to the behavior that
    /// shipped read their files through it, thus no suite keeps its own copy
    /// of the same two lines.
    ///
    /// The read is deliberately unguarded: an absent file must fail the case
    /// that reads it, and must never make that case pass on an empty string.
    ///
    /// `relativePath` obeys the same rule as ``url(relativePath:thisFile:)``:
    /// no `..` component, and no `/` or `~` prefix, thus every file read stays
    /// under the package root.
    ///
    /// - Parameters:
    ///   - relativePath: A path relative to the package root, with no `..`
    ///     traversal and no leading `/` or `~`.
    ///   - thisFile: Forwarded to `packageRoot(thisFile:)`.
    /// - Returns: The whole text of the file.
    /// - Throws: An error when the file is not there, or is not UTF-8 text.
    static func readText(relativePath: String, thisFile: String = #filePath) throws -> String {
        let file = resolve(relativePath: relativePath, under: packageRoot(thisFile: thisFile))
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// Appends `relativePath` to `base`, and refuses a path that could leave
    /// `base`.
    ///
    /// This is test-support code that builds filesystem paths from
    /// caller-supplied strings. A rejected traversal keeps every resolved URL
    /// under `base`.
    ///
    /// - Parameters:
    ///   - relativePath: The path to append, with no `..` traversal and no
    ///     leading `/` or `~`.
    ///   - base: The directory the path resolves against.
    /// - Returns: The resolved URL.
    private static func resolve(relativePath: String, under base: URL) -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        precondition(
            !relativePath.hasPrefix("/") && !relativePath.hasPrefix("~")
                && !components.contains(".."),
            "FixtureLibrary: relativePath must not be absolute or contain \"..\" "
                + "traversal, got \"\(relativePath)\""
        )
        return base.appendingPathComponent(relativePath)
    }

    /// Builds a `SkillsToolContext` over `registry`, with a real,
    /// GPU-free `.retrieval`-mode `MetadataSearcher` (no embedder, no
    /// session) standing in for the stub-searcher context the acceptance
    /// criteria call for.
    ///
    /// Shared by `SkillOperationsTests.makeFixtureContext()` (the model
    /// surface's own registry) and `SkillsCLITests.makeModelTool(registry:)`
    /// (a registry the CLI test also drives directly), so the two suites'
    /// dispatch-context construction can never drift.
    ///
    /// - Parameter registry: The registry the resulting context wraps.
    /// - Returns: The assembled context.
    static func makeSkillsToolContext(registry: SkillsRegistry) -> SkillsToolContext {
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return SkillsToolContext(registry: registry, searchAgent: SkillSearchAgent(searcher: searcher))
    }
}
