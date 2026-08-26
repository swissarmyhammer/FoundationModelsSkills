import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `SkillsRegistry`'s static core (plan.md §3, §6, §6.1, §7.1;
/// decisions #13/#25/#28/#29): the fixture-root construction snapshot, the
/// full plan.md §6 visibility matrix, `commandListing()`/`metadata()`'s
/// deliberate disagreement on the two visibility-split fixtures, `call(id:
/// arguments:)` argument plumbing and its unknown/hidden-id error, `metadata.*`
/// templating (rendered through pass 3, never pass 2), and the "no directory
/// convention literal" source grep.
struct SkillsRegistryTests {
    // MARK: - Fixture roots (mirrors SkillDiscoveryTests)

    private static let defaultsRoot = FixtureLibrary.url(relativePath: "defaults")
    private static let userRoot = FixtureLibrary.url(relativePath: "user")
    private static let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")
    private static let brokenRoot = FixtureLibrary.url(relativePath: "broken")

    /// The §11 fixture stack's three layer roots, lowest precedence first.
    private static let fixtureRoots = [defaultsRoot, userRoot, projectSkillsRoot]

    /// Every id the §11 fixture stack's three layers structurally carry a
    /// `SKILL.md` for, regardless of visibility.
    private static let expectedFixtureIDs: Set<String> = [
        "base-style", "commit", "deploy", "env-report", "git-context", "lint", "release-notes", "spec-clean",
    ]

    // MARK: - Construction snapshot

    @Test func constructionOverFixtureRootsBuildsACatalogEntryForEveryStructuralSkill() {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        #expect(Set(registry.metadata().map(\.id)) == Self.expectedFixtureIDs)
    }

