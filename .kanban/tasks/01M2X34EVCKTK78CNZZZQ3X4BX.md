---
depends_on:
- 01M2X2BXEPERA9BG5CGCW1Z0Q7
position_column: todo
position_ordinal: '8680'
title: Read and render through the Extras stack; this package opens no file
---
## What

This package crosses the layers of `FoundationModelsExtras` two times for each skill: it opens `SKILL.md` with `FileManager` (`Sources/FoundationModelsSkills/Registry/SkillsRegistry.swift:674`), it calls `FrontmatterDocument.split` by itself, it runs two render passes of its own, and it goes to `TemplateEngine` only at the end. That order is wrong. The correct order of the layers is:

```
1  DotfolderStack     find the file in the combined view, and say which layer gave it
2  document facade    read the path, split the frontmatter from the body, keep the layer
3  render facade      render: arguments, shell, Stencil; the trust and the limits from the layer
4  this package       YAML to SkillFrontmatter, the skill rules, the catalog, the operations
```

Extras gives layers 1 to 3 (cards ^40n54dh, ^qpfymzm and ^cwm3mqt on that board). This card makes this package use them, and deletes what is now a copy.

**The rule: this package never opens a file.** `FileManager`, `String(contentsOf:)` and `Data(contentsOf:)` must not be in `Sources/FoundationModelsSkills/`, with one exception that is named below. Each read of a skill file goes through `DotfolderStacking`. The stack resolves the symbolic links and refuses a path that leaves its layer root, thus the confinement check of this package goes away with the file access.

The one exception is the marketplace cache and the git transport (`Sources/FoundationModelsSkills/Marketplace/`). That code **makes** a layer root: it writes the snapshot, the locks and the state file. It is not a reader of the stack. State this boundary in the comment of that directory.

1. **Read.** `SkillsRegistry` stops its `String(contentsOf:)` call. It uses `stack.documents(in: nil, named: "SKILL.md")` to get each `<id>/SKILL.md` with its layer.
2. **Split.** `FrontmatterDecoder` stops its call of `FrontmatterDocument.split`. It takes the `frontmatterText` and the `body` of the document, and it keeps only its own work: the Yams decode into `SkillFrontmatter`, the quoting-fallback retry, and the notes.
3. **Render.** Delete `Render/QuarantinedText.swift`, `Render/ArgumentSubstitution.swift`, `Render/ShellInjection.swift`, `Render/StencilPass.swift` and `Render/RenderPipeline.swift` from this package. Each render goes to the Extras facade with a context and a policy.
4. **The policy comes from this package**: the `RenderPolicy` flags and the marketplace grants of the winning layer make the policy of the call. The trust does not come from this package; the facade takes it from the layer.
5. `RenderPolicy` stays public here, because a host sets it on `SkillsRegistry`.

## Acceptance Criteria

- [ ] No file of `Sources/FoundationModelsSkills/`, outside `Marketplace/`, names `FileManager`, `String(contentsOf:)` or `Data(contentsOf:)`.
- [ ] No file of `Sources/FoundationModelsSkills/` names `FrontmatterDocument`, `TemplateEngine` or Stencil.
- [ ] The `Render/` directory holds no pass and no pipeline.
- [ ] The rendered text of a skill does not change: the tests of the render that are there now pass, with the calls changed only.
- [ ] A skill from a `.defaults` layer still renders trusted; each other layer renders untrusted.
- [ ] The shell stays off when `RenderPolicy.isShellExecutionDisabled` is true, or when the grants of the marketplace do not give the shell.
- [ ] `swift build --build-tests` gives 0 warnings, and `swift test` is green.

## Tests

- [ ] A new test walks `Sources/` and fails when a file outside `Marketplace/` names `FileManager`, `String(contentsOf:)` or `Data(contentsOf:)`, and when any file names Stencil or `TemplateEngine`.
- [ ] `Tests/FoundationModelsSkillsTests/HotReloadTests.swift` and the render tests that are there now give the same text as before.
- [ ] `Tests/FoundationModelsSkillsTests/ShellInjectionTests.swift` (or the test that replaces it): the policy of this package turns the shell off through the facade.
- [ ] `swift test` — all tests pass, 0 failures.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

#dotfolder-overlay #skills #cross-repo