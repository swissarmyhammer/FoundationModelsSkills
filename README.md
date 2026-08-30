# FoundationModelsSkills

An [agentskills.io](https://agentskills.io)-style skill library for
[FoundationModels](https://developer.apple.com/documentation/foundationmodels):
find, search, and run `SKILL.md` files from a layered dotfolder stack.

A skill is a directory that contains a `SKILL.md` file (YAML frontmatter
plus a Markdown body). `SkillsRegistry` finds skills across an ordered set
of layer roots — the near layer wins. It renders each body through a
three-pass pipeline (`$`-argument substitution, `` !`shell` `` injection,
Stencil templating), and it shows the catalog to a model, a `/command`
menu, and a CLI through the same rendering path. macOS 27 or later is
necessary.

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

`SkillsTool.make` gives an `OperationTool`. That type conforms to the
FoundationModels `Tool` protocol, thus it goes into any standard session with
no adapter. The search tier uses the session that you give it, and this
package makes no session of its own. A host that wants no model does not give
the `session:` argument. Each search then uses keyword retrieval only.

The compiled, always-current version of this example is
[`Examples/skills-demo`](Examples/skills-demo). `swift build` builds it
with the library, and the tests run it as a subprocess.

## Install

The package is not on a registry. Add it as a git dependency:

```swift
.package(url: "git@github.com:swissarmyhammer/FoundationModelsSkills.git", branch: "main")
```

## Documentation

- [`docs/operations.md`](docs/operations.md) — the six operations, verb
  aliases, and the visibility table.
- [`docs/security.md`](docs/security.md) — security posture, context
  compaction, and platform limits. Read this before you load skill
  directories that you do not control.
- [`docs/development.md`](docs/development.md) — known deviations from
  the plan, and development notes.
- [`plan.md`](plan.md) — the full design: the layered architecture, each
  resolved decision, and the render-pipeline and resource-operation
  specification.
- [`Examples/skill-library`](Examples/skill-library) — a three-layer
  fixture stack that uses each templating and visibility feature one
  time. The unit tests and the demo load these same directories, thus
  the documented behavior is the tested behavior.
