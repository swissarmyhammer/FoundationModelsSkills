import Foundation
import FoundationModelsExtras
import Testing

// The internal initializer of `StencilPass` takes the factory that makes the
// stenciled stack of one render, and `pinnedPass` gives a factory that pins
// the well-known values of each render.
@testable import FoundationModelsSkills

/// Tests for `StencilPass`, pass 3 of the render pipeline, as this
/// package wires it: the variables of one render
/// (the environment values, and the named arguments of the skill above
/// them), the well-known values that the stenciled stack of Extras adds
/// below them, and the layer that the stack takes the trust from.
///
/// The Stencil work itself belongs to `StenciledDotfolderStack` of
/// `FoundationModelsExtras`, and the tests of that type prove the trust
/// rule, the partial scope rule, the bridge from a quarantined span to one
/// template and the limits of one render. Each case below runs through the
/// real stack, never a mock.
struct StencilPassTests {
    // MARK: - Test helpers

    /// A dummy skill directory and project-root layer, reused by every test
    /// that does not care about the exact values.
    private static let defaultSkillDirectory = URL(
        fileURLWithPath: "/tmp/stencil-pass-tests/skill", isDirectory: true)
    private static let defaultWinningLayer = DotfolderStack.Layer(
        source: .project,
        root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/.skills", isDirectory: true))

    /// A pass over `layers` whose every render reads the same well-known
    /// values, thus `{{ date }}` and `{{ hostname }}` never depend on the
    /// clock or on the machine.
    ///
    /// The internal initializer of `StencilPass` takes the factory that
    /// makes the stenciled stack of one render, and this helper gives a
    /// factory that pins `wellKnownValues`.
    ///
    /// - Parameters:
    ///   - layers: The layer roots to resolve an `{% include %}` against.
    ///     Defaults to empty.
    ///   - environment: The environment values of the ladder. Defaults to
    ///     empty.
    ///   - hostname: The value of `{{ hostname }}`. Defaults to the fixture
    ///     hostname.
    ///   - dotfolderName: The value of `{{ dotfolder_name }}`, or `nil` for
    ///     no such value. Defaults to `nil`.
    /// - Returns: The pass.
    private static func pinnedPass(
        layers: [DotfolderStack.Layer] = [],
        environment: [String: String] = [:],
        hostname: String = fixtureHostname,
        dotfolderName: String? = nil
    ) -> StencilPass {
        let wellKnownValues = WellKnownValues(
            workingDirectory: fixtureWorkingDirectory, date: fixtureDate, hostname: hostname,
            dotfolderName: dotfolderName)
        return StencilPass(layers: layers, environment: environment) { base, variables in
            StenciledDotfolderStack(base: base, variables: variables, wellKnownValues: wellKnownValues)
        }
    }

    /// The pinned working directory of every render below.
    private static let fixtureWorkingDirectory = "/fixture/cwd"

    /// The pinned date of every render below.
    private static let fixtureDate = "2020-01-01"

    /// The pinned hostname of every render below.
    private static let fixtureHostname = "fixture-host"

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

    // MARK: - Ladder precedence

    @Test func explicitContextValueBeatsEnvironmentVariableBeatsWellKnownValueForTheSameKey() throws {
        // All three rungs define "hostname" so the assertion actually
        // exercises context beating environment (not just context beating
        // well-known, which a same-key env value could otherwise mask).
        let pass = Self.pinnedPass(environment: ["hostname": "from-env"], hostname: "from-well-known")

        let rendered = try render(
            "{{ hostname }}", using: pass,
            request: request(text: "{{ hostname }}", arguments: ["from-context"], argumentNames: ["hostname"]))

        #expect(rendered == "from-context")
    }

    @Test func environmentVariableBeatsWellKnownValueWhenNothingOverridesTheSameKey() throws {
        let pass = Self.pinnedPass(environment: ["hostname": "from-env"], hostname: "from-well-known")

        let rendered = try render("{{ hostname }}", using: pass, request: request(text: "{{ hostname }}"))

        #expect(rendered == "from-env")
    }

    @Test func wellKnownValuesArePresentWhenNothingOverridesThem() throws {
        let pass = Self.pinnedPass()
        let text = "{{ working_directory }}|{{ date }}|{{ hostname }}"

        let rendered = try render(text, using: pass, request: request(text: text))

        #expect(
            rendered == "\(Self.fixtureWorkingDirectory)|\(Self.fixtureDate)|\(Self.fixtureHostname)")
    }

    @Test func declaredArgumentNameWithNoSuppliedValueRendersEmptyRatherThanLeakingEnvironment() throws {
        // The skill declares an argument literally named "HOME" but the
        // caller supplies no arguments at all. `$name` (pass 1) would
        // substitute an empty string for this case
        // (`ArgumentSubstitution`'s own `.named` branch), so `{{ HOME }}`
        // (this pass) must agree -- never falling through to the real
        // environment value of the same key, which would otherwise leak a
        // host secret/path a skill author never intended to expose.
        let pass = Self.pinnedPass(environment: ["HOME": "/Users/leaked"])

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
        let pass = Self.pinnedPass()

        let rendered = try render(
            "{{ duplicate }}", using: pass,
            request: request(
                text: "{{ duplicate }}", arguments: ["first", "second", "third"],
                argumentNames: ["duplicate", "other", "duplicate"]))

        #expect(rendered == "first")
    }

