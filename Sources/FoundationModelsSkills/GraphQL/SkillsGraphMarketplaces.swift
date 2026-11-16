import FoundationModelsExtras
import Graphiti
import Marketplace

// The skill marketplaces of the `skills` endpoint (D190): the queries
// `marketplaces` and `marketplace(id:)`, the mutations `addMarketplace`,
// `updateMarketplace` and `removeMarketplace`, and the subscription
// `marketplaceChanges(after:)`. Each call goes to the `MarketplaceRegistry`
// of Extras that the host gives. The registry does not refresh the
// `MarketplaceStore`: the host makes a new store on each change.

// MARK: - Object types

/// The `Marketplace` object: one skill marketplace of the list.
struct SkillsGraphMarketplace: Codable, Sendable {
    /// The id: the alias, or else the repository name.
    let id: ToolkitID

    /// The location.
    let url: String

    /// The branch or the tag, or `nil`.
    let ref: String?

    /// The commit pin, or `nil`.
    let sha: String?

    /// The subfolder of the repository, or `nil`.
    let path: String?

    /// The local name, or `nil`.
    let alias: String?

    /// The skills to take, or `nil` for all the skills.
    let skills: [String]?

    /// Whether the store installs a new commit when it finds one.
    let autoUpdate: Bool

    /// Makes the object of one entry of the registry.
    ///
    /// - Parameter entry: The entry.
    init(_ entry: MarketplaceEntry) {
        let source = entry.source
        id = ToolkitID(entry.id)
        url = source.url
        ref = source.ref
        sha = source.sha
        path = source.path
        alias = source.alias
        switch source.select {
        case .all: skills = nil
        case .skills(let names): skills = names
        }
        autoUpdate = source.autoUpdate
    }
}

/// The `MarketplaceChange` object: one change of the marketplace list.
struct SkillsGraphMarketplaceChange: Sendable {
    /// The cursor that resumes after this change.
    let cursor: String

    /// The time of the change.
    let at: DateTime

    /// The ids that the change added.
    let added: [ToolkitID]

    /// The ids that the change changed.
    let changed: [ToolkitID]

    /// The ids that the change removed.
    let removed: [ToolkitID]

    /// Makes the object of one entry of the change log.
    ///
    /// - Parameter entry: The entry.
    init(_ entry: ChangeLogEntry<ChangedIDs>) {
        let change = IDChange(entry)
        cursor = change.cursor
        at = change.at
        added = change.added
        changed = change.changed
        removed = change.removed
    }
}

// MARK: - Inputs

/// The arguments of `Query.marketplace`.
struct SkillsGraphMarketplaceArguments: Codable, Sendable {
    /// The id of the marketplace.
    let id: ToolkitID
}

/// The `input` object of `addMarketplace`.
struct AddMarketplaceInput: Codable, Sendable {
    /// The location.
    let url: String

    /// The branch or the tag, or `nil`.
    let ref: String?

    /// The commit pin, or `nil`.
    let sha: String?

    /// The subfolder of the repository, or `nil`.
    let path: String?

    /// The local name, or `nil`.
    let alias: String?

    /// The skills to take, or `nil` for all the skills.
    let skills: [String]?

    /// The auto-update flag, or `nil` for `true`.
    let autoUpdate: Bool?

    /// The fields of the new source.
    var fields: MarketplaceSourceFields {
        MarketplaceSourceFields(
            url: url, ref: ref, sha: sha, path: path, alias: alias, skills: skills, autoUpdate: autoUpdate)
    }
}

/// The `input` object of `updateMarketplace`. A field that is `nil` does not
/// change, and an empty text clears a text field.
struct UpdateMarketplaceInput: Codable, Sendable {
    /// The id of the marketplace to change.
    let id: ToolkitID

    /// The new location, or `nil`.
    let url: String?

    /// The new branch or tag, or `nil`.
    let ref: String?

    /// The new commit pin, or `nil`.
    let sha: String?

    /// The new subfolder, or `nil`.
    let path: String?

    /// The new local name, or `nil`.
    let alias: String?

    /// The new skills to take, or `nil`.
    let skills: [String]?

    /// `true` to take all the skills again, or `nil`.
    let allSkills: Bool?

    /// The new auto-update flag, or `nil`.
    let autoUpdate: Bool?

