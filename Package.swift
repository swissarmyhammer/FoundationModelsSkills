// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FoundationModelsSkills",
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
        .library(name: "FoundationModelsSkills", targets: ["FoundationModelsSkills"]),
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
            name: "FoundationModelsSkills",
            dependencies: [
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
        ),
        .testTarget(
            name: "FoundationModelsSkillsTests",
            dependencies: [
                "FoundationModelsSkills",
                .product(name: "FoundationModelsExtras", package: "FoundationModelsExtras"),
                .product(name: "Operations", package: "FoundationModelsOperationTool"),
                .product(name: "FoundationModelsMetadataRegistry", package: "FoundationModelsMetadataRegistry"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
    ]
)
