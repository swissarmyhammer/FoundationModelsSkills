// Re-exports the sibling modules whose types stand in this package's own
// API, so one `import FoundationModelsSkills` is sufficient for a host.
//
// A host must give the fused `SkillsTool` a `MetadataSearcher<SkillMetadata>`
// (`SkillSearchAgent.init(searcher:retrievalFallback:visibilityPredicate:)`) and a set of layer
// roots, which `DotfolderStack` computes. Those two types come from two
// different sibling packages. Without these re-exports, the host must also
// write `import FoundationModelsMetadataRegistry` and
// `import FoundationModelsExtras`. The host must then know which sibling
// package holds the search seam and which one holds the dotfolder stack.
// That knowledge belongs to this package, not to the host: a host that gives
// the tool a standard `LanguageModelSession` must name one module only.
//
// `FoundationModelsMetadataRegistry` itself re-exports
// `FoundationModelsRanker`
// (`Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift`),
// thus the second line below gives a host the whole search and selection
// seam: `MetadataSearcher`, `SearchMode`, `Match`, `SelectionConfig`,
// `AgentSession`, `SelectionTierUnavailable`, `TextEmbedding`,
// `SignalWeights`, and the ungated `extension LanguageModelSession:
// AgentSession` conformance. That conformance is what lets a host pass a
// standard `LanguageModelSession` where an `any AgentSession` is expected.
//
// The first line below gives a host `DotfolderStack`, and with it the rest of
// the Layer 1-2 substrate (`FrontmatterValue`, `QuarantinedText`,
// `SlashCommand`) that this package's own public API already names.
//
// The plain `import` lines in `Search/SkillSearchAgent.swift` and
// `CLI/SkillsCLI.swift` stay as they are. A re-export makes a module's names
// visible to a consumer of this module; it does not make a file's own import
// wrong.
//
// The third line gives a host the marketplace: `MarketplaceStore`,
// `MarketplaceSource`, `MarketplacePolicy`, `MarketplaceConfig`, and the
// provenance that `SkillDiagnostic` already carries. That module is a second
// product of `FoundationModelsExtras`, thus a host that wrote one import
// would otherwise need `import Marketplace` beside it. `docs/marketplaces.md`
// shows the host example with one import only.
@_exported import FoundationModelsExtras
@_exported import FoundationModelsMetadataRegistry
@_exported import Marketplace