    @Test func environmentFlatKeyRendersAsAPlainVariable() throws {
        let pass = Self.pinnedPass(environment: ["HOME": "/Users/fixture"])

        let rendered = try render("{{ HOME }}", using: pass, request: request(text: "{{ HOME }}"))

        #expect(rendered == "/Users/fixture")
    }

    // MARK: - Marketplace layers render untrusted

    /// A body made of one bare `{% now %}` -- a real Stencil tag that an
    /// untrusted render does not allow. So it renders the current date under
    /// a `.defaults` layer and draws the untrusted rejection under each
    /// other layer.
    private static let nowTagBody = "{% now %}"

    /// The error text a render gives when an untrusted render rejects the
    /// tag of `nowTagBody`.
    private static let nowTagUntrustedRejection = "untrusted rendering does not allow the 'now' tag"

    @Test func marketplaceLayerDrawsTheUntrustedRejectionForTheNowTag() throws {
        let pass = Self.pinnedPass()
        let marketplaceLayer = DotfolderStack.Layer(
            source: .marketplace,
            root: URL(fileURLWithPath: "/tmp/stencil-pass-tests/marketplace", isDirectory: true))

        let error = try #require(throws: TemplateEngineError.self) {
            try render(
                Self.nowTagBody, using: pass, request: request(text: Self.nowTagBody, winningLayer: marketplaceLayer))
        }

        #expect(
            error.description.contains(Self.nowTagUntrustedRejection),
            "a .marketplace layer must render untrusted, so the 'now' tag must be rejected")
    }

    // MARK: - Labeled roots: `SkillsRegistry.init(layers:)` trust matrix

    /// A minimal body using `{% ifnot %}` -- a real Stencil tag that an
    /// untrusted render does not allow -- so it renders under a `.defaults`
    /// layer and is rejected under each other layer, which drives both
    /// halves of the registry trust matrix below with one body.
    private static let nonWhitelistedTagBody = "{% ifnot flag %}no{% endif %}"

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

    @Test func registryConstructedFromLabeledLayersRendersTheDefaultsRootTrustedAndOthersUntrusted() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsRoot = root.appendingPathComponent("defaults", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        try Self.writeMinimalSkillFile(id: "trusted-tag", body: Self.nonWhitelistedTagBody, in: defaultsRoot)
        try Self.writeMinimalSkillFile(id: "untrusted-tag", body: Self.nonWhitelistedTagBody, in: projectRoot)

        // The one sanctioned way to label a bare-`[URL]` root's trust
        //: `SkillsRegistry.init(layers:)`, not an override table.
        let registry = SkillsRegistry(
            layers: [
                DotfolderStack.Layer(source: .defaults, root: defaultsRoot),
                DotfolderStack.Layer(source: .project, root: projectRoot),
            ])

        #expect(try await registry.call(id: "trusted-tag") == "no")

        do {
            _ = try await registry.call(id: "untrusted-tag")
            Issue.record("expected a render error for the untrusted layer")
        } catch is TemplateEngineError {
            // Expected.
        }
    }

    @Test func unlabeledRootsConvenienceKeepsEveryRootUntrusted() async throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMinimalSkillFile(id: "untrusted-tag", body: Self.nonWhitelistedTagBody, in: root)

        // `init(roots:)` (no labels) must keep today's all-untrusted
        // behavior, even for a root that would render trusted if labeled
        // `.defaults`.
        let registry = SkillsRegistry(roots: [root])

        do {
            _ = try await registry.call(id: "untrusted-tag")
            Issue.record("expected a render error since init(roots:) labels no layer .defaults")
        } catch is TemplateEngineError {
            // Expected.
        }
    }

    // MARK: - `{{ dotfolder_name }}` derives from the highest-precedence project layer

    @Test func dotfolderNameRendersFromRealLayersEndToEndForALabeledRegistry() async throws {
        // `init(roots:)`'s unlabeled convenience tags every root `.project`,
        // so a naive "first matching layer" derivation would silently pick
        // the *lowest*-precedence root instead of the intended one.
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

        #expect(try await registry.call(id: "dotfolder-probe") == "high-precedence")
    }

    @Test func dotfolderNameRendersFromTheStackConstructorEndToEnd() async throws {
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

        #expect(try await registry.call(id: "dotfolder-probe") == stackName)
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
        let pass = Self.pinnedPass(
            layers: layers, environment: ["HOME": "/fixture/home"], dotfolderName: "fixture-dotfolder")

        let skillURL = FixtureLibrary.url(relativePath: "project/.skills/env-report/SKILL.md")
        let text = try String(contentsOf: skillURL, encoding: .utf8)
        let skill = try #require(
            FixtureLibrary.decodedSkill(text: text), "the env-report fixture must decode cleanly")

        let rendered = try render(
            skill.body, using: pass,
            request: request(
                text: skill.body, winningLayer: DotfolderStack.Layer(source: .project, root: projectSkillsRoot)))

        #expect(rendered.contains("HOME=/fixture/home"))
        #expect(rendered.contains("WORKING_DIRECTORY=\(Self.fixtureWorkingDirectory)"))
        #expect(rendered.contains("fixture-dotfolder Shared Header"))
        #expect(rendered.contains("Literal token follows: $0"))
    }
}
