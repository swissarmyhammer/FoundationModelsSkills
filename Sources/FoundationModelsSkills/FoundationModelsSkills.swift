/// The `FoundationModelsSkills` module's namespace root.
///
/// The module ships the fused FM adapter (Layer 4, `SkillsTool`) and
/// `SkillsRegistry` (Layer 3), built on the `FoundationModelsExtras`
/// substrate (Layers 1-2) and `FoundationModelsMetadataRegistry`'s
/// `MetadataSearcher<SkillMetadata>` (plan.md §3, §9 decision #26). This
/// enum declares no members; it exists to carry the module-level
/// documentation below.
///
/// **iOS posture (plan.md §8): unsupported, not stubbed.** The plan calls for
/// a graceful iOS "unavailable on platform" stub -- `#if os(iOS)` guards
/// compiling out shell/script code paths -- but that stub is only possible
/// at the manifest level when every dependency in the graph itself declares
/// an iOS platform floor, since `Package.swift`'s `platforms:` list is
/// package-wide, not per-target. It is not possible here: two of this
/// package's three sibling dependencies are macOS-only.
///
/// - `FoundationModelsExtras` declares macOS only -- no iOS surface is
///   planned for any of its three pillars (slash commands, `DotfolderStack`,
///   Stencil templating).
/// - `FoundationModelsMetadataRegistry` declares macOS 27 only, inherited
///   from its own `FoundationModelsRouter` dependency, which commits to
///   macOS 27 / FoundationModels v2 with no pre-27 or iOS fallback.
///
/// Only `FoundationModelsOperationTool` (`Operations`) declares both macOS
/// and iOS. Declaring an `.iOS(...)` floor on this package's own manifest
/// would break resolution for the whole package, since two of its three
/// path dependencies can never satisfy it. The deviation is recorded here
/// explicitly, per plan.md §8, rather than silently dropped: **iOS is
/// unsupported** because `FoundationModelsExtras` and
/// `FoundationModelsMetadataRegistry` are macOS-only.
public enum FoundationModelsSkills {}
