---
comments:
- actor: claude-code
  id: 01m2thp4z3xhk2h2nnebmdq114
  text: |-
    ### Research: the cause is found

    **Work item 2 is answered. The libgit2 build has NO SSH transport.**

    - A probe in the test target called `git_libgit2_features()`. The result was `1587`, and the `GIT_FEATURE_SSH` bit was `0`. `git_libgit2_feature_backend(GIT_FEATURE_SSH)` gave `nil`.
    - `git_remote_connect` on `git@github.com:swissarmyhammer/skills.git` and on `ssh://git@github.com/swissarmyhammer/skills.git` gave status `-1` in 0.00002 seconds. The libgit2 message was `unsupported URL protocol`. Thus `connect` fails before it starts a process, as the card supposed.
    - The cause is in `swift-libgit2` 1.9.7, `Package.swift`: `.define("GIT_SSH_EXEC", to: "1", .when(platforms: [.android, .linux, .macOS], traits: []))`. `swift package dump-package` shows the condition with `"traits": []`. SwiftPM never satisfies a condition with an empty trait set. `.build/manifest.pif` holds 704 `GIT_HTTPS` entries and zero `GIT_SSH` entries. The native build system gives the same result (`debug.yaml`: 234 `GIT_HTTPS`, zero `GIT_SSH_EXEC`).
    - Tags 1.9.4, 1.9.6, 1.9.7 and the upstream default branch all have the same line. No released version repairs it. The only SSH path that the package can build is the `libssh2` trait.
    - `LibGit2Transport.phaseError` maps each `.connecting` failure to `.unreachable` and drops the libgit2 message. `MarketplaceStore.text(of:)` uses `String(describing:)`, thus the diagnostic says only `unreachable`.
    - `MarketplaceLocation` refuses an HTTPS URL that holds a user name or a password (`credentialsInURL`). Thus a libgit2 message cannot repeat a credential from the URL.

    **Environment note.** `Package.resolved` is ignored by git, and the local copy pinned `FoundationModelsExtras` at `8b4706d`, which has no `DotfolderStack.Source.marketplace`. The build failed until `swift package update` moved the pin to `24d258d`. No tracked file changed.

    **Rules.** The validator dump is 12098 lines (754 KB), because it holds the rule text for six languages. It was not read whole. These parts were read: `test-integrity` (all three rules), and the Swift parts that apply to the edit.
  timestamp: 2026-09-18T15:20:45.795075+00:00
- actor: claude-code
  id: 01m2thzq6hd75tj3ss3z7fxbbw
  text: |-
    ### Implementation: work item 3 is done, work item 2 is answered, work item 1 is blocked

    **Done (work item 3).** `GitTransportError.unreachable` is now `unreachable(message: String)`.
    - A `.connecting` failure carries the libgit2 message. An SSH URL now gives `unreachable(message: "unsupported URL protocol")`, and a host that is down gives a different message.
    - A refused credential request carries the fixed text `LibGit2Transport.credentialRefusedMessage`, never text from libgit2.
    - `MarketplaceStore.text(of:)` did not change. It uses `String(describing:)`, thus the event, the status, the diagnostic, and the CLI row all get the message.
    - The doc comment of `LibGit2Transport` now says that `swift-libgit2` 1.9.7 builds no SSH transport.
    - TDD: the RED was a compile failure in `GitTransportTests` (`enum case 'unreachable' has no associated values`). For the end-to-end assertion, the RED came from a temporary `message: ""` in `phaseError`; the two new expectations in `MarketplaceEndToEndTests` failed, and the line was then restored.
    - `swift test`: 703 tests in 54 suites passed, with no warning.

    **Blocker (work item 1): "Reproduce with a test that uses the real `LibGit2Transport` and an SSH URL, in the integration tier."** This diff has no such test. A person must decide two things.

    1. **Where the test lives.** Three rules disagree.
       - The `test-integrity/test-partitioning` validator says that a test that uses the network must not be in the unit target, that a Swift integration test lives in a nested `IntegrationTests/` package, and that CI must run it.
       - `CIWorkflowTests` pins `test-skip` and `integration-filter` to exactly `FoundationModelsSkillsTests.HotReloadLiveTests`, and it forbids the `integration-package-path` input. The header of `.github/workflows/ci.yml` records the decision: "this package has one test target, thus no nested integration package".
       - The shared `swift-ci.yaml` runs one integration job: the root package with a filter, or a nested package. Thus a nested package needs `HotReloadLiveTests` to move also, and `CIWorkflowTests` to change. That reverses the decision of card `^dzep0b7`, and it is not in this card.
    2. **What the test asserts.** An honest reproduction asserts that an SSH URL gives a commit. That test stays red until libgit2 has an SSH transport, and no released `swift-libgit2` version has one without the `libssh2` trait. A test that asserts `unsupported URL protocol` would pin the defect as the correct result.

    **What was tried.** A temporary probe suite in the unit target (deleted again) gave all the facts in the research comment. `swift build --build-system native` into a scratch path showed that the build system is not the cause.

    **New card.** `^nvnv7ep` holds the decision about the SSH transport (upstream correction, fork, or the `libssh2` trait), and the document correction for `docs/marketplaces.md`.
  timestamp: 2026-09-18T15:25:59.377588+00:00
