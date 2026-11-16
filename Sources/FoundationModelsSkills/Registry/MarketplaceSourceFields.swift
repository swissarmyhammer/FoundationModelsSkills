import FoundationModelsExtras
import Marketplace

/// The fields of one marketplace source as a client or the model gives
/// them: each field is optional.
///
/// The `skills` GraphQL endpoint (`addMarketplace`, `updateMarketplace`) and
/// the `add marketplace` and `edit marketplace` operations of the `skills`
/// tool use this one type, thus the two surfaces read the fields the same
/// way (D190, D100). The `MarketplaceRegistry` of Extras then checks, saves
/// and announces the source.
public struct MarketplaceSourceFields: Sendable, Equatable {
    /// The location, or `nil` for no change.
    public var url: String?

    /// A branch or a tag. `nil` is no change, and an empty text clears it.
    public var ref: String?

    /// A commit pin. `nil` is no change, and an empty text clears it.
    public var sha: String?

    /// A subfolder of the repository. `nil` is no change, and an empty text
    /// clears it.
    public var path: String?

    /// The local name, which is the id when it is set. `nil` is no change,
    /// and an empty text clears it.
    public var alias: String?

    /// The skills to take, or `nil` for no change.
    public var skills: [String]?

    /// `true` to take all the skills again. It wins over ``skills``.
    public var allSkills: Bool

    /// Whether the store installs a new commit when it finds one, or `nil`
    /// for no change.
    public var autoUpdate: Bool?

    /// Creates the fields by directly assigning each one.
    ///
    /// - Parameters:
    ///   - url: The location, or `nil`.
    ///   - ref: A branch or a tag, or `nil`.
    ///   - sha: A commit pin, or `nil`.
    ///   - path: A subfolder of the repository, or `nil`.
    ///   - alias: The local name, or `nil`.
    ///   - skills: The skills to take, or `nil`.
    ///   - allSkills: `true` to take all the skills.
    ///   - autoUpdate: The auto-update flag, or `nil`.
    public init(
        url: String? = nil, ref: String? = nil, sha: String? = nil, path: String? = nil, alias: String? = nil,
        skills: [String]? = nil, allSkills: Bool = false, autoUpdate: Bool? = nil
    ) {
        self.url = url
        self.ref = ref
        self.sha = sha
        self.path = path
        self.alias = alias
        self.skills = skills
        self.allSkills = allSkills
        self.autoUpdate = autoUpdate
    }

    /// The new source of these fields, for an add.
    ///
    /// A field that is `nil` gets the default of `MarketplaceSource`.
    ///
    /// - Returns: The source. A missing `url` gives an empty URL, which the
    ///   registry refuses with `MarketplaceSourceError.emptyURL`.
    public func newSource() -> MarketplaceSource {
        applied(to: MarketplaceSource(url ?? ""))
    }

    /// `source` with these fields written over it, for an update.
    ///
    /// - Parameter source: The current source.
    /// - Returns: The changed source.
    public func applied(to source: MarketplaceSource) -> MarketplaceSource {
        var result = source
        if let url { result.url = url }
        if let ref { result.ref = Self.cleared(ref) }
        if let sha { result.sha = Self.cleared(sha) }
        if let path { result.path = Self.cleared(path) }
        if let alias { result.alias = Self.cleared(alias) }
        if let skills { result.select = .skills(skills) }
        if allSkills { result.select = .all }
        if let autoUpdate { result.autoUpdate = autoUpdate }
        return result
    }

    /// `text`, or `nil` when it is empty.
    ///
    /// - Parameter text: The text of a field.
    /// - Returns: The value of the field.
    private static func cleared(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}

extension MarketplaceRegistryChange {
    /// The ids of this change, as the change log of an endpoint keeps them.
    ///
    /// An update that keeps the id changes that id. An update that changes
    /// the id removes the old id and adds the new one.
    var changedIDs: ChangedIDs {
        switch self {
        case .added(let entry):
            ChangedIDs(added: [entry.id])
        case .removed(let entry):
            ChangedIDs(removed: [entry.id])
        case .updated(let previousID, let entry) where previousID == entry.id:
            ChangedIDs(changed: [entry.id])
        case .updated(let previousID, let entry):
            ChangedIDs(added: [entry.id], removed: [previousID])
        }
    }
}

/// The edits of a marketplace that the endpoint and the tool operations
/// share.
enum MarketplaceEdits {
    /// Writes `fields` over the source of the marketplace `id`.
    ///
    /// - Parameters:
    ///   - id: The id of the marketplace.
    ///   - fields: The changes.
    ///   - marketplaces: The registry.
    /// - Returns: The changed entry.
    /// - Throws: `MarketplaceRegistryError.unknownMarketplace(id:)` when no
    ///   marketplace has the id, or another error of the registry.
    static func update(
        id: String, with fields: MarketplaceSourceFields, in marketplaces: MarketplaceRegistry
    ) async throws -> MarketplaceEntry {
        guard let current = try await marketplaces.marketplace(id: id) else {
            throw MarketplaceRegistryError.unknownMarketplace(id: id)
        }
        return try await marketplaces.update(id: id, to: fields.applied(to: current.source))
    }
}
