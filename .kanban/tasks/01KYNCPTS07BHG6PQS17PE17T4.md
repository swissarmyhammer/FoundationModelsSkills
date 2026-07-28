---
position_column: doing
position_ordinal: '80'
title: Scaffold Package.swift and empty target structure
---
## What
Create the SwiftPM package skeleton per plan.md §3/§17 (single target, conceptual layering).

- `Package.swift`: package `FoundationModelsSkills`; one library target `FoundationModelsSkills`; test target `FoundationModelsSkillsTests`. Platform floor: match the strictest sibling (`FoundationModelsMetadataRegistry` → `FoundationModelsRouter`, macOS 27 per plan decision #26; read the sibling `Package.swift` files for the exact `.macOS(...)` value).
- Path dependencies on siblings: `../FoundationModelsExtras` (product `FoundationModelsExtras`), `../FoundationModelsOperationTool` (package `FoundationModelsOperations`, product `Operations`; product `OperationsCLI` will be needed later for the CLI task), `../FoundationModelsMetadataRegistry` (read its `Package.swift` for the product name — it is built with variables). Add `Yams` (registry owns YAML decoding, decision #29).
- `Sources/FoundationModelsSkills/FoundationModelsSkills.swift`: namespace enum + doc header.
- **iOS posture (plan §1/§8)**: the plan mandates a graceful iOS "unavailable on platform" stub. Check whether every sibling dependency declares iOS support. If they all do, declare the matching `.iOS(...)` floor and add `#if os(iOS)` guards so shell/script code paths are compiled out (later tasks keep the guards); if ANY dependency is macOS-only, the stub is impossible at the manifest level — record the deviation in a doc comment on the namespace enum stating plainly: iOS unsupported because <dependency> is macOS-only. Either way the outcome is explicit in code, not silently dropped.
- `Tests/FoundationModelsSkillsTests/PackageSmokeTests.swift`: one Swift Testing test that imports the module and each dependency (`FoundationModelsExtras`, `Operations`, the MetadataRegistry product, `Yams`).

## Acceptance Criteria
- [ ] `swift build` succeeds from a clean checkout
- [ ] `swift test` runs the smoke test green
- [ ] All four dependencies are importable from the test target
- [ ] The iOS posture decision (stub or documented deviation) is present in code per the rule above

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/PackageSmokeTests.swift` — imports compile, trivial assertion passes
- [ ] Run `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.