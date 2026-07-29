// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Single source of truth for the package/product/target name -- avoids
// repeating the literal across the package, product, target, and test-target
// declarations below.
let packageName = "FoundationModelsSkills"

// Shared product dependencies needed by both the library target and its test
// target -- factored out so the two lists can't drift out of sync.
let commonDependencies: [Target.Dependency] = [
    .product(name: "FoundationModelsExtras", package: "FoundationModelsExtras"),
    // Despite `FoundationModelsOperationTool`'s own manifest
    // declaring its package identity as `FoundationModelsOperations`
    // (its `Package(name:)`), a *path* dependency's identity is
    // resolved by SwiftPM from the directory name, not the
    // manifest's declared name -- confirmed empirically: `package:
    // "FoundationModelsOperations"` fails to resolve with "unknown
    // package", listing `FoundationModelsOperationTool` as the
    // valid identity for this path. This is the opposite of this
    // family's existing *remote* git dependencies on the same
    // package (e.g. FoundationModelsShelltool,
    // FoundationModelsFileTool), which also key off
    // `FoundationModelsOperationTool` -- there, because that is
    // the URL's last path component.
    .product(name: "Operations", package: "FoundationModelsOperationTool"),
    .product(name: "FoundationModelsMetadataRegistry", package: "FoundationModelsMetadataRegistry"),
    .product(name: "Yams", package: "Yams"),
]

/// The `FoundationModelsSkills` SwiftPM package definition.
///
/// Declares the single library target (plan.md decision #17: no target
/// split, layering is conceptual, not modular) that will host
/// agentskills.io-style skill discovery, search, and invocation as a fused
/// `OperationTool` on top of `FoundationModelsExtras` (dotfolder stack,
/// templating), `FoundationModelsOperationTool` (`@Operation` macro fusion),
/// and `FoundationModelsMetadataRegistry` (hybrid search) -- see plan.md §3
/// for the full layered architecture this package builds toward.
let package = Package(
    name: packageName,
    // macOS 27+, no pre-27 fallback: the strictest floor in this package's own
    // dependency graph. `FoundationModelsMetadataRegistry` depends on
    // `FoundationModelsRouter`, which commits to macOS 27 / FoundationModels v2
    // with no pre-27 fallback; that floor is inherited package-wide (plan.md
    // decision #26, matching decision #17's "no target split" stance -- the
    // whole package carries the Registry -> Router dependency and its floor).
    // No `.iOS(...)` platform is declared here -- see the doc comment on the
    // `FoundationModelsSkills` namespace enum
    // (`Sources/FoundationModelsSkills/FoundationModelsSkills.swift`) for why.
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        // The single library product (plan.md decision #17: one SwiftPM
        // target; layering (§3) is conceptual -- by type, not module).
        .library(name: packageName, targets: [packageName]),
    ],
    dependencies: [
        // Layers 1-2 substrate: `DotfolderStack`, `FrontmatterDocument`,
        // `TemplateEngine` (plan.md §3, decision #29 -- imported, not built
        // here).
        .package(path: "../FoundationModelsExtras"),
        // FM tool fusion: `OperationTool`/`@Operation` macro machinery
        // (decision #20). Only the `Operations` product is needed by this
        // task; `OperationsCLI` joins once the CLI driver task lands (plan.md
        // §7.2).
        .package(path: "../FoundationModelsOperationTool"),
        // `SkillSearchAgent`'s hybrid retrieval (BM25 + trigram + cosine ->
        // RRF) and Router-backed selection session, via
        // `MetadataSearcher<SkillMetadata>` (plan.md decision #26).
        .package(path: "../FoundationModelsMetadataRegistry"),
        // YAML frontmatter decoding stays ours, with Yams, per Extras' no-YAML
        // rule (plan.md decision #29). Pinned `exact:`, matching
        // `FoundationModelsExtras`' own Yams pin.
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: commonDependencies
        ),
        .testTarget(
            name: "FoundationModelsSkillsTests",
            dependencies: [.byName(name: packageName)] + commonDependencies
        ),
    ]
)