    /// The fields of the change.
    var fields: MarketplaceSourceFields {
        MarketplaceSourceFields(
            url: url, ref: ref, sha: sha, path: path, alias: alias, skills: skills, allSkills: allSkills ?? false,
            autoUpdate: autoUpdate)
    }
}

/// The `input` object of `removeMarketplace`.
struct RemoveMarketplaceInput: Codable, Sendable {
    /// The id of the marketplace to remove.
    let id: ToolkitID
}

// MARK: - Errors

/// The errors of the marketplace mutations of the `skills` endpoint. An id
/// that no marketplace has gives the `NOT_FOUND` of the toolkit.
enum SkillsGraphMarketplaceError: CodedError, Equatable {
    /// `DUPLICATE_MARKETPLACE`: the list has a marketplace with the id.
    case duplicateMarketplace(message: String)

    /// `INVALID_MARKETPLACE`: the source is not usable.
    case invalidMarketplace(message: String)

    /// `MARKETPLACES_UNAVAILABLE`: the host gave the endpoint no
    /// marketplace registry.
    case marketplacesUnavailable

    /// Each code of this type, for rule 8 of EXTRAS-9.
    static let codes = ["DUPLICATE_MARKETPLACE", "INVALID_MARKETPLACE", "MARKETPLACES_UNAVAILABLE"]

