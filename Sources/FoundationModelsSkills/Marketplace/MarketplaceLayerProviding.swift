import Foundation
import FoundationModelsExtras

/// Where one marketplace skill came from (marketplace.md §9.1).
///
/// A diagnostic carries this value, so a surface can say which marketplace,
/// at which commit, a skill came from. The value never carries a
/// credential: ``MarketplaceCredential`` is a separate value that the
/// transport asks for, and it never becomes part of a URL here.
public struct MarketplaceProvenance: Sendable, Equatable {
    /// The display id of the marketplace: the `name` field of the catalog
    /// after a fetch, else the pre-fetch key (marketplace.md §5.3).
    public var id: String

    /// The `url` field of the source, as the host wrote it.
    public var url: String

    /// The commit of the snapshot that the layer root names, or `nil`
    /// before the first install.
    public var sha: String?

    /// The `version` field of the catalog of that snapshot, or `nil` when
    /// the catalog has none.
    public var catalogVersion: String?

    /// Creates a provenance by directly assigning every field.
    ///
    /// - Parameters:
    ///   - id: The display id of the marketplace.
    ///   - url: The `url` field of the source.
    ///   - sha: The commit of the snapshot. The default is `nil`.
    ///   - catalogVersion: The `version` field of the catalog. The default
    ///     is `nil`.
    public init(id: String, url: String, sha: String? = nil, catalogVersion: String? = nil) {
        self.id = id
        self.url = url
        self.sha = sha
        self.catalogVersion = catalogVersion
    }

    /// How many first characters of ``sha`` a row shows when the catalog
    /// carries no version: the usual short form of a commit.
    private static let shortShaLength = 7

    /// The text a display row shows for this marketplace, for example
    /// `swissarmyhammer-skills@1.2.0` (marketplace.md §9.1).
    ///
    /// The catalog version names the snapshot when the catalog has one.
    /// Without a version, the short commit names it instead, thus a row
    /// still says which snapshot a skill came from. Without a commit too,
    /// the id alone is the text.
    ///
    /// ``url`` is never part of the text: a URL can hold a credential, and
    /// a row must never show one.
    public var displayText: String {
        if let catalogVersion {
            return "\(id)@\(catalogVersion)"
        }
        if let sha {
            return "\(id)@\(sha.prefix(Self.shortShaLength))"
        }
        return id
    }
}

/// One marketplace as the registry sees it: a layer root plus the
/// provenance of what that root holds (marketplace.md §4.2).
///
/// The root is the stable `<cache>/<id>/current` path, thus it stays the
/// same across an update; only the provenance changes.
public struct MarketplaceLayer: Sendable {
    /// The layer itself. Its source is ``FoundationModelsExtras/DotfolderStack/Source/marketplace``,
    /// thus it never renders trusted (marketplace.md §4.3).
    public var layer: DotfolderStack.Layer

    /// Where the skills under ``layer`` came from.
    public var provenance: MarketplaceProvenance

    /// What the host lets the skills under ``layer`` run
    /// (marketplace.md §6.6).
    ///
    /// A grant removes only the marketplace block. The host `RenderPolicy`
    /// always wins: a grant can never turn on what the host policy turned
    /// off.
    public var grants: MarketplaceGrants

    /// Creates a marketplace layer by directly assigning its fields.
    ///
    /// - Parameters:
    ///   - layer: The layer itself.
    ///   - provenance: Where the skills under that layer came from.
    ///   - grants: What the host lets the skills under that layer run. The
    ///     default is ``MarketplaceGrants/none``: no shell injection and no
    ///     scripts.
    public init(
        layer: DotfolderStack.Layer, provenance: MarketplaceProvenance, grants: MarketplaceGrants = .none
    ) {
        self.layer = layer
        self.provenance = provenance
        self.grants = grants
    }
}

/// What ``SkillsRegistry`` needs from a marketplace store: the layers to put
/// below the local stack, and a signal that they changed (marketplace.md
/// §7.4).
///
/// The registry stays a pure disk reader. It never fetches, and it never
/// waits on the network: it reads the layers that the provider names, and it
/// rebuilds when the provider says so. A symlink swap sends no reliable
/// file-system event, thus the signal, and not the file watcher, is what
/// makes a marketplace update reach the catalog.
public protocol MarketplaceLayerProviding: Sendable {
    /// Gives the current marketplace layers, lowest precedence first.
    ///
    /// The registry calls this again on every update, because the commit
    /// and the catalog version of a layer change while its root stays the
    /// same.
    ///
    /// - Returns: The layers, lowest precedence first.
    func marketplaceLayers() -> [MarketplaceLayer]

    /// One value for each time the marketplace layers changed.
    ///
    /// Each access registers a subscription, thus the registry takes the
    /// stream one time, at construction.
    var layerUpdates: AsyncStream<Void> { get }
}

/// Which marketplace each layer of one catalog generation came from, and
/// what its skills may run, by layer index.
///
/// `DiscoveredSkill.rootIndex` and `ShadowedCandidate.rootIndex` are both
/// indices into the same ordered layer list, thus one lookup by index
/// serves the winner's provenance, the shadow message, and the grants that
/// gate the winner's shell injection and scripts (marketplace.md §6.6).
internal struct MarketplaceProvenanceIndex: Sendable {
    /// What one marketplace layer carries: where its skills came from, and
    /// what the host lets them run.
    internal struct Entry: Sendable {
        /// Where the skills of the layer came from.
        let provenance: MarketplaceProvenance

        /// What the host lets those skills run.
        let grants: MarketplaceGrants

        /// Creates an entry.
        ///
        /// - Parameters:
        ///   - provenance: Where the skills of the layer came from.
        ///   - grants: What the host lets those skills run.
        init(provenance: MarketplaceProvenance, grants: MarketplaceGrants) {
            self.provenance = provenance
            self.grants = grants
        }
    }

    /// One entry for each layer, in layer order; `nil` for a local layer.
    private let byLayerIndex: [Entry?]

    /// Creates an index.
    ///
    /// - Parameter byLayerIndex: One entry for each layer, in layer order;
    ///   `nil` for a local layer. The default is no entry, which names no
    ///   marketplace at all.
    init(byLayerIndex: [Entry?] = []) {
        self.byLayerIndex = byLayerIndex
    }

    /// Gives the marketplace of one layer.
    ///
    /// - Parameter index: The index of the layer.
    /// - Returns: The marketplace, or `nil` for a local layer or an index
    ///   that names no layer.
    func provenance(atLayerIndex index: Int) -> MarketplaceProvenance? {
        entry(atLayerIndex: index)?.provenance
    }

    /// Gives the grants of one layer.
    ///
    /// - Parameter index: The index of the layer.
    /// - Returns: The grants, or `nil` for a local layer or an index that
    ///   names no layer.
    func grants(atLayerIndex index: Int) -> MarketplaceGrants? {
        entry(atLayerIndex: index)?.grants
    }

    /// Gives the entry of one layer.
    ///
    /// - Parameter index: The index of the layer.
    /// - Returns: The entry, or `nil` for a local layer or an index that
    ///   names no layer.
    private func entry(atLayerIndex index: Int) -> Entry? {
        byLayerIndex.indices.contains(index) ? byLayerIndex[index] : nil
    }
}
