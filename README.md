# FoundationModelsSkills

[![CI](https://github.com/swissarmyhammer/FoundationModelsSkills/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsSkills/actions/workflows/ci.yml)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platform: macOS 27+](https://img.shields.io/badge/platform-macOS%2027%2B-lightgrey.svg)

An [agentskills.io](https://agentskills.io)-style skill library for
[FoundationModels](https://developer.apple.com/documentation/foundationmodels):
find, search, and run `SKILL.md` files from a layered dotfolder stack.

A skill is a directory that holds a `SKILL.md` file — YAML frontmatter and a
Markdown body. `SkillsRegistry` finds skills across an ordered set of layer
roots, and renders each body through a three-pass
pipeline (`$`-argument substitution, `` !`shell` `` injection, Stencil
templating). One fused tool then shows that catalog to a model, to a `/command`
menu, and to a CLI through the same rendering path.

The unit of override is the file. More than one layer can hold the same skill
id, and the skill you get is the combined view of those layer directories: for
each path, the copy in the highest layer that holds it wins, and a file that
only a lower layer holds stays visible. Thus a project layer can override the
`SKILL.md` of a skill, or add one reference file to it, and keep each other
file of the lower layers. `DiscoveredSkill.contributingDirectories` names every
layer directory of an id, lowest precedence first.

```swift
import FoundationModels
import FoundationModelsSkills

// The host selects the layer roots. The usual way is a "skills" dotfolder stack:
let stack = DotfolderStack(
    name: "skills",
    workingDirectory: projectDirectory,
    defaultsDirectory: shippedSkillsURL,
    userDirectory: userConfigURL)
let registry = SkillsRegistry(stack: stack, watch: true)

// One fused tool for the full catalog: search, list, use, resources, scripts.
// The model you supply runs the selection tier. Nothing is hardcoded.
let skillsTool = try await SkillsTool.make(registry: registry, model: SystemLanguageModel.default)

// A lean root session: one tool and the preloaded bodies. Other bodies load on use.
// A body renders its shell commands, thus the render is async: read it first.
let preloaded = await registry.preloadedBodies()
let session = LanguageModelSession(
    tools: [skillsTool],
    instructions: Instructions {
        "You use the skills tool to search and run skills from the local library."
        preloaded
    })
```

`SkillsTool.make` gives a `SkillsCatalogTool`, which conforms to the
FoundationModels `Tool` protocol — it goes into any standard session with no
adapter. The selection tier runs on the model you pass: any FoundationModels
`LanguageModel`, for example `SystemLanguageModel.default` or a `PooledModel`
of FoundationModelsExtras. This package makes no model of its own. Omit the
`model:` argument and each search uses keyword retrieval, with no model at all.
The optional `embedder:` argument takes any `PooledEmbedding`, for example a
`PooledEmbedder`, and adds the cosine signal to the keyword rank.

The tool shows the catalog to the model before it plans. Its description lists
each visible skill with its description, and tells the model to load each skill
that helps with any part of the task with `use skill`. The `id` field of its
schema is an enum of the visible skill ids. Both are fixed when the tool is
made: a skill that a hot reload adds is found by `search skill`, and the next
session gets it in the description and in the enum. `catalogCharacterLimit`
(8,000 characters by default) limits the list. See
[`docs/operations.md`](docs/operations.md).

For each prompt, the selection tier makes a new `LanguageModelSession` on the
model, and the guided generation of that session holds the answer to the
`{"ids": [...]}` shape. The tier drops an id that is not a candidate. If the
selection answer does not decode, or the model throws, the search gives the
keyword rank, and the `skills` call does not fail.

[`Examples/skills-demo`](Examples/skills-demo) is the compiled, always-current
version of that example. `swift build` builds it with the library, and the
tests run it as a subprocess.

## Install

macOS 27 or later. The package is not on a registry, thus add it as a git
dependency:

```swift
.package(url: "git@github.com:swissarmyhammer/FoundationModelsSkills.git", branch: "main")
```

## Migration: `SkillsTool.make` takes a model, not a session

`SkillsTool.make(registry:session:)` is removed. Give a FoundationModels
`LanguageModel` to `SkillsTool.make(registry:model:)`. `SelectionSessionRequest`
is removed, and the `embedder:` argument takes a `PooledEmbedding` in place of
a `TextEmbedding`.

```swift
// Before:
SkillsTool.make(registry: registry, session: { request in
    LanguageModelSession(model: .default, instructions: request.instructions)
})

// After:
SkillsTool.make(registry: registry, model: SystemLanguageModel.default)
```

## Documentation

- [`docs/operations.md`](docs/operations.md) — the six operations, verb
  aliases, and the visibility table.
- [`docs/marketplaces.md`](docs/marketplaces.md) — remote skill marketplaces
  (implemented in FoundationModelsExtras): the sources, the layer order, the
  cache, the checks and the updates, and the `skills marketplace` commands.
- [`docs/security.md`](docs/security.md) — security posture, context
  compaction, and platform limits. Read this before you load skill directories
  that you do not control.
- [`Examples/skill-library`](Examples/skill-library) — a three-layer fixture
  stack that uses each templating and visibility feature one time. The unit
  tests and the demo load these same directories, thus the documented behavior
  is the tested behavior.

[`docs/development.md`](docs/development.md) records the known deviations and
the development rules, for anyone changing this package.
