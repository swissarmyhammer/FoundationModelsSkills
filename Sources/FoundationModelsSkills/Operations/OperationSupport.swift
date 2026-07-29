import Foundation
import FoundationModels
import Operations

/// The shared noun every skill operation (`SearchSkill`, `ListSkill`,
/// `UseSkill`) acts on, so the literal lives in one place rather than being
/// repeated across three `static let noun` declarations.
internal let skillOperationNoun = "skill"

extension OperationDefinition {
    /// This operation's `Generable` schema.
    ///
    /// Declared with no properties for every hand-conformed operation in
    /// this package: schema fusion (`SchemaFusion.fuse`) builds the fused
    /// tool's actual model-facing schema from `parameterMetadata`, not from
    /// this property, so it carries no independent meaning beyond
    /// satisfying `Generable`'s requirement. A single default here (rather
    /// than one hand-written copy per operation) keeps `SearchSkill`,
    /// `ListSkill`, and `UseSkill` from repeating the identical boilerplate.
    public static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, description: operationDescription, properties: [])
    }
}

extension String {
    /// Whether this string is empty once leading/trailing whitespace is
    /// trimmed.
    ///
    /// Shared by `SearchSkill`'s blank-query check and `ListSkill`'s
    /// blank-filter check, so the two operations can never drift on what
    /// counts as "blank."
    internal var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Builds a `generatedContent` payload from one required property and one
/// optional property, omitting the optional key entirely when its value is
/// `nil`.
///
/// The shared round-trip encoding shape `SearchSkill.generatedContent`
/// (`query` required, `limit` optional) and `UseSkill.generatedContent`
/// (`id` required, `arguments` optional) both need, despite filling the
/// optional slot with different value types (`Int`, `[String]`) --
/// generic over that slot rather than duplicating the guard per operation.
internal enum GeneratedContentBuilder {
    /// Builds the payload.
    ///
    /// - Parameters:
    ///   - requiredKey: The always-present property's name.
    ///   - requiredValue: The always-present property's value.
    ///   - optionalKey: The possibly-absent property's name.
    ///   - optionalValue: The possibly-absent property's value; `nil` omits
    ///     `optionalKey` entirely.
    /// - Returns: The assembled payload.
    internal static func make<OptionalValue: ConvertibleToGeneratedContent>(
        requiredKey: String, requiredValue: any ConvertibleToGeneratedContent,
        optionalKey: String, optionalValue: OptionalValue?
    ) -> GeneratedContent {
        guard let optionalValue else {
            return GeneratedContent(properties: [requiredKey: requiredValue])
        }
        return GeneratedContent(properties: [requiredKey: requiredValue, optionalKey: optionalValue])
    }
}

/// One operation's outcome: either a successful `Encodable` result or a
/// corrective message for the model.
///
/// Follows the sibling family's *return, don't throw* convention for a
/// recoverable, business-logic-level failure: `SearchSkill` (`SearchSkillOutput`)
/// and `UseSkill` (`UseSkillOutput`) both need this exact shape, so the
/// shared `encode(to:)` behind it lives here once instead of being
/// duplicated per operation.
public enum CorrectiveOutcome<Success: Encodable & Sendable & Equatable>: Encodable, Sendable, Equatable {
    /// A successful outcome, carrying the operation's typed result.
    case success(Success)

    /// A recoverable failure carrying a corrective message for the model.
    case corrective(String)

    /// The coding key for the `.corrective(_:)` encoding.
    private enum CodingKeys: String, CodingKey {
        /// The corrective-message field.
        case corrective
    }

    /// Encodes the outcome.
    ///
    /// A `.success(_:)` outcome encodes `Success` inline; a
    /// `.corrective(_:)` outcome encodes a single `corrective` field
    /// carrying the message.
    ///
    /// - Parameter encoder: The encoder to write the outcome into.
    /// - Throws: Whatever `encoder` throws while writing.
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .success(let value):
            try value.encode(to: encoder)
        case .corrective(let message):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .corrective)
        }
    }
}
