import Foundation
import FoundationModels
import FoundationModelsSkills
import Testing

/// Tests for `ListResource` that call the operation directly, without the
/// fused `skills` tool in front of it: the memberwise initializer and the
/// `generatedContent` round trip. `ResourceOpsTests` covers the same
/// operation through the tool's dispatch.
struct ListResourceTests {
    /// The skill id every direct-construction test names.
    private static let sampleID = "release-notes"

    /// The one property name `ListResource.generatedContent` carries.
    private static let idKey = "id"

    // MARK: - Memberwise initializer

    @Test func memberwiseInitStoresTheID() {
        let operation = ListResource(id: Self.sampleID)

        #expect(operation.id == Self.sampleID)
    }

    // MARK: - generatedContent / init(_:) round trips

    @Test func roundTripsThroughGeneratedContentKeepingTheID() throws {
        let original = ListResource(id: Self.sampleID)

        let decoded = try ListResource(original.generatedContent)

        #expect(decoded.id == original.id)
    }

    @Test func generatedContentCarriesTheIDKeyOnly() throws {
        let content = ListResource(id: Self.sampleID).generatedContent

        let payload = try #require(
            JSONSerialization.jsonObject(with: Data(content.jsonString.utf8)) as? [String: String])

        #expect(payload == [Self.idKey: Self.sampleID])
    }
}
