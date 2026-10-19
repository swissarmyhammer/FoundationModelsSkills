import Foundation
@testable import FoundationModelsSkills
import Testing

/// Tests for the corrective `ResourceIDLookup` draws when the calling
/// context's catalog holds no usable skill at all. `ResourceOpsTests` and
/// `RunScriptTests` always hold at least one usable skill, so they reach
/// only the "Closest usable ids: ..." branch of that message.
///
/// The tests of `ResourceIDLookup.withResolvedPath(_:id:context:whenResolved:)`
/// are here too: that lookup gives the relative path of a path that the
/// model gives, or the denied corrective.
struct ResourceIDLookupTests {
    /// The skill id every empty-catalog test asks for. No catalog holds it.
    private static let missingID = "missing"

    /// The resource path the `ReadResource` test names. It is never read,
    /// because the id fails to resolve first.
    private static let samplePath = "SKILL.md"

    /// The text the other branch of the corrective carries, and this branch
    /// must not.
    private static let usableIDsPrefix = "Closest usable ids:"

    /// Thrown by `correctiveMessage(fromEmptyCatalog:)` when the operation
    /// succeeded against an empty catalog, which no test here expects.
    private struct UnexpectedSuccess: Error {}

    /// The corrective `ResourceIDLookup` draws for `id` when no skill passes
    /// the context's visibility predicate.
    ///
    /// - Parameter id: The id that could not be resolved.
    /// - Returns: The message, in the lookup's own wording.
    private static func emptyCatalogMessage(id: String) -> String {
        "The skill id `\(id)` is not currently usable, and no skills are currently usable."
    }

    /// Runs `operate` against a context whose registry holds no skill, and
    /// returns the corrective message the operation drew.
    ///
    /// The registry is built over a fresh, empty temp root, so the catalog
    /// holds nothing for any visibility predicate to accept.
    ///
    /// - Parameter operate: Runs one resource operation in the empty-catalog
    ///   context.
    /// - Returns: The corrective message.
    /// - Throws: `UnexpectedSuccess` when the operation succeeded; otherwise
    ///   whatever the temp-root creation or `operate` throws.
    private static func correctiveMessage<Success>(
        fromEmptyCatalog operate: (SkillsToolContext) async throws -> CorrectiveOutcome<Success>
    ) async throws -> String {
        let root = try HotReloadTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = ResourceTestSupport.makeContext(roots: [root])
        guard case .corrective(let message) = try await operate(context) else {
            throw UnexpectedSuccess()
        }
        return message
    }

    @Test func listResourceOnAnEmptyCatalogDrawsTheNoUsableSkillsCorrective() async throws {
        let message = try await Self.correctiveMessage { context in
            try await ListResource(id: Self.missingID).execute(in: context)
        }

        #expect(message == Self.emptyCatalogMessage(id: Self.missingID))
        #expect(!message.contains(Self.usableIDsPrefix))
    }

    @Test func readResourceOnAnEmptyCatalogDrawsTheSameNoUsableSkillsCorrective() async throws {
        // `ReadResource` shares the lookup with `ListResource`, so the
        // message must be the same one, word for word.
        let message = try await Self.correctiveMessage { context in
            try await ReadResource(id: Self.missingID, path: Self.samplePath).execute(in: context)
        }

        #expect(message == Self.emptyCatalogMessage(id: Self.missingID))
        #expect(!message.contains(Self.usableIDsPrefix))
    }

    // MARK: - The relative path of a path that the model gives

    /// The id of the fixture skill that the path tests use.
    private static let fixtureSkillID = "release-notes"

    /// The path of a file of the fixture skill, relative to the skill
    /// directory.
    private static let fixtureFilePath = "references/changelog.md"

    /// Runs `ResourceIDLookup.withResolvedPath(_:id:context:whenResolved:)`
    /// for `path` of the fixture skill. The closure gives the relative path
    /// that it got as its success value.
    ///
    /// - Parameter path: The path that the model gives.
    /// - Returns: The relative path that the closure got, or the corrective
    ///   message of the lookup.
    private static func resolvedPath(of path: String) async -> CorrectiveOutcome<String> {
        let context = ResourceTestSupport.makeContext(roots: [ResourceTestSupport.projectSkillsRoot])
        return await ResourceIDLookup.withResolvedPath(path, id: Self.fixtureSkillID, context: context) {
            relativePath, _ in
            .success(relativePath)
        }
    }

    @Test func anAbsolutePathInTheSkillReachesTheClosureAsItsRelativePath() async {
        let absolutePath = ResourceTestSupport.absoluteSkillFilePath(
            root: ResourceTestSupport.projectSkillsRoot, id: Self.fixtureSkillID, path: Self.fixtureFilePath)

        let output = await Self.resolvedPath(of: absolutePath)

        #expect(output == .success(Self.fixtureFilePath))
    }

    /// The closure does not run, and the denied corrective names the path that
    /// the model gave.
    @Test func anAbsolutePathOutsideTheSkillDrawsTheDeniedCorrective() async {
        let output = await Self.resolvedPath(of: ResourceTestSupport.systemFilePath)

        #expect(output == .corrective(ResourcePathRules.deniedMessage(path: ResourceTestSupport.systemFilePath)))
    }
}
