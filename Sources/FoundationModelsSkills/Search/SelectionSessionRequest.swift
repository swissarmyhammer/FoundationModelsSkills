import FoundationModelsMetadataRegistry

/// What the `skills` tool gives the host when its selection tier needs a new
/// session: the instructions, the candidate skill ids, and the JSON Schema
/// that holds the answer to those ids.
///
/// The selection tier reads the answer of a session as `{"ids": [String]}`.
/// A small model with no constraint on its output can write another shape,
/// for example `[explore]`. Thus this package makes the grammar, and the host
/// applies it when it makes the session. A session whose model takes a JSON
/// Schema grammar constrains its output with `jsonSchema`. Then each answer is
/// an object with one `ids` array, and each id is one of `candidateIDs`.
///
/// A `LanguageModelSession` constrains the `{"ids": [...]}` shape with its own
/// guided generation. It does not read `jsonSchema`, and it can still give an
/// id that is not a candidate. The tier drops such an id.
///
/// An answer that does not decode does not make the `search skill` call fail.
/// `SkillSearchAgent` then gives the rank of the retrieval tier (see
/// `SkillSearchAgent.init(searcher:retrievalFallback:visibilityPredicate:)`).
public struct SelectionSessionRequest: Sendable, Equatable {
    /// The instructions the new session starts with: the selection preamble
    /// and each candidate skill, as the selection tier assembled them.
    public let instructions: String

    /// The ids of the skills the tool presents at the time of the request.
    ///
    /// These are the ids `jsonSchema` permits. The tool reads them from the
    /// live registry through its visibility predicate, thus a reload that adds
    /// a skill adds its id to the next request.
    public let candidateIDs: [String]

    /// The JSON Schema source text that limits an answer to
    /// `{"ids": [String]}`, where each id is one of `candidateIDs`.
    ///
    /// The schema also sets `uniqueItems` and a `maxItems` of
    /// `candidateIDs.count`, thus a constrained model cannot repeat one id
    /// without end. `SelectionTier.idEnumSchema(ids:)` makes it.
    public let jsonSchema: String

    /// Creates a request, and makes its JSON Schema from `candidateIDs`.
    ///
    /// - Parameters:
    ///   - instructions: The instructions the new session starts with.
    ///   - candidateIDs: The ids the schema permits.
    /// - Throws: Whatever `SelectionTier.idEnumSchema(ids:)` throws. An array
    ///   of strings always encodes, thus this is not expected.
    init(instructions: String, candidateIDs: [String]) throws {
        self.instructions = instructions
        self.candidateIDs = candidateIDs
        jsonSchema = try SelectionTier.idEnumSchema(ids: candidateIDs)
    }
}

/// The session the tool gives the selection tier when it cannot make a
/// `SelectionSessionRequest`.
///
/// Each call throws `cause`. Thus the failure reaches `SkillSearchAgent`, which
/// records it and gives the rank of the retrieval tier. The failure does not
/// stop the search, and it is not silent.
struct UnavailableSelectionSession: AgentSession {
    /// The error that stopped the request.
    let cause: any Error

    /// Throws `cause`, and sends no prompt.
    ///
    /// - Parameter prompt: The prompt the tier sends. It is not read.
    /// - Returns: Nothing; the call always throws.
    /// - Throws: `cause`.
    func respond(to prompt: String) async throws -> String {
        throw cause
    }
}
