---
comments:
- actor: claude-code
  id: 01m2zh34td2yzfe1m7mxrfdc5p
  text: |-
    Research, before the code.

    What the Extras revision gives (read in `.build/checkouts/FoundationModelsExtras/Sources/FoundationModelsExtras/`):
    - `FrontmatterDocumentStack<Base, Metadata>` where `Base.Item == String`. Its decode seam is `@Sendable (String) -> Metadata?`, and it gets the raw text between the fences only.
    - `items(in:named:)` gives `[String: Located<FrontmatterDocument<Metadata>>]`, keyed by the child directory name. `FrontmatterDocument` holds `metadata` and `content`.
    - A file that no layer holds, that is unreadable, or that is not UTF-8 text has no entry at all. That is the hook for the `.skip` diagnostic.

    The plan of the code:
    - `FrontmatterDecoder.MetadataOutcome` is the body-less half: `.decoded(frontmatter:notes:)` or `.skipped(reason:)`. `decode(frontmatter:)` takes the frontmatter text only and always gives a value, thus a failure keeps its message.
    - `FrontmatterDecoder.Outcome.init(metadata:body:)` joins the two halves again. `metadata == nil` gives the empty `SkillFrontmatter` with the whole body, the same as the no-frontmatter-block case today.
    - `SkillsRegistry` builds `FrontmatterDocumentStack(base: DotfolderStack(layers:), decode:)` over the plain stack, not a stenciled one, and reads `items(in: nil, named: "SKILL.md")`.

    One part of the card does not fit, and it is named here before the work starts: `Marketplace/CatalogResolver.rootSkillName()` reads the root `SKILL.md` of a marketplace repository through a `CatalogFileSource`. That source can be a git tree (`GitTreeFileSource`), thus it is not a dotfolder stack and the document stack cannot serve it. It is the last caller of the whole-text route, and it must keep one `FrontmatterDocument.split` call. Acceptance criterion 2 says no file of `Sources/` calls the split. The registry path and the frontmatter path meet it; `Marketplace/` does not.
  timestamp: 2026-09-20T13:46:35.213660+00:00
- actor: claude-code
  id: 01m2zhray72k3k1fd97fc47vam
  text: |-
    The work landed, and these are the decisions.

    - `FrontmatterDecoder.MetadataOutcome` is the body-less half, and `decode(frontmatter:)` is the one entry point. The whitespace-only block still gives the empty `SkillFrontmatter`, thus the behavior of a `---` block with nothing in it does not change.
    - `FrontmatterDecoder.Outcome.init(metadata:body:)` joins the two halves again. `metadata == nil` gives the empty frontmatter with the whole body.
    - `SkillsRegistry.skillDocuments(layers:)` builds `FrontmatterDocumentStack(base: DotfolderStack(layers:), decode:)` and reads `items(in: nil, named: "SKILL.md")` one time for each catalog build. `validate` then takes the document, not the URL.
    - The `.skip` text is now exactly `SKILL.md could not be read`, with no system error after it. The card allows that.
    - `decode(text:)` and `SkillValidator.validate(discovered:text:)` are deleted. The test target got one shared route for a whole text, `FixtureLibrary.decodeOutcome(text:)` and `FixtureLibrary.decodedSkill(text:)`, thus the five suites that held a fixture text keep one copy of the two steps, not five.
    - Each of those suites now unwraps with `try #require`, not with `guard case ... else { Issue.record; return }`. A case that cannot run must fail, never pass in silence.
    - Three new cases: the empty frontmatter block, the two halves that join again, and a skill that two layers give (the higher layer gives both the description and the body). One more case for a `SKILL.md` whose bytes are no UTF-8 text: one `.skip` diagnostic, no catalog entry.

    What did not work, so that the next agent does not try it again: `CatalogResolver` cannot go through the document stack. Its `CatalogFileSource` can be a git tree (`GitTreeFileSource`), which is no directory and thus no dotfolder stack. Only that one call of `FrontmatterDocument.split` is left in `Sources/`, and the guard suite filters `Marketplace/` out of its walk. Card ^4e1wajh removes the filter after card ^xd7yjf8 deletes the folder.
  timestamp: 2026-09-20T13:58:09.607720+00:00
- actor: claude-code
  id: 01m2zhrkkp593fddb712v6tj6r
  text: |-
    ### implement — changed
    - evidence: 12 files — Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift, Sources/FoundationModelsSkills/Frontmatter/SkillFrontmatter.swift, Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift, Sources/FoundationModelsSkills/Validation/SkillValidator.swift, Sources/FoundationModelsSkills/Listing/SkillListing.swift, Sources/FoundationModelsSkills/Marketplace/CatalogResolver.swift, Tests/FoundationModelsSkillsTests/FixtureLibrary.swift, Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift, Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift, Tests/FoundationModelsSkillsTests/SkillValidatorTests.swift, Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift (new), plus the four fixture-text call sites (SkillListingTests, ShellInjectionTests, FixtureLibraryTests, StencilPassTests, ArgumentSubstitutionTests). `swift build --build-tests`: 0 warnings, 0 errors. `swift test`: 803 tests in 65 suites, 0 failures.
    - gap: acceptance criterion 2 is open. `Marketplace/CatalogResolver.rootSkillName()` keeps one `FrontmatterDocument.split` call, because a `CatalogFileSource` can be a git tree and thus no dotfolder stack. The guard suite filters `Marketplace/` out of its walk, and it names the reason.
    - next: review. Card ^4e1wajh closes the gap after card ^xd7yjf8 deletes `Marketplace/`.
  timestamp: 2026-09-20T13:58:18.486128+00:00
