import FoundationModelsMetadataRegistry

/// Conforms `SkillsRegistry`'s `SkillMetadata` row to
/// `FoundationModelsMetadataRegistry`'s `SearchableMetadata` protocol, so a
/// `MetadataSearcher<SkillMetadata>` can index and retrieve it directly
/// (plan.md §7, §7.1; decision #26).
///
/// `SkillMetadata`'s own `id` already satisfies the protocol's stable-id
/// requirement; only `renderBlock()` is new here.
extension SkillMetadata: SearchableMetadata {
    /// Renders this row to the text block `MetadataSearcher` tokenizes,
    /// trigrams, and embeds: this row's id, its rendered description, and a
    /// parameter summary line.
    ///
    /// Never a skill's full body -- `SkillMetadata` doesn't carry one in the
    /// first place, so this block is body-free by construction, not by an
    /// extra omission rule here.
    ///
    /// - Returns: The rendered search-surface text block.
    public func renderBlock() -> String {
        var lines = [id]
        if !description.isEmpty {
            lines.append(description)
        }
        if !parameters.isEmpty {
            lines.append("Parameters: \(parameters.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
