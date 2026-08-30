// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Single source of truth for the package/product/target name -- avoids
// repeating the literal across the package, product, target, and test-target
// declarations below.
let packageName = "FoundationModelsSkills"
let testTargetName = packageName + "Tests"

/// The GitHub organization URL base the swissarmyhammer-family sibling
/// dependencies resolve under.
///
/// Covers `FoundationModelsExtras` and `FoundationModelsMetadataRegistry` --
/// extracted so the org lives in one place instead of dependency entries
/// that could silently drift.
/// Every sibling is wired as a *remote* dependency (`main` branch), never a
/// local `path:` one, matching the family convention (e.g.
/// `FoundationModelsMetadataRegistry` reaches `FoundationModelsRanker` the
/// same way) so this package's CI can use the family's shared `swift-ci.yaml`
/// reusable workflow, which only checks out the calling repo -- a `path:`
/// dependency on an uncommitted sibling checkout would not exist there. It
/// also keeps the SwiftPM "Conflicting identity" warning away: that warning
/// comes as soon as one package is reached by path here and by URL from
/// anywhere else in the graph, and a remote reference here can never make
/// that pair.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// Shared product dependencies needed by both the library target and its test
/// target -- factored out so the two lists can't drift out of sync.
let commonDependencies: [Target.Dependency] = [
    .product(name: "FoundationModelsExtras", package: "FoundationModelsExtras"),
    // FM tool fusion: `OperationTool`/`@Operation` macro machinery. The
    // Operations capability moved into the Extras package on 2026-08-29
    // (the FoundationModelsOperationTool repository is retired), so these
    // two products resolve from `FoundationModelsExtras` now.
    .product(name: "Operations", package: "FoundationModelsExtras"),
    // Dual-use CLI driver (plan.md §7.2): assembles the same fused
    // `OperationTool` into an ArgumentParser command tree for `SkillsCLI`.
    .product(name: "OperationsCLI", package: "FoundationModelsExtras"),
    .product(name: "FoundationModelsMetadataRegistry", package: "FoundationModelsMetadataRegistry"),
    .product(name: "Yams", package: "Yams"),
]

/// The `FoundationModelsSkills` SwiftPM package definition.
///
/// Declares the single library target (plan.md decision #17: no target
/// split, layering is conceptual, not modular) that will host
/// agentskills.io-style skill discovery, search, and invocation as a fused
/// `OperationTool` on top of `FoundationModelsExtras` (dotfolder stack,
/// templating, and the `Operations` `@Operation` macro fusion) and
/// `FoundationModelsMetadataRegistry` (hybrid search) -- see plan.md §3
/// for the full layered architecture this package builds toward.
let package = Package(
    name: packageName,
    // macOS 27+, no pre-27 fallback: the strictest floor in this package's own
    // dependency graph. `FoundationModelsExtras` declares macOS 27, because
    // FoundationModels v2 needs macOS 27 and there is no pre-27 fallback;
    // `FoundationModelsMetadataRegistry` declares the same floor. It is
    // inherited package-wide (plan.md decision #26, matching decision #17's
    // "no target split" stance -- one target carries every dependency, thus it
    // carries the strictest floor of all of them).
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
        // here) -- plus, since 2026-08-29, the `Operations` /
        // `OperationsCLI` modules: `OperationTool`/`@Operation` macro
        // fusion (decision #20) and `OperationCLIDriver` for the dual-use
        // CLI (plan.md §7.2).
        .package(url: "\(swissArmyHammerOrg)FoundationModelsExtras.git", branch: "main"),
        // `SkillSearchAgent`'s hybrid retrieval (BM25 + trigram + cosine ->
        // RRF) and its `AgentSession`-backed selection session -- a plain
        // `LanguageModelSession` conforms to `AgentSession` -- via
        // `MetadataSearcher<SkillMetadata>` (plan.md decision #26).
        .package(url: "\(swissArmyHammerOrg)FoundationModelsMetadataRegistry.git", branch: "main"),
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
        // The §11 dual-use worked example: CLI, `--chat`, and `--watch` modes
        // over the checked-in `Examples/skill-library` fixture stack. Lives
        // in the root manifest (not a nested example package) so one `swift
        // build` covers library and demo alike.
        .executableTarget(
            name: "skills-demo",
            dependencies: [.byName(name: packageName)] + commonDependencies,
            path: "Examples/skills-demo"
        ),
        .testTarget(
            name: testTargetName,
            dependencies: [.byName(name: packageName)] + commonDependencies
        ),
    ]
)
