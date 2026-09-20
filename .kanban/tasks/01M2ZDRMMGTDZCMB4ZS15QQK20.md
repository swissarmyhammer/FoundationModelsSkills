---
position_column: todo
position_ordinal: '9380'
title: Read SKILL.md through the Extras FrontmatterDocumentStack; the registry opens no file
---
## What

The boundary rule (the user, 2026-09-20): the raw work of loading lives in `FoundationModelsExtras` (the file system, the layers, Stencil, the frontmatter split). This package keeps only the work of the skill schema.

`SkillsRegistry.validate(discovered:marketplaces:diagnostics:)` (`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`) reads the winning `SKILL.md` with `String(contentsOf:encoding:)`. It is the only raw read of `SKILL.md` in this package. `FrontmatterDecoder.decode(text:)` (`Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift`) then calls `FrontmatterDocument.split(text:)` itself. Extras has a facade for both steps, `FrontmatterDocumentStack`, and this package does not use it. The API is on the pinned Extras revision now; no Extras card is necessary.

1. **Read and split through the stack.** Build `FrontmatterDocumentStack(base: stack, decode:)` over the plain `DotfolderStack` of the layer plan, not over a stenciled stack: the split runs on the raw text, because this package renders the body and each metadata field later, with the arguments of the call. `items(in: nil, named: SkillDiscovery.skillFileName)` gives each `<id>/SKILL.md` with its layer, its URL, its decoded metadata and its body.
2. **The decoder is the schema work, and it stays here.** Give the stack a decoder that takes the raw frontmatter text and gives the `FrontmatterDecoder` outcome: the Yams decode into `SkillFrontmatter`, the quoting-fallback retry, and the notes. The decode of this package never fails without a reason, thus make the `Metadata` type the outcome value (decoded, or failed with its message), so a failure keeps its message. `metadata == nil` then means only "the file has no frontmatter block"; map it to the outcome that the decoder gives for that case today.
3. `FrontmatterDecoder` loses its call of `FrontmatterDocument.split`. It gets an entry point that takes the frontmatter text and the body. Keep `decode(text:)` only if a caller outside the registry still needs it; if no caller does, delete it and move its tests to the new entry point.
4. **The unreadable file.** The stack gives no entry for a winning copy that is not UTF-8 text, and discovery still lists that skill (it uses `locate`). Keep the `.skip` diagnostic "SKILL.md could not be read" for a discovered skill that has no entry in the stack result. Its text can lose the system error message.
5. `SkillDiscovery` does not change: it is already on `childDirectories()` and `locate(_:)` of the stack.

## Acceptance Criteria

- [ ] `SkillsRegistry.swift` has no `String(contentsOf:` call, and no file of `Sources/FoundationModelsSkills/` outside `Marketplace/` reads `SKILL.md` itself.
- [ ] No file of `Sources/FoundationModelsSkills/` calls `FrontmatterDocument.split`.
- [ ] The catalog, each diagnostic and each decoder note are the same as before for the fixture library `Examples/skill-library`.
- [ ] A `SKILL.md` with the unquoted-colon `description:` mistake still decodes through the quoting fallback, with its note.
- [ ] A `SKILL.md` that is not UTF-8 text gives one `.skip` diagnostic and no catalog entry.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] `Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift`: the cases pass through the new entry point (frontmatter text plus body), with the same outcomes and notes.
- [ ] `Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift`: a skill that two layers give takes its metadata and its body from the higher `SKILL.md`; the unreadable `SKILL.md` case gives the `.skip` diagnostic.
- [ ] `Tests/FoundationModelsSkillsTests/SwiftSourceScanTests.swift` (or the source scan suite that exists): no file under `Sources/` names `FrontmatterDocument.split`, and `Registry/SkillsRegistry.swift` does not name `String(contentsOf`.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills
