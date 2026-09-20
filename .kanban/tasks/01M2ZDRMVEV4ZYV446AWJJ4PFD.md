---
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
- 01M2XD7YJF87V9PF0EPSG5CF2N
position_column: todo
position_ordinal: '9480'
title: 'Resources: take the execute bit and the confinement from Extras; delete the local PathConfinement and the stack shim'
---
## What

After the card ^g9jt4sq, the resource operations still hold four pieces of raw file work, and two shims for gaps of Extras. This card removes them. It needs the Extras card `^00nmjzg` on the `FoundationModelsExtras` board ("Close two DotfolderStack gaps ...": a public `DotfolderStack.init(layers:)` and `isExecutable(_:)` on the stack).

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no `isExecutable` requirement on `DotfolderStacking`, stop, write a comment on this card, and leave it in To Do.
2. **The execute bit.** `ListResource` takes the `executable` column from `isExecutable(_:)` of the stack; delete the `resourceValues(forKeys:)` call that the card ^g9jt4sq left. `RunScript.executabilityIssue` (`Sources/FoundationModelsSkills/Resources/RunScript.swift`) takes the `chmod +x` gate from the same call; delete `FileManager.default.isExecutableFile`.
3. **The shebang.** `RunScript.hasShebang` reads two bytes with `FileHandle`. Read them with `data(_:in: 0..<2)` of the stack.
4. **Delete the local `PathConfinement`** (`Sources/FoundationModelsSkills/Resources/PathConfinement.swift`). It is a copy of the rule that Extras holds, and the stack applies that rule on each lookup. `SkillOverlay.resolve(_:)` takes the winning copy from the stack (`urls()` or `nearest`-shaped lookup of the overlay stack), not from `winningCopy(relativePath:in:)`. Two things are not raw file work, and they stay in this package as pure string functions in `ResourceSupport.swift`: the check of a well-formed relative path (empty, leading `/`, leading `~`, a `..` component), and the text of the denied corrective. To tell "the path leaves the skill" from "the file is not there" for the corrective, use the public `PathConfinement.isConfined(_:to:)` of Extras. **Caution:** this module re-exports Extras, and the local `internal enum PathConfinement` wins the name today. When the local file goes, each call site binds to the Extras type, which has only `isConfined(_:to:)`. Change each call site in the same commit. The `Marketplace/` folder also called the local type; the card ^sg5cf2n deletes that folder first, thus this card depends on it.
5. **Delete the shim** `Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift`. Each caller (`SkillDiscovery`, `StencilPass`, `SkillOverlay`) uses the public `DotfolderStack(layers:)` of Extras.
6. Move `Tests/FoundationModelsSkillsTests/PathConfinementTests.swift`: the cases of the symbolic link rule are covered in Extras; keep here only the cases of the well-formed path check and of the corrective texts, against their new home.

## Acceptance Criteria

- [ ] No file under `Sources/FoundationModelsSkills/Resources/` names `FileManager`, `FileHandle` or `resourceValues`.
- [ ] `Resources/PathConfinement.swift` and `Discovery/DotfolderStack+Layers.swift` do not exist.
- [ ] `list resource` gives the same `executable` value as before for a `0755` file and for a `0644` file.
- [ ] `run script` gives the same `chmod +x` corrective and the same shebang corrective as before.
- [ ] A path that leaves the skill through `..` or through a symbolic link gives the denied corrective, and a missing file gives the not-found corrective, as before.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: the not-executable case, the no-shebang case and the confinement case pass with no change of their expected texts.
- [ ] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: the `executable` column for a script of a lower layer and for the higher copy of a path that two layers hold.
- [ ] `Tests/FoundationModelsSkillsTests/ResourceIDLookupTests.swift` (or a new `ResourcePathRulesTests.swift`): the well-formed path check, as a table.
- [ ] A source scan test: no file under `Sources/FoundationModelsSkills/Resources/` names `FileManager`, `FileHandle` or `resourceValues`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills #blocked-upstream
