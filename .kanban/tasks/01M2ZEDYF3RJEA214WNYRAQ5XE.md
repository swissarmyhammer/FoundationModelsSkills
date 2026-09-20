---
depends_on:
- 01M2X2J679TGA1ENB64G9JT4SQ
- 01M2ZEDY8TKCMFQJA8RWHTH0PD
position_column: todo
position_ordinal: '9880'
title: 'Resources: take the execute bit and the shebang bytes from the Extras stack'
---
## What

After the card ^g9jt4sq, the resource operations still make three raw file calls: the execute bit of a `list resource` row, the `chmod +x` gate of `run script`, and the two-byte shebang read of `run script`. This card needs the Extras card `^00nmjzg` on the `FoundationModelsExtras` board, which adds `isExecutable(_:)` to the stack.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no `isExecutable` requirement on `DotfolderStacking`, stop, write a comment on this card, and leave it in To Do.
2. **The execute bit of a row.** `ListResource` (`Sources/FoundationModelsSkills/Resources/ListResource.swift`) takes the `executable` column from `isExecutable(_:)` of the overlay stack. Delete the one `resourceValues(forKeys:)` call that the card ^g9jt4sq left for it.
3. **The `chmod +x` gate.** `RunScript.executabilityIssue` (`Sources/FoundationModelsSkills/Resources/RunScript.swift`) takes its answer from the same call. Delete `FileManager.default.isExecutableFile`.
4. **The shebang.** `RunScript.hasShebang` reads two bytes with `FileHandle`. Read them with `data(_:in: 0..<2)` of the overlay stack.

## Acceptance Criteria

- [ ] `ListResource.swift` and `RunScript.swift` name no `FileManager`, no `FileHandle` and no `resourceValues`.
- [ ] `list resource` gives the same `executable` value as before for a `0755` file and for a `0644` file.
- [ ] `run script` gives the same `chmod +x` corrective and the same shebang corrective as before.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/RunScriptTests.swift`: the not-executable case and the no-shebang case pass with no change of their expected texts.
- [ ] `Tests/FoundationModelsSkillsTests/ResourceOpsTests.swift`: the `executable` column for a script that only a lower layer holds, and for the higher copy of a path that two layers hold with different modes.
- [ ] A source scan test: `Resources/ListResource.swift` and `Resources/RunScript.swift` name none of `FileManager`, `FileHandle`, `resourceValues`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills #blocked-upstream
