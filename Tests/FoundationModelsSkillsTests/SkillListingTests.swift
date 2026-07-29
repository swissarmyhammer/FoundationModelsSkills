import Foundation
import FoundationModelsSkills
import Testing

/// Listing snapshot tests over the §11 fixture stack (plan.md §6.1): each
/// fixture's `SKILL.md` is decoded via `FrontmatterDecoder` and wrapped in a
/// `SkillListing`, asserting every field -- including `license`/
/// `compatibility` (only `spec-clean` sets them) and the parsed
/// `parameters`/`acceptsTrailingArguments` derived by `ParameterInference`.
struct SkillListingTests {
    /// Decodes the named fixture's `SKILL.md` and builds its `SkillListing`,
    /// using the fixture's own directory name as `id` (mirrors plan.md §4:
    /// the directory name is the canonical id).
    private func listing(
        id: String, relativePath: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> SkillListing {
        let text = try String(contentsOf: FixtureLibrary.url(relativePath: relativePath), encoding: .utf8)
        let outcome = FrontmatterDecoder.decode(text: text)
        guard case .decoded(let skill) = outcome else {
            Issue.record("expected .decoded, got \(outcome)", sourceLocation: sourceLocation)
            throw ListingExpectationFailure.notDecoded
        }
        return SkillListing(id: id, decodedSkill: skill)
    }

    private enum ListingExpectationFailure: Error {
        case notDecoded
    }

    // MARK: - commit: arguments: + argument-hint: + $0/$ARGUMENTS body

    @Test func commitFixtureYieldsNamedParameterWithHintPlaceholderAndTrailingArguments() throws {
        let listing = try listing(id: "commit", relativePath: "project/.skills/commit/SKILL.md")

        #expect(listing.id == "commit")
        #expect(listing.displayName == "commit")
        #expect(
            listing.description
                == "Create a git commit for the currently staged changes using the given message.")
        #expect(listing.license == nil)
        #expect(listing.compatibility == nil)
        #expect(
            listing.parameters == [
                SkillParameter(
                    name: "message", position: 0, required: true, variadic: false, placeholder: "<message>")
            ])
        #expect(listing.acceptsTrailingArguments == true)
    }

    // MARK: - deploy: disable-model-invocation:, no arguments/hint/body refs

    @Test func deployFixtureHasNoParametersAndNoTrailingArguments() throws {
        let listing = try listing(id: "deploy", relativePath: "project/.skills/deploy/SKILL.md")

        #expect(listing.id == "deploy")
        #expect(listing.displayName == "deploy")
        #expect(listing.description == "Deploy the current build to the target environment.")
        #expect(listing.parameters.isEmpty)
        #expect(listing.acceptsTrailingArguments == false)
    }

    // MARK: - lint: user-invocable: false, no arguments/hint/body refs

    @Test func lintFixtureHasNoParametersAndNoTrailingArguments() throws {
        let listing = try listing(id: "lint", relativePath: "project/.skills/lint/SKILL.md")

        #expect(listing.id == "lint")
        #expect(listing.displayName == "lint")
        #expect(listing.description == "Run the project's linter and report findings.")
        #expect(listing.parameters.isEmpty)
        #expect(listing.acceptsTrailingArguments == false)
    }

    // MARK: - spec-clean: license + compatibility, pure-spec frontmatter

    @Test func specCleanFixtureCarriesLicenseAndCompatibility() throws {
        let listing = try listing(id: "spec-clean", relativePath: "project/.skills/spec-clean/SKILL.md")

        #expect(listing.id == "spec-clean")
        #expect(listing.displayName == "spec-clean")
        #expect(listing.license == "MIT")
        #expect(listing.compatibility == "Requires a POSIX shell and git 2.30 or later.")
        #expect(listing.parameters.isEmpty)
        #expect(listing.acceptsTrailingArguments == false)
    }

    // MARK: - displayName is optional -- a Claude-style input without `name:`

    @Test func displayNameIsNilWhenFrontmatterOmitsName() {
        let frontmatter = SkillFrontmatter(description: "No name field at all.")
        let listing = SkillListing(id: "no-name", frontmatter: frontmatter, body: "")
        #expect(listing.displayName == nil)
        #expect(listing.id == "no-name")
    }
}
