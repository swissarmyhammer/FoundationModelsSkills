# FoundationModelsSkills

[![CI](https://github.com/swissarmyhammer/FoundationModelsSkills/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsSkills/actions/workflows/ci.yml)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platform: macOS 27+](https://img.shields.io/badge/platform-macOS%2027%2B-lightgrey.svg)

An [agentskills.io](https://agentskills.io)-style skill library for
[FoundationModels](https://developer.apple.com/documentation/foundationmodels):
find, search, and run `SKILL.md` files from a layered dotfolder stack.

A skill is a directory that holds a `SKILL.md` file — YAML frontmatter and a
Markdown body. `SkillsRegistry` finds skills across an ordered set of layer
roots, where the near layer wins, and renders each body through a three-pass
pipeline (`$`-argument substitution, `` !`shell` `` injection, Stencil
templating). One fused tool then shows that catalog to a model, to a `/command`
menu, and to a CLI through the same rendering path.

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
// The session you supply runs the selection tier. Nothing is hardcoded.
let skillsTool = try await SkillsTool.make(
    registry: registry,
    session: { prefix in LanguageModelSession(model: .default, instructions: prefix) })

// A lean root session: one tool, preloaded bodies, no full catalog in context.
let session = LanguageModelSession(
    tools: [skillsTool],
    instructions: Instructions {
        "You use the skills tool to search and run skills from the local library."
        registry.preloadedBodies()
    })
```

`SkillsTool.make` gives an `OperationTool`, which conforms to the
FoundationModels `Tool` protocol — it goes into any standard session with no
adapter. The search tier runs on the session you pass, and this package makes
no session of its own. Omit the `session:` argument and each search uses
keyword retrieval, with no model at all.

[`Examples/skills-demo`](Examples/skills-demo) is the compiled, always-current
version of that example. `swift build` builds it with the library, and the
tests run it as a subprocess.

## Install

macOS 27 or later. The package is not on a registry, thus add it as a git
dependency:

```swift
.package(url: "git@github.com:swissarmyhammer/FoundationModelsSkills.git", branch: "main")
```

## Documentation

- [`docs/operations.md`](docs/operations.md) — the six operations, verb
  aliases, and the visibility table.
- [`docs/security.md`](docs/security.md) — security posture, context
  compaction, and platform limits. Read this before you load skill directories
  that you do not control.
- [`plan.md`](plan.md) — the full design: the layered architecture, each
  resolved decision, and the render-pipeline and resource-operation
  specification.
- [`Examples/skill-library`](Examples/skill-library) — a three-layer fixture
  stack that uses each templating and visibility feature one time. The unit
  tests and the demo load these same directories, thus the documented behavior
  is the tested behavior.

[`docs/development.md`](docs/development.md) records the known deviations from
the plan, for anyone changing this package.
