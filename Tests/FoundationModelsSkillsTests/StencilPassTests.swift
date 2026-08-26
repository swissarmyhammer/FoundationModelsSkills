import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Tests for `StencilPass`, pass 3 of the §5 render pipeline (plan.md §5.3,
/// decision #29): the explicit-context/environment/well-known precedence
/// ladder, the root -> `Trust` mapping (default rule + override), `{%
/// include %}` partial resolution over host-supplied roots (with a
/// `$`-token inside the included partial staying literal, decision #16),
/// and the untrusted-rejection diagnostic (plan.md §13's named case) --
/// all through Extras' real `TemplateEngine`, never a mock.
struct StencilPassTests {
    // MARK: - Test helpers

    /// A dummy skill directory and project-root layer, reused by every test
    /// that does not care about the exact values.
    private static let defaultSkillDirectory = URL(
        fileURLWithPath: "/tmp/stencil-pass-tests/skill", isDirectory: true)
    private static let defaultWinningLayer = DotfolderStack.Layer(
        source: .project,
        root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/.skills", isDirectory: true))

    /// Deterministic well-known values so tests never depend on real process
    /// state (current directory, real date, real hostname) -- mirrors
    /// `TemplateEngineTests.fixtureWellKnownValues` in
    /// `FoundationModelsExtras`.
    private static let fixtureWellKnownValues = StencilPass.WellKnownValues(
        workingDirectory: "/fixture/cwd", date: "2020-01-01", hostname: "fixture-host")

    /// A minimal body using `{% ifnot %}` -- a real Stencil tag
    /// `TemplateEngine`'s own doc comment names among the tags
    /// `Trust.untrusted` rejects, and one not on
    /// `TemplateEngine.untrustedAllowedTags` -- so it renders under
    /// `.trusted` and is rejected under `.untrusted`, driving both halves of
    /// the trust-matrix tests below with one body.
    private static let nonWhitelistedTagBody = "{% ifnot flag %}no{% endif %}"

    /// Builds a `RenderRequest` with sensible fixed defaults -- callers
    /// override only the fields the test cares about. Mirrors
    /// `RenderPipelineTests`/`ArgumentSubstitutionTests`' own helper.
    private func request(
        text: String,
        arguments: [String] = [],
        argumentNames: [String] = [],
        winningLayer: DotfolderStack.Layer = StencilPassTests.defaultWinningLayer
    ) -> RenderRequest {
        RenderRequest(
            text: text,
            arguments: arguments,
            argumentNames: argumentNames,
            skillDirectory: Self.defaultSkillDirectory,
            winningLayer: winningLayer,
            policy: RenderPolicy())
    }

    /// Runs `pass.render` over `text`, wrapping/flattening `QuarantinedText` so every call site
    /// below can pass/receive plain `String`s.
    private func render(_ text: String, using pass: StencilPass, request: RenderRequest) throws -> String {
        try pass.render(QuarantinedText(original: text), request: request).flattened
    }

    /// Runs the REAL `ArgumentSubstitution` pass over `text` first, so the
    /// `QuarantinedText` handed to `pass.render` carries genuine
    /// `.quarantined` argument spans, then flattens `pass`'s output.
    private func renderAfterArgumentSubstitution(_ text: String, using pass: StencilPass, request: RenderRequest)
        throws -> String
    {
        let substituted = try ArgumentSubstitution().render(QuarantinedText(original: text), request: request)
        return try pass.render(substituted, request: request).flattened
    }

    // MARK: - Straddling blocks: one template per render, splices as opaque values (^q1mywft)

    /// The suffix pass 1 appends when a body omits `$ARGUMENTS` and one
    /// argument, `VAL`, is supplied -- every straddling expectation below
    /// carries it, since the whole substituted text renders as one template.
    private static let suppliedArgumentsSuffix = "\n\nARGUMENTS: VAL"

    @Test func stencilBlockStraddlingAnArgumentSpliceRendersAsOneTemplate() throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)
        let text = "{% if flag %}yes $0 end{% endif %}"

        let rendered = try renderAfterArgumentSubstitution(
            text, using: pass, request: request(text: text, arguments: ["VAL"], argumentNames: ["flag"]))

        #expect(rendered == "yes VAL end" + Self.suppliedArgumentsSuffix)
    }

    @Test(
        "a bare brace before a splice, and a closed variable before one, both stay intact",
        arguments: [
            (body: "{$0}", expected: "{VAL}"),
            (body: "see {$0} here", expected: "see {VAL} here"),
            (body: "{{ hostname }}$0", expected: "fixture-hostVAL"),
        ])
    func textAdjacentToASpliceRendersIntact(body: String, expected: String) throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)

        let rendered = try renderAfterArgumentSubstitution(
            body, using: pass, request: request(text: body, arguments: ["VAL"]))

        #expect(rendered == expected + Self.suppliedArgumentsSuffix)
    }

    @Test(
        "a splice inside a Stencil variable, tag, or comment is a rendering error",
        arguments: [
            "{{$0}}",
            "{{ $0 }}",
            "{{ \"$0\" }}",
            "{%$0%}",
            "{% if $0 %}yes{% else %}no{% endif %}",
            "{# $0 #}",
            "{{ hostname }} then {{ $0 }}",
            "{{{$0}}}",
        ])
    func spliceInsideADelimiterPairIsARenderingError(body: String) throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)

        #expect(throws: TemplateEngineError.self, "\(body)") {
            try renderAfterArgumentSubstitution(body, using: pass, request: request(text: body, arguments: ["VAL"]))
        }
    }

    @Test func splicedValueSpelledLikeTheQuarantineContextKeyStaysLiteral() throws {
        // A model-supplied value must never resolve as a template variable,
        // not even one spelled like the pass's own quarantine placeholder.
        // `$ARGUMENTS` splices the raw, as-typed text (a `$0` would
        // shell-tokenize the spaced value into three positions).
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)
        let text = "$ARGUMENTS and $ARGUMENTS"
        let argument = "{{ \(StencilPass.quarantinedSpanContextKeyPrefix)0 }}"

        let rendered = try renderAfterArgumentSubstitution(
            text, using: pass, request: request(text: text, arguments: [argument]))

        #expect(rendered == "\(argument) and \(argument)")
    }

    // MARK: - Ladder precedence

    @Test func explicitContextValueBeatsEnvironmentVariableBeatsWellKnownValueForTheSameKey() throws {
        // All three rungs define "hostname" so the assertion actually
        // exercises context beating environment (not just context beating
        // well-known, which a same-key env value could otherwise mask).
        let pass = StencilPass(
            environment: ["hostname": "from-env"],
            wellKnownValues: StencilPass.WellKnownValues(
                workingDirectory: "/fixture/cwd", date: "2020-01-01", hostname: "from-well-known"))

        let rendered = try render(
            "{{ hostname }}", using: pass,
            request: request(text: "{{ hostname }}", arguments: ["from-context"], argumentNames: ["hostname"]))

        #expect(rendered == "from-context")
    }

    @Test func environmentVariableBeatsWellKnownValueWhenNothingOverridesTheSameKey() throws {
        let pass = StencilPass(
            environment: ["hostname": "from-env"],
            wellKnownValues: StencilPass.WellKnownValues(
                workingDirectory: "/fixture/cwd", date: "2020-01-01", hostname: "from-well-known"))

        let rendered = try render("{{ hostname }}", using: pass, request: request(text: "{{ hostname }}"))

        #expect(rendered == "from-env")
    }

    @Test func wellKnownValuesArePresentWhenNothingOverridesThem() throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)
        let text = "{{ working_directory }}|{{ date }}|{{ hostname }}"

        let rendered = try render(text, using: pass, request: request(text: text))

        #expect(rendered == "/fixture/cwd|2020-01-01|fixture-host")
    }

    @Test func declaredArgumentNameWithNoSuppliedValueRendersEmptyRatherThanLeakingEnvironment() throws {
        // The skill declares an argument literally named "HOME" but the
        // caller supplies no arguments at all. `$name` (pass 1) would
        // substitute an empty string for this case
        // (`ArgumentSubstitution`'s own `.named` branch), so `{{ HOME }}`
        // (this pass) must agree -- never falling through to the real
        // environment value of the same key, which would otherwise leak a
        // host secret/path a skill author never intended to expose.
        let pass = StencilPass(
            environment: ["HOME": "/Users/leaked"], wellKnownValues: Self.fixtureWellKnownValues)

        let rendered = try render(
            "{{ HOME }}", using: pass, request: request(text: "{{ HOME }}", arguments: [], argumentNames: ["HOME"]))

        #expect(rendered == "")
    }

    @Test func duplicateArgumentNameResolvesToItsFirstOccurrencePositionMatchingPassOne() throws {
        // `ArgumentSubstitution`'s `.named` branch always resolves `$name`
        // via `argumentNames.firstIndex(of: name)` -- the *first*
        // occurrence's position, regardless of where else `name` recurs in
        // the declared list. `{{ name }}` (this pass) must resolve to the
        // same position for the two passes to actually "always agree", as
        // this file's own `namedArguments(for:)` doc comment claims.
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)

        let rendered = try render(
            "{{ duplicate }}", using: pass,
            request: request(
                text: "{{ duplicate }}", arguments: ["first", "second", "third"],
                argumentNames: ["duplicate", "other", "duplicate"]))

        #expect(rendered == "first")
    }

    @Test func environmentFlatKeyRendersAsAPlainVariable() throws {
        let pass = StencilPass(
            environment: ["HOME": "/Users/fixture"], wellKnownValues: Self.fixtureWellKnownValues)

        let rendered = try render("{{ HOME }}", using: pass, request: request(text: "{{ HOME }}"))

        #expect(rendered == "/Users/fixture")
    }

    // MARK: - Trust default rule

    @Test func defaultsRootRendersTrustedAllowingANonWhitelistedTag() throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)
        let defaultsLayer = DotfolderStack.Layer(
            source: .defaults,
            root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/defaults", isDirectory: true))

        let rendered = try render(
            Self.nonWhitelistedTagBody, using: pass,
            request: request(text: Self.nonWhitelistedTagBody, winningLayer: defaultsLayer))

        #expect(rendered == "no")
    }

    @Test func projectRootDrawsTheUntrustedRejectionDiagnosticForANonWhitelistedTag() throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)

        do {
            _ = try render(
                Self.nonWhitelistedTagBody, using: pass, request: request(text: Self.nonWhitelistedTagBody))
            Issue.record("expected TemplateEngineError to be thrown")
        } catch let error as TemplateEngineError {
            #expect("\(error)".contains("ifnot"))
        }
    }

    @Test func userRootAlsoDefaultsToUntrusted() throws {
        let pass = StencilPass(wellKnownValues: Self.fixtureWellKnownValues)
        let userLayer = DotfolderStack.Layer(
            source: .user, root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/user", isDirectory: true))

        do {
            _ = try render(
                Self.nonWhitelistedTagBody, using: pass,
                request: request(text: Self.nonWhitelistedTagBody, winningLayer: userLayer))
            Issue.record("expected TemplateEngineError to be thrown")
        } catch is TemplateEngineError {
            // Expected.
        }
    }

    // MARK: - Labeled roots (^1tb4h7f): `SkillsRegistry.init(layers:)` trust matrix

    /// Creates a fresh, empty throwaway directory under
    /// `FileManager.default.temporaryDirectory`.
    ///
    /// - Returns: The new directory's URL.
    /// - Throws: Whatever `FileManager.createDirectory` throws.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StencilPassTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes a minimal `id/SKILL.md` under `root`, with `body` as the raw,
    /// unrendered body text.
    ///
    /// - Parameters:
    ///   - id: The skill id -- both the subdirectory name and the
    ///     frontmatter's `name:` field.
    ///   - body: The raw body text to write, verbatim.
    ///   - root: The directory to write the skill's own subdirectory under.
    /// - Throws: Whatever `FileManager.createDirectory` or `String.write`
    ///   throws.
    private static func writeMinimalSkillFile(id: String, body: String, in root: URL) throws {
        let skillDirectory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "---\nname: \(id)\ndescription: fixture.\n---\n\(body)"
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    @Test func registryConstructedFromLabeledLayersRendersTheDefaultsRootTrustedAndOthersUntrusted() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsRoot = root.appendingPathComponent("defaults", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        try Self.writeMinimalSkillFile(id: "trusted-tag", body: Self.nonWhitelistedTagBody, in: defaultsRoot)
        try Self.writeMinimalSkillFile(id: "untrusted-tag", body: Self.nonWhitelistedTagBody, in: projectRoot)

        // The one sanctioned way to label a bare-`[URL]` root's trust
        // (^1tb4h7f): `SkillsRegistry.init(layers:)`, not an override table.
        let registry = SkillsRegistry(
            layers: [
                DotfolderStack.Layer(source: .defaults, root: defaultsRoot),
                DotfolderStack.Layer(source: .project, root: projectRoot),
            ])

        #expect(try registry.call(id: "trusted-tag") == "no")

        do {
            _ = try registry.call(id: "untrusted-tag")
            Issue.record("expected a TemplateEngineError for the untrusted layer")
        } catch is TemplateEngineError {
            // Expected.
        }
    }

    @Test func unlabeledRootsConvenienceKeepsEveryRootUntrusted() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMinimalSkillFile(id: "untrusted-tag", body: Self.nonWhitelistedTagBody, in: root)

        // `init(roots:)` (no labels) must keep today's all-untrusted
        // behavior, even for a root that would render trusted if labeled
        // `.defaults`.
        let registry = SkillsRegistry(roots: [root])

        do {
            _ = try registry.call(id: "untrusted-tag")
            Issue.record("expected a TemplateEngineError since init(roots:) labels no layer .defaults")
        } catch is TemplateEngineError {
            // Expected.
        }
    }

    // MARK: - `{{ dotfolder_name }}` derives from the highest-precedence project layer

    @Test func wellKnownValuesCurrentDerivesDotfolderNameFromTheHighestPrecedenceProjectLayer() {
        // A real-layer derivation test (^1tb4h7f): every other test in this
        // file injects `dotfolderName` directly via `WellKnownValues.init`.
        // `init(roots:)`'s unlabeled convenience tags every root `.project`,
        // so a naive "first matching layer" derivation would silently pick
        // the *lowest*-precedence root instead of the intended one.
        let lowPrecedence = DotfolderStack.Layer(
            source: .project,
            root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/.low-precedence", isDirectory: true))
        let highPrecedence = DotfolderStack.Layer(
            source: .project,
            root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/.high-precedence", isDirectory: true))

        let values = StencilPass.WellKnownValues.current(layers: [lowPrecedence, highPrecedence])

        #expect(values.dotfolderName == "high-precedence")
    }

    @Test func dotfolderNameRendersFromRealLayersEndToEndForALabeledRegistry() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lowPrecedenceRoot = root.appendingPathComponent(".low-precedence", isDirectory: true)
        let highPrecedenceRoot = root.appendingPathComponent(".high-precedence", isDirectory: true)
        try Self.writeMinimalSkillFile(id: "dotfolder-probe", body: "{{ dotfolder_name }}", in: highPrecedenceRoot)

        let registry = SkillsRegistry(
            layers: [
                DotfolderStack.Layer(source: .project, root: lowPrecedenceRoot),
                DotfolderStack.Layer(source: .project, root: highPrecedenceRoot),
            ])

        #expect(try registry.call(id: "dotfolder-probe") == "high-precedence")
    }

    @Test func dotfolderNameRendersFromTheStackConstructorEndToEnd() throws {
        // `SkillsRegistry.init(stack:)` takes its layers from a real
        // `DotfolderStack`, whose `.project` layer is `<workingDirectory>/.<name>`
        // -- so `{{ dotfolder_name }}` must render as that stack's own name.
        let workingDirectory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let userDirectory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: userDirectory) }
        let stackName = "probe-stack"
        try Self.writeMinimalSkillFile(
            id: "dotfolder-probe", body: "{{ dotfolder_name }}",
            in: workingDirectory.appendingPathComponent(".\(stackName)", isDirectory: true))

        // An empty environment keeps `<NAME>_DEFAULTS_DIR`/`XDG_CONFIG_HOME`
        // from repointing the stack's layers at real host directories.
        let stack = DotfolderStack(
            name: stackName, workingDirectory: workingDirectory, userDirectory: userDirectory, environment: [:])
        let registry = SkillsRegistry(stack: stack)

        #expect(try registry.call(id: "dotfolder-probe") == stackName)
    }

    // MARK: - Partial include, over host-supplied roots, nearest wins

    @Test func includeResolvesFromTheNearestWinningRootAndALiteralDollarTokenInsideStaysLiteral() throws {
        let fixture = try TempStackFixture()
        defer { fixture.cleanUp() }
        fixture.writePartial("from defaults", named: "header.md", in: fixture.defaultsRoot)
        fixture.writePartial("from user: $0", named: "header.md", in: fixture.userRoot)

        let pass = StencilPass(layers: fixture.layers, wellKnownValues: Self.fixtureWellKnownValues)
        let text = "{% include \"header\" %}"

        let rendered = try render(
            text, using: pass,
            request: request(
                text: text, winningLayer: DotfolderStack.Layer(source: .project, root: fixture.projectRoot)))

        // Pass 1 (argument substitution) already ran, on the parent skill's
        // body, before this pass ever loaded the partial (decision #16) --
        // so the "$0" written into the partial file itself is never
        // substituted, even though "$0" is otherwise a recognized pass-1
        // token.
        #expect(rendered == "from user: $0")
    }

    @Test func laterRootShadowsAnEarlierRootsPartialOfTheSameName() throws {
        let fixture = try TempStackFixture()
        defer { fixture.cleanUp() }
        fixture.writePartial("from defaults", named: "header.md", in: fixture.defaultsRoot)
        fixture.writePartial("from user", named: "header.md", in: fixture.userRoot)
        fixture.writePartial("from project", named: "header.md", in: fixture.projectRoot)

        let pass = StencilPass(layers: fixture.layers, wellKnownValues: Self.fixtureWellKnownValues)
        let text = "{% include \"header\" %}"

        let rendered = try render(
            text, using: pass,
            request: request(
                text: text, winningLayer: DotfolderStack.Layer(source: .project, root: fixture.projectRoot)))

        #expect(rendered == "from project")
    }

    // MARK: - Golden env-report render over the real fixture library

    @Test func envReportFixtureRendersHomeAndWorkingDirectoryThroughTheLadderAndIncludesTheHeaderPartial() throws {
        let defaultsRoot = FixtureLibrary.url(relativePath: "defaults")
        let userRoot = FixtureLibrary.url(relativePath: "user")
        let projectSkillsRoot = FixtureLibrary.url(relativePath: "project/.skills")
        let layers = [
            DotfolderStack.Layer(source: .defaults, root: defaultsRoot),
            DotfolderStack.Layer(source: .user, root: userRoot),
            DotfolderStack.Layer(source: .project, root: projectSkillsRoot),
        ]
        let pass = StencilPass(
            layers: layers,
            environment: ["HOME": "/fixture/home"],
            wellKnownValues: StencilPass.WellKnownValues(
                workingDirectory: "/fixture/cwd", date: "2020-01-01", hostname: "fixture-host",
                dotfolderName: "fixture-dotfolder"))

        let skillURL = FixtureLibrary.url(relativePath: "project/.skills/env-report/SKILL.md")
        let text = try String(contentsOf: skillURL, encoding: .utf8)
        guard case .decoded(let skill) = FrontmatterDecoder.decode(text: text) else {
            Issue.record("expected the env-report fixture to decode cleanly")
            return
        }

        let rendered = try render(
            skill.body, using: pass,
            request: request(
                text: skill.body, winningLayer: DotfolderStack.Layer(source: .project, root: projectSkillsRoot)))

        #expect(rendered.contains("HOME=/fixture/home"))
        #expect(rendered.contains("WORKING_DIRECTORY=/fixture/cwd"))
        #expect(rendered.contains("fixture-dotfolder Shared Header"))
        #expect(rendered.contains("Literal token follows: $0"))
    }

    // MARK: - Temp-directory fixture for the include tests

    /// A throwaway three-layer directory tree, each layer able to hold its
    /// own `_partials/header.md`, cleaned up via `cleanUp()` when the test
    /// ends. Mirrors `FoundationModelsExtras`' own
    /// `DotfolderLoaderTests.Fixture`.
    private struct TempStackFixture {
        /// This fixture's own throwaway root, removed wholesale by `cleanUp()`.
        let root: URL
        /// The `.defaults`-sourced layer root.
        let defaultsRoot: URL
        /// The `.user`-sourced layer root.
        let userRoot: URL
        /// The `.project`-sourced layer root.
        let projectRoot: URL

        /// `layers`, ready to hand to `StencilPass.init(layers:)`, ordered
        /// lowest precedence first (defaults < user < project).
        var layers: [DotfolderStack.Layer] {
            [
                DotfolderStack.Layer(source: .defaults, root: defaultsRoot),
                DotfolderStack.Layer(source: .user, root: userRoot),
                DotfolderStack.Layer(source: .project, root: projectRoot),
            ]
        }

        /// Creates a fresh, empty three-layer directory tree.
        ///
        /// - Throws: Whatever `FileManager.createDirectory` throws.
        init() throws {
            root = try StencilPassTests.makeTempDirectory()
            defaultsRoot = root.appendingPathComponent("defaults", isDirectory: true)
            userRoot = root.appendingPathComponent("user", isDirectory: true)
            projectRoot = root.appendingPathComponent("project", isDirectory: true)
            for directory in [defaultsRoot, userRoot, projectRoot] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        /// Writes `contents` to `_partials/<name>` under `directory`.
        ///
        /// - Parameters:
        ///   - contents: The partial file's text.
        ///   - name: The partial's file name, e.g. `"header.md"`.
        ///   - directory: The layer root to write under.
        func writePartial(_ contents: String, named name: String, in directory: URL) {
            let fileURL = directory.appendingPathComponent("_partials").appendingPathComponent(name)
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        /// Removes this fixture's entire throwaway directory tree.
        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