    /// The code of the error.
    var code: String {
        switch self {
        case .duplicateMarketplace: Self.codes[0]
        case .invalidMarketplace: Self.codes[1]
        case .marketplacesUnavailable: Self.codes[2]
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    var message: String {
        switch self {
        case .duplicateMarketplace(let message), .invalidMarketplace(let message):
            message
        case .marketplacesUnavailable:
            "This host keeps no marketplace list, thus a marketplace cannot change here."
        }
    }

    /// The coded error of an error of the registry.
    ///
    /// - Parameter error: The error of the registry.
    /// - Returns: The coded error.
    static func coded(_ error: MarketplaceRegistryError) -> any CodedError {
        let message = error.errorDescription ?? "\(error)"
        switch error {
        case .duplicateMarketplace:
            return Self.duplicateMarketplace(message: message)
        case .unknownMarketplace(let id):
            return GraphQLToolkitError.notFound(kind: marketplaceKind, id: id)
        case .invalidSource:
            return Self.invalidMarketplace(message: message)
        }
    }

    /// The kind of the id in a `NOT_FOUND` error.
    static let marketplaceKind = "marketplace"
}

// MARK: - The change feed

/// Feeds the marketplace change log of the `skills` endpoint from the
/// changes of one `MarketplaceRegistry`: one `ChangedIDs` event for each
/// change.
///
/// The endpoint owns the feed, and the deinit of the feed cancels the task.
final class MarketplaceChangeFeed: Sendable {
    /// The task that appends the events.
    private let task: Task<Void, Never>

    /// Starts to feed a change log from the changes of a registry.
    ///
    /// The feed subscribes before the init returns, thus a mutation after
    /// the init always reaches the log.
    ///
    /// - Parameters:
    ///   - marketplaces: The registry whose changes feed the log.
    ///   - changeLog: The change log that gets one event for each change.
    init(marketplaces: MarketplaceRegistry, changeLog: ChangeLog<ChangedIDs>) {
        let changes = marketplaces.changes()
        task = Task {
            for await change in changes {
                await changeLog.append(change.changedIDs)
            }
        }
    }

    /// Stops the feed.
    deinit {
        task.cancel()
    }
}

// MARK: - Resolvers

extension SkillsGraphResolver {
    /// Resolves `Query.marketplaceCursor`.
    ///
    /// - Returns: The cursor of the newest change of the marketplaces.
    func marketplaceCursor(context _: SkillsGraphContext, arguments _: NoArguments) async -> String {
        await marketplaceChangeLog.cursor
    }

    /// Resolves the source stream of `Subscription.marketplaceChanges`.
    ///
    /// - Parameter arguments: The cursor to resume after.
    /// - Returns: The changes after the cursor.
    func marketplaceChanges(
        context _: SkillsGraphContext, arguments: SkillsGraphChangesArguments
    ) async -> ChangeLog<ChangedIDs>.Changes {
        await marketplaceChangeLog.changes(after: arguments.after)
    }

    /// Resolves `Query.marketplaces`.
    ///
    /// - Returns: Each marketplace of the list, in order, or no marketplace
    ///   when the host gave no registry.
    /// - Throws: An error of the storage of the registry.
    func marketplaces(context _: SkillsGraphContext, arguments _: NoArguments) async throws -> [SkillsGraphMarketplace] {
        guard let marketplaces else { return [] }
        return try await Self.coding { try await marketplaces.marketplaces().map(SkillsGraphMarketplace.init) }
    }

    /// Resolves `Query.marketplace`.
    ///
    /// - Parameter arguments: The id of the marketplace.
    /// - Returns: The marketplace, or `nil` when no marketplace has the id.
    /// - Throws: An error of the storage of the registry.
    func marketplace(
        context _: SkillsGraphContext, arguments: SkillsGraphMarketplaceArguments
    ) async throws -> SkillsGraphMarketplace? {
        guard let marketplaces else { return nil }
        return try await Self.coding {
            try await marketplaces.marketplace(id: arguments.id.text).map(SkillsGraphMarketplace.init)
        }
    }

    /// Resolves `Mutation.addMarketplace`.
    ///
    /// - Parameter arguments: The new marketplace.
    /// - Returns: The new marketplace.
    /// - Throws: `DUPLICATE_MARKETPLACE`, `INVALID_MARKETPLACE`,
    ///   `MARKETPLACES_UNAVAILABLE`, or an error of the storage.
    func addMarketplace(
        context _: SkillsGraphContext, arguments: SkillsGraphInputArguments<AddMarketplaceInput>
    ) async throws -> SkillsGraphMarketplace? {
        let marketplaces = try requireMarketplaces()
        return try await Self.coding {
            SkillsGraphMarketplace(try await marketplaces.add(arguments.input.fields.newSource()))
        }
    }

    /// Resolves `Mutation.updateMarketplace`.
    ///
    /// - Parameter arguments: The marketplace and its changes.
    /// - Returns: The changed marketplace.
    /// - Throws: `NOT_FOUND`, `DUPLICATE_MARKETPLACE`, `INVALID_MARKETPLACE`,
    ///   `MARKETPLACES_UNAVAILABLE`, or an error of the storage.
    func updateMarketplace(
        context _: SkillsGraphContext, arguments: SkillsGraphInputArguments<UpdateMarketplaceInput>
    ) async throws -> SkillsGraphMarketplace? {
        let marketplaces = try requireMarketplaces()
        let input = arguments.input
        return try await Self.coding {
            SkillsGraphMarketplace(try await MarketplaceEdits.update(id: input.id.text, with: input.fields, in: marketplaces))
        }
    }

    /// Resolves `Mutation.removeMarketplace`.
    ///
    /// - Parameter arguments: The marketplace to remove.
    /// - Returns: The removed marketplace.
    /// - Throws: `NOT_FOUND`, `MARKETPLACES_UNAVAILABLE`, or an error of the
    ///   storage.
    func removeMarketplace(
        context _: SkillsGraphContext, arguments: SkillsGraphInputArguments<RemoveMarketplaceInput>
    ) async throws -> SkillsGraphMarketplace? {
        let marketplaces = try requireMarketplaces()
        return try await Self.coding {
            SkillsGraphMarketplace(try await marketplaces.remove(id: arguments.input.id.text))
        }
    }

    /// The marketplace registry of the endpoint.
    ///
    /// - Returns: The registry.
    /// - Throws: `MARKETPLACES_UNAVAILABLE` when the host gave none.
    private func requireMarketplaces() throws -> MarketplaceRegistry {
        guard let marketplaces else {
            throw SkillsGraphMarketplaceError.marketplacesUnavailable
        }
        return marketplaces
    }

    /// Runs `body`, and gives each error of the registry as a coded error.
    ///
    /// - Parameter body: The call of the registry.
    /// - Returns: The value of `body`.
    /// - Throws: The coded error of a `MarketplaceRegistryError`, or any
    ///   other error of `body` as it is.
    private static func coding<Value>(_ body: () async throws -> Value) async throws -> Value {
        do {
            return try await body()
        } catch let error as MarketplaceRegistryError {
            throw SkillsGraphMarketplaceError.coded(error)
        }
    }
}
