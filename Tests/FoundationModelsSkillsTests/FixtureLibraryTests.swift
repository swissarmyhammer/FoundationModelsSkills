import Foundation
import FoundationModelsSkills
import Testing

/// Decodes the fixture at `relativePath` via the production
/// `FrontmatterDecoder`, unwrapping the `.decoded` case -- every fixture
/// exercised below is expected to decode cleanly. (The `broken/` fixtures'
/// lenient-validation behavior -- retry success/failure, skip diagnostics --
/// is covered by `FrontmatterDecoderTests`, not here; this file only proves
/// the fixture library resolves the right files and that a few representative
/// happy-path fixtures carry the fields their names promise.)
private func loadDecodedSkill(_ relativePath: String) throws -> DecodedSkill {
    let text = try String(contentsOf: FixtureLibrary.url(relativePath: relativePath), encoding: .utf8)
    guard case .decoded(let skill) = FrontmatterDecoder.decode(text: text) else {
        Issue.record("expected \(relativePath) to decode cleanly")
        throw LoadFixtureFailure.notDecoded
    }
    return skill
}

private enum LoadFixtureFailure: Error {
    case notDecoded
}

/// Reads and decodes the frontmatter block of the fixture at `relativePath`.
private func loadFrontmatter(_ relativePath: String) throws -> SkillFrontmatter {
    try loadDecodedSkill(relativePath).frontmatter
}

/// Reads the render-pipeline body (post frontmatter split) of the fixture at
/// `relativePath`.
private func loadBody(_ relativePath: String) throws -> String {
    try loadDecodedSkill(relativePath).body
}

/// The three-layer stack's happy-path fixtures (plan.md §11): every §5/§6
/// feature in this slice, one fixture each.
private let happyPathFixtures = [
    "defaults/base-style/SKILL.md",
    "user/base-style/SKILL.md",
    "user/_partials/header.md",
    "project/.skills/commit/SKILL.md",
    "project/.skills/deploy/SKILL.md",
    "project/.skills/env-report/SKILL.md",
    "project/.skills/lint/SKILL.md",
    "project/.skills/spec-clean/SKILL.md",
]

/// The lenient-validation `broken/` fixtures -- kept out of the three-layer
/// stack so the happy-path tests above stay clean (plan.md §11 task note).
private let brokenFixtures = [
    "broken/bad-colon-description/SKILL.md",
    "broken/missing-description/SKILL.md",
    "broken/name-mismatch/SKILL.md",
    "broken/partial-flag/SKILL.md",
]

@Test func fixtureLibraryResolvesUnderTheRepoRootAtExamplesSkillLibrary() {
    let root = FixtureLibrary.root()
    #expect(root.path.hasSuffix("Examples/skill-library"))
}

@Test func fixtureLibraryResolutionIsAPureFunctionOfTheCallingFileNotTheEnvironment() {
    // Hermetic per plan.md §11: resolution walks up from the injectable
    // `thisFile` (defaulting to the call site's `#filePath`), never from
    // `FileManager.default.homeDirectoryForCurrentUser`, `$HOME`, or
    // `$XDG_CONFIG_HOME` -- so it can never land on the real dotfolder
    // convention (`~/.skills`, `~/.config/skills/`) regardless of the
    // environment the test suite runs in. Proven directly: an unrelated,
    // non-existent `thisFile` still resolves deterministically, with no
    // dependence on any environment variable or real filesystem state.
    let fakeCallSite = "/nonexistent/example-checkout/Tests/FoundationModelsSkillsTests/Fake.swift"
    let root = FixtureLibrary.root(thisFile: fakeCallSite)
    #expect(root.path == "/nonexistent/example-checkout/Examples/skill-library")
}

@Test(arguments: happyPathFixtures)
func fixtureLibraryResolvesHappyPathFixture(_ relativePath: String) {
    #expect(FileManager.default.fileExists(atPath: FixtureLibrary.url(relativePath: relativePath).path))
}

@Test(arguments: brokenFixtures)
func fixtureLibraryResolvesBrokenFixture(_ relativePath: String) {
    #expect(FileManager.default.fileExists(atPath: FixtureLibrary.url(relativePath: relativePath).path))
}

@Test func defaultsBaseStyleIsAPlainValidSkill() throws {
    let frontmatter = try loadFrontmatter("defaults/base-style/SKILL.md")
    #expect(frontmatter.name == "base-style")
    #expect(frontmatter.description?.isEmpty == false)
}

@Test func userBaseStyleFullyReplacesTheDefaultsCopy() throws {
    let frontmatter = try loadFrontmatter("user/base-style/SKILL.md")
    #expect(frontmatter.name == "base-style")
    #expect(frontmatter.description?.isEmpty == false)

    // Same id (directory name), different content -- the full-replace
    // override this fixture pair demonstrates (decision #3).
    let userBody = try loadBody("user/base-style/SKILL.md")
    let defaultsBody = try loadBody("defaults/base-style/SKILL.md")
    #expect(userBody != defaultsBody)
}

@Test func commitHasArgumentsHintAndPositionalTokensInBody() throws {
    let frontmatter = try loadFrontmatter("project/.skills/commit/SKILL.md")
    #expect(frontmatter.name == "commit")
    #expect(frontmatter.arguments == ["message"])
    #expect(frontmatter.argumentHint == "<message>")

    let body = try loadBody("project/.skills/commit/SKILL.md")
    #expect(body.contains("$0"))
    #expect(body.contains("$ARGUMENTS"))
}

@Test func deployDisablesModelInvocation() throws {
    let frontmatter = try loadFrontmatter("project/.skills/deploy/SKILL.md")
    #expect(frontmatter.name == "deploy")
    #expect(frontmatter.disableModelInvocation == true)
}

@Test func lintIsNotUserInvocable() throws {
    let frontmatter = try loadFrontmatter("project/.skills/lint/SKILL.md")
    #expect(frontmatter.name == "lint")
    #expect(frontmatter.userInvocable == false)
}

@Test func specCleanCarriesPureSpecFieldsWithExtensionsUnderMetadata() throws {
    let frontmatter = try loadFrontmatter("project/.skills/spec-clean/SKILL.md")
    #expect(frontmatter.name == "spec-clean")
    #expect(frontmatter.license != nil)
    #expect(frontmatter.compatibility != nil)
    #expect(frontmatter.metadata.isEmpty == false)

    // Pure-spec at the top level (decision #27): this fixture's own
    // extension fields live only under `metadata.*` -- `disable-model-invocation`
    // and `preload` -- and still resolve onto `SkillFrontmatter`'s canonical
    // properties via the metadata fallback (no top-level value to conflict
    // with, so no note is recorded either).
    #expect(frontmatter.disableModelInvocation == false)
    #expect(frontmatter.preload == false)
    #expect(frontmatter.notes.isEmpty)

    // Extension fields this fixture's metadata never sets stay absent.
    #expect(frontmatter.arguments.isEmpty)
    #expect(frontmatter.argumentHint == nil)
    #expect(frontmatter.userInvocable == nil)
}
