---
position_column: todo
position_ordinal: '9780'
title: Delete the DotfolderStack(layers:) shim when Extras gives the public initializer
---
## What

`Sources/FoundationModelsSkills/Discovery/DotfolderStack+Layers.swift` is a shim: `extension DotfolderStack { internal init(layers: [Layer]) }`. It exists because `FoundationModelsExtras` had no such initializer. The Extras card `^00nmjzg` on the `FoundationModelsExtras` board adds `public init(layers: [Layer])` with the **same signature**. From the moment this package resolves that revision, each call site sees two initializers with one signature, and the build can stop with an ambiguous use error. Thus this card must land with the first package update that pulls that revision.

Each later card of this board that runs `swift package update FoundationModelsExtras` depends on this card. The card ^sg5cf2n is ready before this one can start, thus it carries the same instruction as a fallback: if its update pulls the public initializer, it deletes the shim in its own commit, and this card then has only its check to do.

1. **Check the upstream first.** Run `swift package update FoundationModelsExtras`. If the resolved revision has no public `DotfolderStack.init(layers:)`, stop, write a comment on this card, and leave it in To Do.
2. Delete `Discovery/DotfolderStack+Layers.swift`. The three callers (`Discovery/SkillDiscovery.swift`, `Render/StencilPass.swift`, `Resources/SkillOverlay.swift`) bind to the public initializer with no change of text.
3. `dotfolder_name`: the public initializer keeps the rule of this package, the highest-precedence `.project` layer (that Extras card states it). Check it with the test that is there now.

## Acceptance Criteria

- [ ] `Discovery/DotfolderStack+Layers.swift` does not exist, and no file of `Sources/FoundationModelsSkills/` declares an initializer on `DotfolderStack`.
- [ ] `Package.resolved` pins an Extras revision that holds the public `DotfolderStack.init(layers:)`.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift`, `SkillOverlayTests.swift` and `StencilPassTests.swift`: each case passes with no change of its expected values; the case "derives from the highest-precedence project layer" is one of them.
- [ ] A source scan test: no file under `Sources/` holds the text `extension DotfolderStack`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills #blocked-upstream