    @Test func diagnosticsCarryTheWinningRootProvenanceForTheShadowedFixture() throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let shadowDiagnostic = try #require(
            registry.diagnostics.first { $0.skillID == "base-style" && $0.severity == .advisory })
        #expect(shadowDiagnostic.provenance.root.path == Self.userRoot.path)
    }

    @Test func stackConvenienceInitProducesTheSameCatalogAsPassingRootsDirectly() {
        let stack = DotfolderStack(
            name: "skills", workingDirectory: FixtureLibrary.url(relativePath: "project"),
            defaultsDirectory: Self.defaultsRoot, userDirectory: Self.userRoot)

        let viaStack = SkillsRegistry(stack: stack)
        let viaRoots = SkillsRegistry(roots: Self.fixtureRoots)

        #expect(Set(viaStack.metadata().map(\.id)) == Set(viaRoots.metadata().map(\.id)))
        #expect(Set(viaStack.commandListing().map(\.id)) == Set(viaRoots.commandListing().map(\.id)))
    }

    @Test func stackConvenienceInitRendersTheDefaultsLayerTrustedUnlikeTheSameDirectoryPassedAsABareRoot()
        throws
    {
        let defaultsDirectory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: defaultsDirectory) }
        try Self.writeMetadataRenderFailureSkill(in: defaultsDirectory)

        // Same directory, two construction paths: `init(stack:)` preserves
        // this layer's `.defaults` tag (renders trusted, so `| uppercase`
        // succeeds); `init(roots:)` has no such signal from a bare `[URL]`
        // (renders untrusted, so it falls back to raw text, matching
        // `metadataRenderFailureFallsBackToUnrenderedTextRatherThanThrowing`).
        var stack = DotfolderStack(
            name: "skills", workingDirectory: try Self.makeTempDirectory(),
            defaultsDirectory: defaultsDirectory, userDirectory: try Self.makeTempDirectory())
        defer {
            for layer in stack.layers { try? FileManager.default.removeItem(at: layer.root) }
        }
        // `DotfolderStack.init` always appends a user and project layer even
        // though this test only cares about the defaults one; harmless
        // (both roots stay empty) but tidied up above regardless.
        stack.layers = [DotfolderStack.Layer(source: .defaults, root: defaultsDirectory)]

        let viaStack = SkillsRegistry(stack: stack)
        let viaRoots = SkillsRegistry(roots: [defaultsDirectory])

        let expectedWorkingDirectory = FileManager.default.currentDirectoryPath
        let stackEntry = try #require(viaStack.metadata().first { $0.id == "metadata-render-failure" })
        #expect(
            stackEntry.metadata["filtered-value"]
                == .string("will-fail=\(expectedWorkingDirectory.uppercased())"))

        let rootsEntry = try #require(viaRoots.metadata().first { $0.id == "metadata-render-failure" })
        #expect(rootsEntry.metadata["filtered-value"] == .string("will-fail={{ working_directory | uppercase }}"))
    }

    // MARK: - Visibility matrix (plan.md §6's four-row table)

    /// One row of the plan.md §6 visibility table, expressed as a fixture
    /// id plus its expected surface flags and a distinguishing body snippet
    /// to probe `preloadedBodies()` with.
    private struct VisibilityCase: Sendable {
        let id: String
        let bodyMarker: String
        let isModelVisible: Bool
        let isUserInvocable: Bool
        let isPreloaded: Bool
    }

    private static let visibilityCases: [VisibilityCase] = [
        VisibilityCase(
            id: "spec-clean", bodyMarker: "maximum agentskills.io portability",
            isModelVisible: true, isUserInvocable: true, isPreloaded: false),
        VisibilityCase(
            id: "deploy", bodyMarker: "Deploy the current build.",
            isModelVisible: false, isUserInvocable: true, isPreloaded: false),
        VisibilityCase(
            id: "lint", bodyMarker: "Run the linter over the project",
            isModelVisible: true, isUserInvocable: false, isPreloaded: false),
        VisibilityCase(
            id: "git-context", bodyMarker: "on branch main, working tree clean",
            isModelVisible: true, isUserInvocable: true, isPreloaded: true),
    ]

    @Test(
        "visibility matrix (plan.md §6): default, disable-model-invocation, user-invocable:false, preload:true",
        arguments: visibilityCases)
    private func visibilityMatrixMatchesPlanSectionSix(_ testCase: VisibilityCase) {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)

        let metadataEntry = registry.metadata().first { $0.id == testCase.id }
        #expect(metadataEntry?.isModelVisible == testCase.isModelVisible, "\(testCase.id): model-visibility flag")

        let isListed = registry.commandListing().contains { $0.id == testCase.id }
        #expect(isListed == testCase.isUserInvocable, "\(testCase.id): user menu listing")

        let isPreloaded = registry.preloadedBodies().contains(testCase.bodyMarker)
        #expect(isPreloaded == testCase.isPreloaded, "\(testCase.id): preload injection")
    }

    // MARK: - commandListing() / metadata() deliberate disagreement

    @Test func commandListingAndMetadataDisagreeExactlyOnDeployAndLint() {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let listedIDs = Set(registry.commandListing().map(\.id))
        let metadataByID = Dictionary(uniqueKeysWithValues: registry.metadata().map { ($0.id, $0) })

        #expect(listedIDs.contains("deploy"))
        #expect(metadataByID["deploy"]?.isModelVisible == false)

        #expect(!listedIDs.contains("lint"))
        #expect(metadataByID["lint"]?.isModelVisible == true)

        for id in Set(metadataByID.keys).subtracting(["deploy", "lint"]) {
            #expect(
                listedIDs.contains(id) == (metadataByID[id]?.isModelVisible == true),
                "\(id) unexpectedly disagrees between the two surfaces")
        }
    }

    // MARK: - metadata() parameter summaries

    @Test func metadataCarriesTheArgumentHintPlaceholderSummaryForCommit() throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        let entry = try #require(registry.metadata().first { $0.id == "commit" })
        #expect(entry.parameters == ["<message>"])
    }

    // MARK: - preloadedBodies() honors RenderPolicy

    @Test func shellExecutionDisabledPolicyAppliesToPreloadedBodies() {
        let registry = SkillsRegistry(
            roots: Self.fixtureRoots, policy: RenderPolicy(isShellExecutionDisabled: true))
        let preloaded = registry.preloadedBodies()
        #expect(preloaded.contains(ShellInjection.disabledMarker))
        #expect(!preloaded.contains("on branch main, working tree clean"))
    }

    @Test func shellExecutionDisabledPolicyAppliesToCallIDArguments() throws {
        // §25 coverage gap (^zbv0t4j): the disable flag was previously only
        // proven on the preload path -- `call(id:arguments:)` is the exact
        // same path `use skill` and the CLI's `skill use` dispatch through.
        let registry = SkillsRegistry(
            roots: Self.fixtureRoots, policy: RenderPolicy(isShellExecutionDisabled: true))

        let body = try registry.call(id: "git-context")

        #expect(body.contains(ShellInjection.disabledMarker))
        #expect(!body.contains("on branch main, working tree clean"))
    }

    // MARK: - call(id:arguments:) plumbing

    @Test func callCommitSubstitutesSuppliedArgumentsIntoTheRenderedBody() throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        // A caller building `arguments` element-by-element (rather than typing
        // one raw command line) quotes a multi-word value, the same discipline
        // $N/$ARGUMENTS[N] shell-style tokenizing already requires -- see
        // `RenderRequest.argumentNames`'s own doc comment.
        let body = try registry.call(id: "commit", arguments: [#""fix parser bug""#])
        #expect(body.contains("Commit the currently staged changes using the message: fix parser bug"))
        #expect(!body.contains("$0"))
    }

    @Test func callUnknownIDThrowsCarryingTheCurrentValidIDs() throws {
        let registry = SkillsRegistry(roots: Self.fixtureRoots)
        var thrown: UnknownSkillError?
        do {
            _ = try registry.call(id: "does-not-exist")
        } catch let error as UnknownSkillError {
            thrown = error
        }
        let error = try #require(thrown)
        #expect(error.id == "does-not-exist")
        #expect(Set(error.validIDs) == Self.expectedFixtureIDs)
        #expect(error.validIDs == error.validIDs.sorted())
    }

    @Test func callOnAValidatorHiddenIDThrowsTheSameUnknownSkillError() throws {
        let registry = SkillsRegistry(roots: [Self.brokenRoot])
        var thrown: UnknownSkillError?
        do {
            _ = try registry.call(id: "partial-flag")
        } catch let error as UnknownSkillError {
            thrown = error
        }
        let error = try #require(thrown)
        #expect(error.id == "partial-flag")
        #expect(!error.validIDs.contains("partial-flag"))
    }

    // MARK: - metadata.* templating: pass 3 runs, pass 2 never does

    /// Writes `id/SKILL.md` directly under `root`, creating the skill's own
    /// subdirectory first -- the shared workhorse every temp-dir fixture
    /// writer in this file builds on, so the create-directory-then-write
    /// steps live in exactly one place.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and (by
    ///     convention, not enforced here) `skillMarkdown`'s own `name:`.
    ///   - skillMarkdown: The complete `SKILL.md` file contents, frontmatter
    ///     fence included.
    ///   - root: The directory to write the skill's own subdirectory under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeSkillFixture(id: String, skillMarkdown: String, in root: URL) throws {
        let skillDirectory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try skillMarkdown.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    /// Writes a minimal `SKILL.md` under `root`, whose `description:` and
    /// three `metadata.*` values exercise every templating claim at once.
    ///
    /// A `{{ working_directory }}` reference should render (pass 3 runs at
    /// metadata-build time), including one nested inside a `metadata.*`
    /// array element and one nested inside a `metadata.*` mapping element
    /// (proving rendering recurses into both collection shapes, not just
    /// top-level scalars); a `` !`echo x` `` shell-injection-shaped value
    /// should stay completely inert (pass 2 never runs at metadata-build
    /// time -- only pass 1 and pass 3 do, per `RenderPipeline.renderMetadata`).
    ///
    /// - Parameter root: The directory to write the skill's own subdirectory
    ///   and `SKILL.md` under.
    /// - Throws: Whatever `writeSkillFixture(id:skillMarkdown:in:)` throws.
    private static func writeMetadataTemplatingSkill(in root: URL) throws {
        try writeSkillFixture(
            id: "metadata-templating",
            skillMarkdown: """
                ---
                name: metadata-templating
                description: "Working directory is {{ working_directory }}."
                metadata:
                  templated-value: "wd={{ working_directory }}"
                  shell-like-value: "raw=!`echo x`"
                  nested-values:
                    - "tag={{ working_directory }}"
                  nested-mapping:
                    inner-key: "mapped={{ working_directory }}"
                ---
                Body text, unused by this fixture's own tests.
                """,
            in: root)
    }

    /// Creates a fresh, empty temporary directory for a test root, so one
    /// test's filesystem activity can never be observed by another.
    ///
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    /// - Returns: The new directory's URL.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func descriptionAndMetadataStringValuesRenderThroughPass3ButShellInjectionNeverRunsAtMetadataBuildTime()
        throws
    {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMetadataTemplatingSkill(in: root)
        let expectedWorkingDirectory = FileManager.default.currentDirectoryPath

        let registry = SkillsRegistry(roots: [root])

        let metadataEntry = try #require(registry.metadata().first { $0.id == "metadata-templating" })
        #expect(metadataEntry.description == "Working directory is \(expectedWorkingDirectory).")
        #expect(metadataEntry.metadata["templated-value"] == .string("wd=\(expectedWorkingDirectory)"))
        #expect(metadataEntry.metadata["shell-like-value"] == .string("raw=!`echo x`"))
        #expect(
            metadataEntry.metadata["nested-values"]
                == .array([.string("tag=\(expectedWorkingDirectory)")]))
        #expect(
            metadataEntry.metadata["nested-mapping"]
                == .dictionary(["inner-key": .string("mapped=\(expectedWorkingDirectory)")]))

        let listingEntry = try #require(registry.commandListing().first { $0.id == "metadata-templating" })
        #expect(listingEntry.description == "Working directory is \(expectedWorkingDirectory).")
    }

    // MARK: - metadata() render failure falls back to unrendered text

    /// Writes a `SKILL.md` under `root` whose `metadata.filtered-value:`
    /// uses a real Stencil filter (`uppercase`) that untrusted rendering's
    /// empty filter whitelist genuinely rejects -- unlike
    /// `writeMetadataTemplatingSkill(in:)`'s inert shell-injection syntax,
    /// this is a syntactically valid template that fails to render, proving
    /// `renderedMetadataText(text:entry:)`'s `try?` fallback path is reached
    /// by an actual failure, not merely syntax Stencil never recognized in
    /// the first place.
    ///
    /// - Parameter root: The directory to write the skill's own subdirectory
    ///   and `SKILL.md` under.
    /// - Throws: Whatever `writeSkillFixture(id:skillMarkdown:in:)` throws.
    private static func writeMetadataRenderFailureSkill(in root: URL) throws {
        try writeSkillFixture(
            id: "metadata-render-failure",
            skillMarkdown: """
                ---
                name: metadata-render-failure
                description: A registry test fixture proving a genuine render failure falls back to raw text.
                metadata:
                  filtered-value: "will-fail={{ working_directory | uppercase }}"
                ---
                Body text, unused by this fixture's own tests.
                """,
            in: root)
    }

    @Test func metadataRenderFailureFallsBackToUnrenderedTextRatherThanThrowing() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMetadataRenderFailureSkill(in: root)

        // `init(roots:)` renders every layer untrusted (no `.defaults`
        // signal available from a bare `[URL]`), and untrusted rendering's
        // filter whitelist starts empty -- `| uppercase` is a real Stencil
        // filter that would succeed under `.trusted`, so this genuinely
        // fails here rather than never having been valid syntax.
        let registry = SkillsRegistry(roots: [root])
        let entry = try #require(registry.metadata().first { $0.id == "metadata-render-failure" })
        #expect(entry.metadata["filtered-value"] == .string("will-fail={{ working_directory | uppercase }}"))
    }

    // MARK: - preload composes independently of model/user visibility

    /// Writes a `SKILL.md` under `root` with both `preload: true` and
    /// `disable-model-invocation: true` set together, proving the three
    /// visibility axes `ResolvedVisibility` computes are independent: a
    /// model-hidden skill's body still gets preloaded.
    ///
    /// - Parameter root: The directory to write the skill's own subdirectory
    ///   and `SKILL.md` under.
    /// - Throws: Whatever `writeSkillFixture(id:skillMarkdown:in:)` throws.
    private static func writePreloadedModelHiddenSkill(in root: URL) throws {
        try writeSkillFixture(
            id: "preloaded-model-hidden",
            skillMarkdown: """
                ---
                name: preloaded-model-hidden
                description: A registry test fixture combining preload:true with disable-model-invocation:true.
                preload: true
                disable-model-invocation: true
                ---
                PRELOADED_MODEL_HIDDEN_MARKER
                """,
            in: root)
    }

    @Test func preloadInjectsTheBodyEvenWhenTheSameSkillIsModelHidden() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writePreloadedModelHiddenSkill(in: root)

        let registry = SkillsRegistry(roots: [root])

        let entry = try #require(registry.metadata().first { $0.id == "preloaded-model-hidden" })
        #expect(entry.isModelVisible == false)
        #expect(registry.commandListing().contains { $0.id == "preloaded-model-hidden" })
        #expect(registry.preloadedBodies().contains("PRELOADED_MODEL_HIDDEN_MARKER"))
    }

    // MARK: - Parameter-inference diagnostics fold into the registry surface

    /// Writes a `SKILL.md` under `root` whose `arguments:` names three
    /// parameters but `argument-hint:` only supplies two tokens -- an arity
    /// mismatch `ParameterInference.infer` records as a diagnostic (plan.md
    /// §6.1).
    ///
    /// - Parameter root: The directory to write the skill's own subdirectory
    ///   and `SKILL.md` under.
    /// - Throws: Whatever `writeSkillFixture(id:skillMarkdown:in:)` throws.
    private static func writeArityMismatchSkill(in root: URL) throws {
        try writeSkillFixture(
            id: "arity-mismatch",
            skillMarkdown: """
                ---
                name: arity-mismatch
                description: "A registry test fixture whose arguments: and argument-hint: disagree in count."
                arguments: message channel urgency
                argument-hint: "<message> [channel]"
                ---
                Body text, unused by this fixture's own tests.
                """,
            in: root)
    }

    @Test func anArgumentsArgumentHintArityMismatchProducesARegistryDiagnosticNamingTheSkillAndTheMismatch()
        throws
    {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeArityMismatchSkill(in: root)

        let registry = SkillsRegistry(roots: [root])

        let diagnostic = try #require(
            registry.diagnostics.first { $0.skillID == "arity-mismatch" && $0.severity == .advisory })
        #expect(diagnostic.message.contains("argument-hint:"))
        #expect(diagnostic.message.contains("arguments:"))
        #expect(diagnostic.provenance.root.path == root.path)
    }

    // MARK: - Frontmatter decode notes fold into the registry surface

    /// Writes a `SKILL.md` under `root` whose frontmatter carries the given
    /// extension-field lines -- the shared writer for the two decode-note
    /// fixtures (a mistyped `metadata.*` value, and a field spelled both
    /// top-level and under `metadata.*`), which differ only in those lines.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and `name:`.
    ///   - extensionFrontmatter: The extension-field YAML lines to place
    ///     after `description:`, top-level indentation.
    ///   - root: The directory to write the skill's own subdirectory
    ///     and `SKILL.md` under.
    /// - Throws: Whatever `writeSkillFixture(id:skillMarkdown:in:)` throws.
    private static func writeDecodeNoteSkill(id: String, extensionFrontmatter: String, in root: URL) throws {
        try writeSkillFixture(
            id: id,
            skillMarkdown: """
                ---
                name: \(id)
                description: A registry test fixture whose frontmatter draws a decoder note.
                \(extensionFrontmatter)
                ---
                Body text, unused by this fixture's own tests.
                """,
            in: root)
    }

    @Test func aMistypedMetadataExtensionValueProducesARegistryAdvisoryNamingTheKeyAndExpectedType() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeDecodeNoteSkill(
            id: "mistyped-metadata",
            extensionFrontmatter: """
                metadata:
                  preload: "true"
                """,
            in: root)

        let registry = SkillsRegistry(roots: [root])

        let diagnostic = try #require(
            registry.diagnostics.first { $0.skillID == "mistyped-metadata" && $0.severity == .advisory })
        #expect(diagnostic.message == "metadata.preload is present but is not a boolean; ignoring.")
        #expect(diagnostic.provenance.rootIndex == 0)
        #expect(diagnostic.provenance.root.path == root.path)
        #expect(registry.metadata().contains { $0.id == "mistyped-metadata" })
        #expect(registry.preloadedBodies().isEmpty)
    }

    @Test func aFieldSpelledBothTopLevelAndUnderMetadataProducesARegistryConflictAdvisory() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeDecodeNoteSkill(
            id: "both-spellings",
            extensionFrontmatter: """
                preload: true
                metadata:
                  preload: false
                """,
            in: root)

        let registry = SkillsRegistry(roots: [root])

        let diagnostic = try #require(
            registry.diagnostics.first { $0.skillID == "both-spellings" && $0.severity == .advisory })
        #expect(
            diagnostic.message
                == "'preload' is set both top-level and under metadata.preload; using the top-level value.")
        #expect(diagnostic.provenance.rootIndex == 0)
        #expect(diagnostic.provenance.root.path == root.path)
        #expect(registry.preloadedBodies().contains("Body text, unused by this fixture's own tests."))
    }

    // MARK: - commandListing() description truncation

    /// Writes a `SKILL.md` under `root` whose `description:` is well over
    /// `SkillsRegistry`'s menu truncation cap, built from repeated words so
    /// the truncation boundary always lands on a space.
    ///
    /// - Parameter root: The directory to write the skill's own subdirectory
    ///   and `SKILL.md` under.
    /// - Throws: Whatever `writeSkillFixture(id:skillMarkdown:in:)` throws.
    private static func writeLongDescriptionSkill(in root: URL) throws {
        let longDescription = Array(repeating: "wordwordword", count: 30).joined(separator: " ")
        try writeSkillFixture(
            id: "long-description",
            skillMarkdown: """
                ---
                name: long-description
                description: "\(longDescription)"
                ---
                Body text, unused by this fixture's own tests.
                """,
            in: root)
    }

    @Test func aDescriptionOverTwoHundredCharactersIsTruncatedInCommandListingButFullLengthInMetadata()
        throws
    {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeLongDescriptionSkill(in: root)

        let registry = SkillsRegistry(roots: [root])

        let metadataEntry = try #require(registry.metadata().first { $0.id == "long-description" })
        #expect(metadataEntry.description.count > 200)

        let listingEntry = try #require(registry.commandListing().first { $0.id == "long-description" })
        let listingDescription = try #require(listingEntry.description)
        #expect(listingDescription.count <= 201)
        #expect(listingDescription.hasSuffix("…"))
        #expect(metadataEntry.description.hasPrefix(listingDescription.dropLast()))
    }

    @Test func aDescriptionAtOrUnderTwoHundredCharactersIsUnchangedInCommandListing() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shortDescription = String(repeating: "a", count: 200)
        try Self.writeSkillFixture(
            id: "boundary-description",
            skillMarkdown: """
                ---
                name: boundary-description
                description: "\(shortDescription)"
                ---
                Body text, unused by this fixture's own tests.
                """,
            in: root)

        let registry = SkillsRegistry(roots: [root])

        let listingEntry = try #require(registry.commandListing().first { $0.id == "boundary-description" })
        #expect(listingEntry.description == shortDescription)
    }

    // MARK: - No directory-convention literal in registry source

    @Test func registrySourceNamesNoDotfolderConventionLiteral() throws {
        let sourceURL = FixtureLibrary.packageRoot()
            .appendingPathComponent("Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift")
        let text = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in [".skills", ".config", "~"] {
            #expect(!text.contains(forbidden), "SkillsRegistry.swift must not name \"\(forbidden)\"")
        }
    }
}
