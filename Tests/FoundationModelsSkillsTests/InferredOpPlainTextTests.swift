import Foundation
import FoundationModels
import FoundationModelsSkills
import Testing

/// Tests for the payloads of the fused `skills` tool that do not name their
/// operation the plain way: a payload with no `op`, and a payload in one
/// `arguments` key.
///
/// The `Operations` runtime infers a missing `op` from the keys of the
/// payload, and unwraps a lone `arguments` object (^vm78pnz). A call of the
/// Recursive Flint model is `{"id": "kanban"}`: the keys fit `use skill` and
/// `list resource`, and the resolver of the tool settles on `use skill`. The
/// answer of an inferred or unwrapped `use skill` is the rendered body as
/// plain text, as it is for an explicit `use skill`. An explicit op keeps
/// the answer it had.
struct InferredOpPlainTextTests {
    // MARK: - Constants

    /// The canonical op of the `use skill` operation.
    private static let useSkillOp = "use skill"

    /// The canonical op of the `list resource` operation.
    private static let listResourceOp = "list resource"

    /// The key that holds the operation of a payload.
    private static let opKey = "op"

    /// The key that holds the skill id of a payload.
    private static let idKey = "id"

    /// The key that a caller sometimes puts a whole payload into.
    private static let argumentsKey = "arguments"

    /// The fixture skill with no file other than `SKILL.md`, thus the answer
    /// of `use skill` is the rendered body alone.
    private static let commitSkillID = "commit"

    /// The fixture skill with four files, thus `list resource` has rows.
    private static let releaseNotesSkillID = "release-notes"

    /// The JSON of the first row of `list resource` over
    /// `releaseNotesSkillID`.
    private static let releaseNotesFirstRow = #""kind":"asset","path":"assets\/logo.bin""#

    // MARK: - A payload with no op

    @Test func anIDWithNoOpGivesTheRenderedBody() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await Self.makeTool(registry: registry).call(
            arguments: GeneratedContent(properties: [Self.idKey: Self.commitSkillID]))

        #expect(answer == renderedBody)
    }

    @Test func performOfAnIDWithNoOpGivesTheRenderedBody() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await Self.makeTool(registry: registry).perform(
            GeneratedContent(properties: [Self.idKey: Self.commitSkillID]))

        #expect(answer == renderedBody)
    }

    @Test func anIDBesideAnEmptyArgumentsArrayWithNoOpGivesTheRenderedBody() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await Self.makeTool(registry: registry).call(
            arguments: GeneratedContent(properties: [Self.argumentsKey: [String](), Self.idKey: Self.commitSkillID]))

        #expect(answer == renderedBody)
    }

    // MARK: - A payload in one arguments key

    @Test func aUseSkillPayloadInArgumentsGivesTheRenderedBody() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await Self.makeTool(registry: registry).call(
            arguments: Self.wrapped(GeneratedContent(properties: [Self.opKey: Self.useSkillOp, Self.idKey: Self.commitSkillID])))

        #expect(answer == renderedBody)
    }

    @Test func anIDWithNoOpInArgumentsGivesTheRenderedBody() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await Self.makeTool(registry: registry).call(
            arguments: Self.wrapped(GeneratedContent(properties: [Self.idKey: Self.commitSkillID])))

        #expect(answer == renderedBody)
    }

    // MARK: - An explicit op keeps its answer

    @Test func anExplicitUseSkillGivesTheRenderedBody() async throws {
        let registry = Self.makeFixtureRegistry()
        let renderedBody = try await registry.call(id: Self.commitSkillID, arguments: [])

        let answer = try await Self.makeTool(registry: registry).call(
            arguments: GeneratedContent(properties: [Self.opKey: Self.useSkillOp, Self.idKey: Self.commitSkillID]))

        #expect(answer == renderedBody)
    }

    @Test func anExplicitListResourceStillGivesItsJSONRows() async throws {
        let answer = try await Self.makeTool(registry: Self.makeFixtureRegistry()).call(
            arguments: GeneratedContent(properties: [
                Self.opKey: Self.listResourceOp, Self.idKey: Self.releaseNotesSkillID,
            ]))

        #expect(answer.contains(Self.releaseNotesFirstRow))
    }

    @Test func aListResourcePayloadInArgumentsStillGivesItsJSONRows() async throws {
        let answer = try await Self.makeTool(registry: Self.makeFixtureRegistry()).call(
            arguments: Self.wrapped(
                GeneratedContent(properties: [Self.opKey: Self.listResourceOp, Self.idKey: Self.releaseNotesSkillID])))

        #expect(answer.contains(Self.releaseNotesFirstRow))
    }

    // MARK: - Fixtures

    /// The payload that holds `payload` in one `arguments` key.
    ///
    /// - Parameter payload: The inner payload.
    /// - Returns: The wrapped payload.
    private static func wrapped(_ payload: GeneratedContent) -> GeneratedContent {
        GeneratedContent(properties: [argumentsKey: payload])
    }

    /// Builds a registry over the `project/.skills` fixture root.
    ///
    /// - Returns: The registry that the tool and the expected body share.
    private static func makeFixtureRegistry() -> SkillsRegistry {
        SkillsRegistry(roots: [FixtureLibrary.url(relativePath: "project/.skills")], mode: .open)
    }

    /// Builds the fused `skills` tool over `registry`, with the model-facing
    /// visibility predicate.
    ///
    /// - Parameter registry: The registry the tool dispatches against.
    /// - Returns: The fused tool.
    /// - Throws: Whatever `SkillsTool.make(context:)` throws.
    private static func makeTool(registry: SkillsRegistry) throws -> SkillsCatalogTool {
        try SkillsTool.make(context: FixtureLibrary.makeSkillsToolContext(registry: registry))
    }
}
