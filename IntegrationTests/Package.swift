// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The integration test target lives in this nested package, and the root
// package declares no integration target. The package boundary separates the
// unit tests from the integration tests (Shape 2 of the org test contract,
// docs/swift-ci.md of swissarmyhammer/workflows):
//
// - `swift test` at the repository root runs ONLY the unit tests, by
//   construction: no `--skip`, no name regex, and no environment variable.
// - `swift test --package-path IntegrationTests` runs the integration tests.
//
// The real dependency of these tests is the on-device Apple Intelligence
// model. Each test has its own model-availability gate, thus a host with no
// such model reports the test as skipped, never as a failure.

/// The name of the package under test, of its library product and of the root
/// directory that this package depends on by path.
let skillsPackage = "FoundationModelsSkills"

/// The name of the metadata registry package: the tests build a `.selection`
/// `MetadataSearcher` with its `SelectionConfig`. The URL is the URL of the
/// root manifest, thus the package identity stays one.
let registryPackage = "FoundationModelsMetadataRegistry"

let package = Package(
    name: "IntegrationTests",
    // macOS 27, the same floor as the root package.
    platforms: [
        .macOS("27.0"),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "git@github.com:swissarmyhammer/\(registryPackage).git", branch: "main"),
    ],
    targets: [
        .testTarget(
            name: "\(skillsPackage)IntegrationTests",
            dependencies: [
                .product(name: skillsPackage, package: skillsPackage),
                .product(name: registryPackage, package: registryPackage),
            ],
            path: "Tests/\(skillsPackage)IntegrationTests"
        ),
    ]
)