- actor: claude-code
  id: 01m2tj0dnbpkv6fde2hzd730rv
  text: |-
    ### implement — stuck
    - evidence: 4 files changed — Sources/FoundationModelsSkills/Marketplace/Git/GitTransport.swift, Sources/FoundationModelsSkills/Marketplace/Git/LibGit2Transport.swift, Tests/FoundationModelsSkillsTests/GitTransportTests.swift, Tests/FoundationModelsSkillsTests/MarketplaceEndToEndTests.swift. `swift test`: 703 tests in 54 suites passed, no warning. Work item 3 is done and work item 2 is answered. Work item 1 (the SSH test in the integration tier) is NOT in the diff.
    - gap: the `test-partitioning` validator, `CIWorkflowTests`, and the card disagree on where a network test lives, and an honest SSH test stays red until libgit2 has an SSH transport (`swift-libgit2` 1.9.7 builds none). See the blocker comment.
    - next: a person decides the location of the integration test and the SSH transport path (card `^nvnv7ep`). Then run `/implement` again for work item 1.
  timestamp: 2026-09-18T15:26:22.379196+00:00
- actor: claude-code
  id: 01m2tj16c950rs61hvfb6m5j4z
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — 4 files changed (GitTransport.swift, LibGit2Transport.swift, GitTransportTests.swift, MarketplaceEndToEndTests.swift). Work item 2 is answered and work item 3 is done. Work item 1 (the SSH test in the integration tier) is not in the diff.
    - test: not run as a separate step. The implement step reported `swift test`, 703 tests in 54 suites passed, 0 warnings.
    - commit: none. The changes are in the working tree and are not committed.
    - review: not run.
    - blocker: a person must decide (1) where the SSH integration test lives, because `test-partitioning`, `CIWorkflowTests` and the shared `swift-ci.yaml` disagree, and (2) what the test asserts while libgit2 has no SSH transport. Card `^nvnv7ep` holds the SSH transport decision.
  timestamp: 2026-09-18T15:26:47.689705+00:00
- actor: claude-code
  id: 01m2tjtq44p87cckw9w2w8yp9g
  text: |-
    ### test — green
    - evidence: swift test — 703 passed, 0 failed, 0 skipped; no warnings found; diagnostics check clean (0 errors, 0 warnings)
    - next: ready for review
  timestamp: 2026-09-18T15:40:44.036163+00:00
- actor: claude-code
  id: 01m2tjvt70mcmgwgfhxw2ygj8q
  text: |-
    ### commit — changed
    - evidence: 3e86b91 fix(marketplace): add the libgit2 message to GitTransportError.unreachable
    - next: none
  timestamp: 2026-09-18T15:41:19.968382+00:00
- actor: claude-code
  id: 01m2tk0wgbxhwdjqm08tr203ja
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit `3e86b91`). Counts: 0 findings, 0 confirmed, 0 refuted, 7 validator runs attempted, 0 failed, 0 skipped. 4 files reviewed. 4 `.kanban/` files were excluded by `.reviewignore`. The card had no prior `## Review Findings` section.
    - next: the task is in `done`. Card `^nvnv7ep` corrects the documents. Work item 1 (SSH test) stays dropped by the user decision of 2026-09-18.
  timestamp: 2026-09-18T15:44:06.155406+00:00
- actor: claude-code
  id: 01m2tk17dckpym0q97b17g0vdz
  text: |-
    ### finish iteration 2 — clean
    - implement: no new step. The user dropped work item 1 (no SSH, no SSH test). The change from iteration 1 is the full scope.
    - test: green — swift test, 703 passed, 0 failed, 0 skipped, no warnings
    - commit: 3e86b91
    - review: clean — HEAD~1..HEAD, 0 findings, 7 validator runs, 4 files reviewed. The task moved to done.
  timestamp: 2026-09-18T15:44:17.324176+00:00
position_column: done
position_ordinal: ee80
title: The SSH form of a marketplace URL is unreachable, although git over SSH works
---
## What

On 2026-09-18, with this package at `b902551`, a host made this store:

```swift
MarketplaceStore(sources: [MarketplaceSource("git@github.com:swissarmyhammer/skills.git", ref: "code-context")])
```

`await store.start()` returned in 0.06 seconds. `store.diagnostics` held `[error] skills: The marketplace is not updated: unreachable`, and `store.check()` gave `error: "unreachable"` with no current commit. No layer had a skill.

In the same shell, `git push` and `git ls-remote` to the same SSH URL worked, and `SSH_AUTH_SOCK` was set. The HTTPS form `https://github.com/swissarmyhammer/skills.git` with the same `ref` fetched commit `1941497` and mounted five skills in 2 seconds.

## Why it matters

`docs/marketplaces.md` gives the SSH form as the first example, and the family manifests use SSH URLs. A host that follows the document gets no skills and only one diagnostic. 0.06 seconds is too short for an OpenSSH process to connect, thus the exec transport possibly never starts.

## The work

1. DROPPED by the user on 2026-09-18: no SSH test. Do not add a network test for SSH. The answer was "no ssh thanks, too much drama".
2. DONE: the libgit2 build has no SSH transport (`GIT_FEATURE_SSH` is `0`). `connect` fails with `unsupported URL protocol` before it starts a process. Card `^nvnv7ep` holds the cause.
3. Make the diagnostic say the libgit2 message. `unreachable` alone does not tell a transport that is absent from a host that is down. The change is in the working tree: `GitTransportError.unreachable(message:)`.

The scope of this card is now work item 3 only, with its unit tests. Card `^nvnv7ep` corrects the documents.

## Where it was found

`FoundationModelsACPAgent`, card `^bt2wyyz`. The agent uses the HTTPS form in `bench/code-context.config.yaml` as the workaround. #marketplace #cross-repo