- actor: claude-code
  id: 01m2zhy5enx7mqf4v1mga7t4bk
  text: |-
    ### test — green
    - evidence: `swift package clean && swift build --build-tests` — 0 errors, 0 warnings; `swift test` — 803 tests in 65 suites passed, 0 failed, 0 skipped
    - next: ready for review
  timestamp: 2026-09-20T14:01:20.597720+00:00
position_column: doing
position_ordinal: '80'
title: Read SKILL.md through the Extras FrontmatterDocumentStack; the registry opens no file
---
## What

The boundary rule (the user, 2026-09-20): the raw work of loading lives in `FoundationModelsExtras` (the file system, the layers, Stencil, the frontmatter split). This package keeps only the work of the skill schema.

`SkillsRegistry.validate(discovered:marketplaces:diagnostics:)` (`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift`) reads the winning `SKILL.md` with `String(contentsOf:encoding:)`. It is the only raw read of `SKILL.md` in this package. `FrontmatterDecoder.decode(text:)` (`Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift`) then calls `FrontmatterDocument.split(text:)` itself. Extras has a facade for both steps, `FrontmatterDocumentStack`, and this package does not use it. The API is on the pinned Extras revision now; no Extras card is necessary.

1. **Read and split through the stack.** Build `FrontmatterDocumentStack(base: stack, decode:)` over the plain `DotfolderStack` of the layer plan, not over a stenciled stack: the split runs on the raw text, because this package renders the body and each metadata field later, with the arguments of the call. `items(in: nil, named: SkillDiscovery.skillFileName)` gives each `<id>/SKILL.md` with its layer, its URL, its decoded metadata and its body.
2. **The decoder is the schema work, and it stays here.** The seam of the stack is `(String) -> Metadata?`, and it gets the frontmatter text only, never the body. Thus `Metadata` is the half of the outcome that has no body: the decoded `SkillFrontmatter` with its notes, or the skip reason with its message. Name it, for example `FrontmatterDecoder.MetadataOutcome`. The stack decoder does the Yams decode, the quoting-fallback retry and the notes, and it always gives a value, so a failure keeps its message. The registry then makes `DecodedSkill` from that value and from `FrontmatterDocument.content` (the body). `metadata == nil` then means only "the file has no frontmatter block"; map it to the outcome that the decoder gives for that case today.
3. `FrontmatterDecoder` loses its call of `FrontmatterDocument.split`. Its entry point takes the frontmatter text only and gives the body-less outcome of step 2. Delete `decode(text:)` when no caller is left, and move its tests to the new entry point plus the assembly in the registry. Rewrite each doc comment of `FrontmatterDecoder.swift` and `SkillFrontmatter.swift` that names `FrontmatterDocument.split`: the last card of this group walks comments too.
4. **The unreadable file.** The stack gives no entry for a winning copy that is not UTF-8 text, and discovery still lists that skill (it uses `locate`). Keep the `.skip` diagnostic "SKILL.md could not be read" for a discovered skill that has no entry in the stack result. Its text can lose the system error message.
5. `SkillDiscovery` does not change: it is already on `childDirectories()` and `locate(_:)` of the stack.

## Acceptance Criteria

- [x] `SkillsRegistry.swift` has no `String(contentsOf:` call, and no file of `Sources/FoundationModelsSkills/` outside `Marketplace/` reads `SKILL.md` itself.
- [ ] No file of `Sources/FoundationModelsSkills/` calls `FrontmatterDocument.split`. **Open.** One call is left, in `Marketplace/CatalogResolver.rootSkillName()`. That path reads the root `SKILL.md` of a marketplace repository through a `CatalogFileSource`, which can be a git tree, thus it is no dotfolder stack and the document stack cannot serve it. Card ^xd7yjf8 deletes that folder, and card ^4e1wajh then deletes the exception of the guard suite.
- [x] The catalog, each diagnostic and each decoder note are the same as before for the fixture library `Examples/skill-library`.
- [x] A `SKILL.md` with the unquoted-colon `description:` mistake still decodes through the quoting fallback, with its note.
- [x] A `SKILL.md` that is not UTF-8 text gives one `.skip` diagnostic and no catalog entry.
- [x] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [x] `Tests/FoundationModelsSkillsTests/FrontmatterDecoderTests.swift`: the cases pass through the new entry point (frontmatter text only), with the same frontmatter values, notes and skip reasons.
- [x] `Tests/FoundationModelsSkillsTests/SkillsRegistryTests.swift`: a skill that two layers give takes its metadata and its body from the higher `SKILL.md`; the unreadable `SKILL.md` case gives the `.skip` diagnostic.
- [x] `Tests/FoundationModelsSkillsTests/NoFrontmatterSplitTests.swift`: no file under `Sources/`, outside `Marketplace/`, names `FrontmatterDocument.split`, and `Registry/` does not name `String(contentsOf`.
- [x] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Record each decision in a comment on this card. Do not ask the user about an implementation detail.

#loading-boundary #skills