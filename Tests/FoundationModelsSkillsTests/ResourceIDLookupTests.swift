import Foundation
import FoundationModelsSkills
import Testing

/// Tests for the corrective `ResourceIDLookup` draws when the calling
/// context's catalog holds no usable skill at all. `ResourceOpsTests` and
/// `RunScriptTests` always hold at least one usable skill, so they reach
/// only the "Currently usable ids: ..." branch of that message.
struct ResourceIDLookupTests {
    /// The skill id every empty-catalog test asks for. No catalog holds it.
    private static let missingID = "missing"

    /// The resource path the `ReadResource` test names. It is never read,
    /// because the id fails to resolve first.
    private static let samplePath = "SKILL.md"

    /// The text the other branch of the corrective carries, and this branch
    /// must not.
    private static let usableIDsPrefix = "Currently usable ids:"

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
}
