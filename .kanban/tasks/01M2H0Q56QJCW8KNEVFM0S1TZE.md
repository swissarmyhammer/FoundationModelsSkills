---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Scaffold the ../skills marketplace repository with a test harness and CI
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/skills` (make the folder first). The `/finish` pipeline in FoundationModelsSkills cannot do it: that pipeline commits only in FoundationModelsSkills and never pushes. Steps marked **(operator)** need the network and a person's approval.

marketplace.md §3.1, §3.2, §3.6. Make the new repository `/Users/wballard/github/swissarmyhammer/skills`. It is a sibling of this repository. sah does not change.

Create these files:
- `README.md` — one paragraph: the marketplace name `swissarmyhammer-skills`; the skills are Stencil templates for `FoundationModelsSkills`; how to add the marketplace URL.
- `LICENSE-MIT`, `LICENSE-APACHE` (license `MIT OR Apache-2.0`).
- `.gitignore` — `.build/`, `.swiftpm/`.
- `Package.swift` — swift-tools 6.2, `platforms: [.macOS("27.0")]`, no library product. One test target, `SkillsMarketplaceTests`. It depends on `FoundationModelsSkills` (`git@github.com:swissarmyhammer/FoundationModelsSkills.git`, `branch: "main"`, the same family convention as this repository's `Package.swift`).
- `Tests/SkillsMarketplaceTests/SkillLibraryTests.swift` — finds the repository root from `#filePath`, and builds `SkillsRegistry(roots: [root/skills])` (every root renders untrusted).
- `skills/_partials/.gitkeep`.
- `.github/workflows/ci.yml` — copy the shape of this repository's `.github/workflows/ci.yml`: `uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main`, triggers on push to `main`, on a `v*` tag push, on pull request, and on dispatch, with the same concurrency group. No `test-skip` and no integration inputs.

- [ ] Write the scaffold files and `Package.swift`
- [ ] Write `SkillLibraryTests` with the diagnostics assertion
- [ ] Add the CI workflow
- [ ] `git init -b main` and commit
- [ ] **(operator)** `gh repo create swissarmyhammer/skills --public --source . --push` (the user approved a public repository)

## Acceptance Criteria
- [ ] `swift test` in `../skills` passes with zero warnings
- [ ] `https://github.com/swissarmyhammer/skills` exists, is public, and has the commit on `main`
- [ ] The CI workflow triggers on `main`, on `v*` tags, and on pull requests

## Tests
- [ ] `Tests/SkillsMarketplaceTests/SkillLibraryTests.swift`: `libraryHasNoBlockingDiagnostics` — builds the registry over `skills/` and asserts that `registry.diagnostics` has no `.skip` and no `.warning` entry (an empty library passes)
- [ ] Run `swift test` in `../skills`; expect green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo