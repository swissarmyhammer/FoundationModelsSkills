import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsSkills
import Operations
import Testing
import Yams

/// Placeholder scaffold test proving the library target and all four
/// dependencies build, link, and are importable from the test target.
///
/// Proves `FoundationModelsSkills` and its four dependencies --
/// `FoundationModelsExtras`, `Operations` (package `FoundationModelsOperations`),
/// `FoundationModelsMetadataRegistry`, and `Yams` -- all resolve, build, and
/// link from a Swift Testing test target (plan.md §3/§17). The imports above
/// are the real assertion, exactly like the sibling packages' own scaffold
/// smoke tests: this only compiles if every dependency is wired correctly in
/// `Package.swift`. Replaced by real tests as each layer lands in subsequent
/// tasks.
@Test func moduleAndDependenciesImportCleanly() {
    #expect(Bool(true))
}
