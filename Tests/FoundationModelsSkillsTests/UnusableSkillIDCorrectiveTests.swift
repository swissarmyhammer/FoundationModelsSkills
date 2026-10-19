import Foundation
import FoundationModels
import FoundationModelsSkills
import Testing

/// Tests for the corrective that the `skills` tool gives for a skill id that
/// is not usable.
///
/// The `id` field of the schema is a plain string, thus a small model can
/// guess an id. The corrective names the closest usable ids, at most five,
/// by edit distance and then by id. It then gives the exact `search skill`
/// call. `use skill` and each resource operation give the same text.
struct UnusableSkillIDCorrectiveTests {
    // MARK: - Constants

    /// The sentence that ends each corrective with usable ids: the exact
    /// `search skill` call.
    private static let searchSentence =
        #"To find a skill, call the `skills` tool with {"op": "search skill", "query": "<the kind of work>"}."#

    /// The skills of the near-miss case. `explain` sorts before `explore`,
    /// thus the order of the answer shows the edit distance, not the id.
    private static let nearMissSkillIDs = ["explain", "explore", "lint"]

    /// The near miss of `explore` that the model writes.
    private static let nearMissID = "explor"

    /// The skills of the limit case. Five ids are one edit from `lint`.
    /// `print` is two edits from it, and `commit` is far from it. `commit`
    /// sorts first, thus the order of the answer shows the edit distance.
    private static let limitSkillIDs = ["commit", "flint", "line", "lints", "list", "mint", "print"]

    /// The id of the limit case, which no skill has.
    private static let limitID = "lint"

    // MARK: - use skill

    @Test func aNearMissIDGivesTheClosestIDsThenTheSearchCall() async throws {
        let answer = try await Self.answer(
            op: "use skill", id: Self.nearMissID, skillIDs: Self.nearMissSkillIDs)

        #expect(
            answer
                == "The skill id `explor` is not currently usable. "
                + "Closest usable ids: explore, explain, lint. " + Self.searchSentence)
    }

    @Test func theCorrectiveNamesAtMostFiveIDsByEditDistanceThenByID() async throws {
        let answer = try await Self.answer(op: "use skill", id: Self.limitID, skillIDs: Self.limitSkillIDs)

        #expect(
            answer
                == "The skill id `lint` is not currently usable. "
                + "Closest usable ids: flint, line, lints, list, mint. " + Self.searchSentence)
    }

    // MARK: - The resource operations

    @Test func listResourceGivesTheSameCorrectiveAsUseSkill() async throws {
        let useAnswer = try await Self.answer(
            op: "use skill", id: Self.nearMissID, skillIDs: Self.nearMissSkillIDs)

        let listJSON = try await Self.answer(
            op: "list resource", id: Self.nearMissID, skillIDs: Self.nearMissSkillIDs)

        #expect(try JSONDecoder().decode(String.self, from: Data(listJSON.utf8)) == useAnswer)
    }

    // MARK: - Fixtures

    /// Gives the answer of the fused tool to one call, over a temporary
    /// layer that holds one minimal skill for each of `skillIDs`.
    ///
    /// - Parameters:
    ///   - op: The op of the call.
    ///   - id: The skill id of the call.
    ///   - skillIDs: The skills of the temporary layer.
    /// - Returns: The answer of the tool.
    /// - Throws: Whatever a fixture write, `SkillsTool.make(context:)`, or
    ///   `call(arguments:)` throws.
    private static func answer(op: String, id: String, skillIDs: [String]) async throws -> String {
        let directories = try LayerFixtureSupport.makeLayerDirectories(count: 1)
        defer { LayerFixtureSupport.removeDirectories(directories) }
        for skillID in skillIDs {
            try ResourceTestSupport.writeMinimalSkillFile(id: skillID, in: directories[0])
        }
        let tool = try SkillsTool.make(context: ResourceTestSupport.makeContext(roots: directories))
        return try await tool.call(arguments: GeneratedContent(properties: ["op": op, "id": id]))
    }
}
