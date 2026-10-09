import Marketplace

/// The shape of a skill marketplace tree, as this package names it.
///
/// The `Marketplace` module of `FoundationModelsExtras` knows no skill: it
/// reads whichever document the host names. This package names `SKILL.md`,
/// and it names the same excluded folders and the same partials folder that
/// ``SkillDiscovery`` reads on this computer. Thus a marketplace snapshot and
/// a local layer hold the same shape, and one skill moves between the two
/// with no edit.
///
/// The value stands one time, here. The registry and a host both read it,
/// thus the two of them cannot name a different document.
///
/// ```swift
/// let store = MarketplaceStore(
///     sources: [MarketplaceSource("github:acme/team-skills")],
///     layout: SkillMarketplaceLayout.skills)
/// ```
public enum SkillMarketplaceLayout {
    /// The layout of a skill marketplace: `SKILL.md` marks a skill folder,
    /// the scan reads into no excluded folder, and `_partials` holds the
    /// partials of a skill.
    public static let skills = MarketplaceLayout(
        documentName: SkillDiscovery.skillFileName,
        excludedDirectoryNames: SkillDiscovery.excludedDirectoryNames,
        partialsDirectoryName: MarketplaceLayout.defaultPartialsDirectoryName)
}
