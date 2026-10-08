import Marketplace

/// Which marketplace each layer of one catalog generation came from, by
/// layer index.
///
/// `DiscoveredSkill.rootIndex` and `ContributingDirectory.rootIndex` are both
/// indices into the same ordered layer list, thus one lookup by index
/// serves the winner's provenance and the shadow message.
///
/// The marketplace itself lives in the `Marketplace` module of
/// `FoundationModelsExtras`. This index is the skill knowledge around it: it
/// ties one ``MarketplaceProvenance`` to the layer that the discovery of this
/// package found a skill in.
internal struct MarketplaceProvenanceIndex: Sendable {
    /// What one marketplace layer carries: where its skills came from.
    internal struct Entry: Sendable {
        /// Where the skills of the layer came from.
        let provenance: MarketplaceProvenance
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

    /// Gives the entry of one layer.
    ///
    /// - Parameter index: The index of the layer.
    /// - Returns: The entry, or `nil` for a local layer or an index that
    ///   names no layer.
    private func entry(atLayerIndex index: Int) -> Entry? {
        byLayerIndex.indices.contains(index) ? byLayerIndex[index] : nil
    }
}
