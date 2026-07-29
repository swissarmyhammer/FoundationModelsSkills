import Foundation
import FoundationModelsExtras
import Testing
import Yams

/// Coding-key-mapped view over the frontmatter fields this slice's fixtures
/// exercise (plan.md §4-§6, §11): the agentskills.io-spec fields (`name`,
/// `description`, `license`, `compatibility`) plus this package's
/// Claude-compatible extensions (`arguments`, `argument-hint`,
/// `disable-model-invocation`, `user-invocable`, `metadata`).
///
/// Test-local -- the real decode type lands with `SkillsRegistry` in a later
/// task.
private struct SkillFrontmatter: Decodable {
    let name: String?
    let description: String?
    let arguments: [String]?
    let argumentHint: String?
    let disableModelInvocation: Bool?
    let userInvocable: Bool?
    let license: String?
    let compatibility: String?
    let metadata: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case name, description, arguments, license, compatibility, metadata
        case argumentHint = "argument-hint"
        case disableModelInvocation = "disable-model-invocation"
        case userInvocable = "user-invocable"
    }
}

/// Reads and Yams-decodes the frontmatter block of the fixture at
/// `relativePath`, using `FrontmatterDocument.split` for the textual split
/// (plan.md §4/§29: YAML decoding stays ours, Extras only splits text).
private func loadFrontmatter(_ relativePath: String) throws -> SkillFrontmatter {
    let text = try String(contentsOf: FixtureLibrary.url(relativePath: relativePath), encoding: .utf8)
    let frontmatterText = try #require(FrontmatterDocument.split(text: text).frontmatter)
    return try YAMLDecoder().decode(SkillFrontmatter.self, from: frontmatterText)
}

/// Reads the render-pipeline body (post frontmatter split) of the fixture at
/// `relativePath`.
private func loadBody(_ relativePath: String) throws -> String {
    let text = try String(contentsOf: FixtureLibrary.url(relativePath: relativePath), encoding: .utf8)
    return FrontmatterDocument.split(text: text).body
}

/// The three-layer stack's happy-path fixtures (plan.md §11): every §5/§6
/// feature in this slice, one fixture each.
private let happyPathFixtures = [
    "defaults/base-style/SKILL.md",
    "user/base-style/SKILL.md",
    "user/_partials/header.md",
    "project/.skills/commit/SKILL.md",
    "project/.skills/deploy/SKILL.md",
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
    #expect(frontmatter.metadata?.isEmpty == false)

    // Pure-spec at the top level (decision #27): none of our extension
    // fields appear there directly -- they ride under `metadata.*` instead.
    #expect(frontmatter.arguments == nil)
    #expect(frontmatter.argumentHint == nil)
    #expect(frontmatter.disableModelInvocation == nil)
    #expect(frontmatter.userInvocable == nil)
}
