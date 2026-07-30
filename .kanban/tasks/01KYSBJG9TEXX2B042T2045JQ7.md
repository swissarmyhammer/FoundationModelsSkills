---
position_column: todo
position_ordinal: '80'
title: Resolve SwiftPM identity conflict for FoundationModelsOperationTool (path vs URL)
---
## What
`swift build` emits two SwiftPM warnings: "Conflicting identity for foundationmodelsoperationtool" — chain (A) `FoundationModelsSkills → ../FoundationModelsMetadataRegistry → github.com/swissarmyhammer/foundationmodelsrouter → github.com/swissarmyhammer/foundationmodelsoperationtool` (URL) vs chain (B) `FoundationModelsSkills → ../FoundationModelsOperationTool` (path). SwiftPM states this "will be escalated to an error in future versions", and it violates the M7 task's zero-warnings acceptance criterion.

Fix at the source of the URL edge: `../FoundationModelsRouter`'s `Package.swift` references OperationTool by GitHub URL while every sibling in this workspace uses path dependencies. Coordinate the sibling change (Router → path dependency on `../FoundationModelsOperationTool`, matching how `FoundationModelsMetadataRegistry` already references Router by path per the chain), or — if Router must keep the URL for standalone use — investigate its existing conditional-dependency seam (it resolves `routerDependencyName` via variables; check whether an env-controlled local/remote switch already exists in the family, and use it). The mlx `Cmlx.bundle` "missing creator for mutated node" warning is toolchain noise from mlx-swift — document it as known/out of scope in the README's development section rather than chasing it.

## Acceptance Criteria
- [ ] `swift build` in this package emits zero "Conflicting identity" warnings
- [ ] `swift test` remains green here AND in `../FoundationModelsRouter` / `../FoundationModelsMetadataRegistry` after the sibling change
- [ ] The mlx bundle warning is either gone or documented as known toolchain noise

## Tests
- [ ] `swift build 2>&1 | grep -c "Conflicting identity"` → 0
- [ ] `swift test` — exit 0

## Workflow
- Use `/tdd` where applicable; this is chiefly manifest coordination — verify by clean-build output.