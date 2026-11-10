import Foundation
import FoundationModelsSkills
import Testing

/// Shared reads of the `skills` GraphQL endpoint for the test suites.
///
/// `SkillsGraphChangesTests` and `SkillsCatalogToolEndpointTests` both read
/// the root `cursor` and the events of the `changes` subscription. They call
/// these helpers, thus each read has one copy.
enum GraphQLTestSupport {
    /// Reads the JSON text of one GraphQL response as a JSON object.
    ///
    /// - Parameter response: The JSON text of the response.
    /// - Returns: The object.
    /// - Throws: A failure of `#require` when the text is not an object.
    static func object(_ response: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    }

    /// Reads the `data` object of one GraphQL response.
    ///
    /// - Parameter response: The JSON text of the response.
    /// - Returns: The `data` object.
    /// - Throws: A failure of `#require` when the response has no `data`
    ///   object.
    static func data(of response: String) throws -> [String: Any] {
        try #require(try object(response)["data"] as? [String: Any])
    }

    /// Gives the `extensions.code` of each error of one GraphQL response.
    ///
    /// - Parameter response: The JSON text of the response.
    /// - Returns: The codes, in order.
    /// - Throws: A failure of `#require` when the text is not an object.
    static func codes(of response: String) throws -> [String] {
        let errors = try object(response)["errors"] as? [[String: Any]] ?? []
        return errors.compactMap { error in (error["extensions"] as? [String: Any])?["code"] as? String }
    }

    /// Reads the `changes` event object of one subscription response.
    ///
    /// - Parameter response: The JSON text of the response.
    /// - Returns: The event object.
    /// - Throws: A failure of `#require` when the response has no event.
    static func changeEvent(in response: String) throws -> [String: Any] {
        try #require(try data(of: response)["changes"] as? [String: Any])
    }

    /// Queries the root `cursor` of `endpoint`.
    ///
    /// - Parameter endpoint: The `skills` endpoint.
    /// - Returns: The cursor of the newest event.
    /// - Throws: An error of the endpoint, or a failure of `#require` when
    ///   the response has no cursor.
    static func cursor(of endpoint: SkillsGraph) async throws -> String {
        let response = try await endpoint.execute(query: "{ cursor }", variables: [:], operationName: nil, viewer: nil)
        return try #require(try data(of: response)["cursor"] as? String)
    }
}
