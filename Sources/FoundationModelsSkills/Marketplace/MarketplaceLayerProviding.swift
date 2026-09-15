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

    /// Creates a marketplace layer by directly assigning both fields.
    ///
    /// - Parameters:
    ///   - layer: The layer itself.
    ///   - provenance: Where the skills under that layer came from.
    public init(layer: DotfolderStack.Layer, provenance: MarketplaceProvenance) {
        self.layer = layer
        self.provenance = provenance
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

/// Which marketplace each layer of one catalog generation came from, by
/// layer index.
///
/// `DiscoveredSkill.rootIndex` and `ShadowedCandidate.rootIndex` are both
/// indices into the same ordered layer list, thus one lookup by index
/// serves both the winner's provenance and the shadow message.
internal struct MarketplaceProvenanceIndex: Sendable {
    /// One entry for each layer, in layer order; `nil` for a local layer.
    private let byLayerIndex: [MarketplaceProvenance?]

    /// Creates an index.
    ///
    /// - Parameter byLayerIndex: One entry for each layer, in layer order;
    ///   `nil` for a local layer. The default is no entry, which names no
    ///   marketplace at all.
    init(byLayerIndex: [MarketplaceProvenance?] = []) {
        self.byLayerIndex = byLayerIndex
    }

    /// Gives the marketplace of one layer.
    ///
    /// - Parameter index: The index of the layer.
    /// - Returns: The marketplace, or `nil` for a local layer or an index
    ///   that names no layer.
    func provenance(atLayerIndex index: Int) -> MarketplaceProvenance? {
        byLayerIndex.indices.contains(index) ? byLayerIndex[index] : nil
    }
}
