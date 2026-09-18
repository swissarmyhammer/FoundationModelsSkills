---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2tk4fggt1gcazsae5g9188j
  text: |-
    Research. A search for `ssh` and `git@` found these places that give the SSH form as a marketplace URL that works, or that say SSH uses the exec transport:
    - `docs/marketplaces.md`: the code example, the YAML example, and the source form table.
    - `docs/security.md` item 4.
    - `marketplace.md`: the section 5.1 table, the package comparison table, the SSH rule, the code example, the YAML example, the `state.json` example, section 12 item 4, decision 10, and the reference list.
    - Doc comments: `LibGit2Transport`, `CredentialGate`, `MarketplaceConfig`, `MarketplaceSource`, `MarketplaceLocation`.
    - User text: the `unsupportedForm` message of `MarketplaceSourceError`, and the help text of `skills marketplace add`. Both recommend `git@host:owner/repo.git`.

    Places that stay as they are, with the reason:
    - `Package.swift`, `README.md`, and `docs/development.md` use SSH URLs for SwiftPM dependencies. SwiftPM uses the system git, thus these URLs work. They are not marketplace sources.
    - `marketplace.md` section 3.1 names the git remote of the `../skills` repository. A person uses it with `git`. It is not a marketplace source.
    - The tests (`MarketplaceSourceTests`, `SourcePatternTests`, `MarketplaceConfigTests`, `MarketplaceCacheTests`, `CredentialGateTests`) use SSH URLs as parser input or as plain data. The card says not to change them. The parser continues to accept the scp-like form.
    - `Examples/` holds no SSH marketplace URL.

    Note: the `dump validators` file is 650 KB, because it holds the rules of many languages. It is too large to read whole. I read the `data-driven` and `test-integrity` rules, which apply to the test edit.
  timestamp: 2026-09-18T15:46:03.920027+00:00
- actor: claude-code
  id: 01m2tkd8qr6c5z8gda7rxmka6e
  text: |-
    Implementation notes.

    TDD: I added the tests first in `MarketplaceDocsTests`, and the run gave 4 issues as expected: the host guide did not hold `unsupported URL protocol`, the host guide held `git@`, and two texts of URL advice held `git@`. After the edits the suite passes.

    What changed:
    - `docs/marketplaces.md`: the code example and the YAML example use the HTTPS form. The `git SSH` row is gone from the source form table. A new paragraph says that SSH URLs are not supported, and it names the diagnostic `unsupported URL protocol`.
    - `docs/security.md` item 4: SSH URLs are not supported, and the package starts no `ssh` process.
    - `marketplace.md`: the section 5.1 SSH row says not supported, the `swift-libgit2` row says no SSH transport, the SSH rule records the cause and the decision of 2026-09-18, the three examples use the HTTPS form, section 12 item 4 and decision 10 are corrected, and the reference list is corrected.
    - Doc comments: `LibGit2Transport`, `CredentialGate`, `MarketplaceConfig`, `MarketplaceSource`, `MarketplaceLocation`.
    - User text: the `unsupportedForm` message and the help of `skills marketplace add` do not recommend `git@host:owner/repo.git` now. The help says that SSH URLs are not supported.

    What did not change, and why: see the research comment. The parser still accepts the scp-like form, thus the parser tests stay. `marketplace.md` section 3.1 keeps the SSH remote, because a person uses it with `git`. The `ibrahimcetin/libgit2` row stays, because it describes a different package that we did not examine.

    Discovery: the first full `swift test` run failed in `SkillWatcherTests.burstOfWritesWithinTheDebounceWindowProducesExactlyOneCallback` (2 issues). The second full run passed with no code change. That test depends on timing and has no relation to this card. New card: `^dfgw3nc`.

    Note: the `files` edit operation returns the full file after each edit. For the large `marketplace.md` file I gave the exact old text and new text of 17 replacements to a helper agent, then I checked the result with `git diff --stat` and a search for `ssh` and `git@`.

    ### implement — changed
    - evidence: 11 files. `docs/marketplaces.md`, `docs/security.md`, `marketplace.md`, `Sources/FoundationModelsSkills/CLI/MarketplaceCLI.swift`, `Sources/FoundationModelsSkills/Marketplace/Git/CredentialGate.swift`, `Sources/FoundationModelsSkills/Marketplace/Git/LibGit2Transport.swift`, `Sources/FoundationModelsSkills/Marketplace/MarketplaceConfig.swift`, `Sources/FoundationModelsSkills/Marketplace/MarketplaceLocation.swift`, `Sources/FoundationModelsSkills/Marketplace/MarketplaceSource.swift`, `Sources/FoundationModelsSkills/Marketplace/MarketplaceSourceError.swift`, `Tests/FoundationModelsSkillsTests/MarketplaceDocsTests.swift`. `swift test`: 705 tests in 54 suites passed, 0 warnings (second run; the first run had the timing failure of `^dfgw3nc`).
    - next: `/review`. No commit was made. The task stays in `doing`.
  timestamp: 2026-09-18T15:50:51.896846+00:00
- actor: claude-code
  id: 01m2tkj13y59sa1gfx5t1jv24j
  text: |-
    ### test — green
    - evidence: `swift test` — 705 tests in 54 suites passed, 0 failed, 0 skipped. `swift build` and `swift build --build-tests` gave 0 warnings and 0 errors.
    - The known timing test `SkillWatcherTests.burstOfWritesWithinTheDebounceWindowProducesExactlyOneCallback` passed. No change was made to `SkillWatcher`.
    - next: send this task for review.
  timestamp: 2026-09-18T15:53:27.934593+00:00
position_column: doing
position_ordinal: '80'
title: State in the documents that marketplace sources do not support SSH URLs
---
## What

Card `^vf3a6an` found the cause of the SSH failure. `swift-libgit2` 1.9.7 builds libgit2 with no SSH transport on macOS. `git_libgit2_features()` has the `GIT_FEATURE_SSH` bit at `0`, and `git_remote_connect` on an SSH URL gives `unsupported URL protocol` before it starts a process.

The manifest of the package has this line:

```swift
.define("GIT_SSH_EXEC", to: "1", .when(platforms: [.android, .linux, .macOS], traits: []))
```

SwiftPM never satisfies a condition that has an empty trait list.

## The decision

The user decided on 2026-09-18: documents only, no SSH. Do not fork `swift-libgit2`, do not enable the `libssh2` trait, and do not add an SSH test.

## The work

- [x] Change `docs/marketplaces.md` so that the first example and all other examples use the HTTPS form. State that SSH URLs are not supported, and that an SSH URL gives the diagnostic `unsupported URL protocol`.
- [x] Correct `marketplace.md` decision 10 and all other documents and doc comments that say SSH uses the libgit2 exec transport.
- [x] Find the SSH marketplace URLs in this repository (manifests, examples, fixtures that are given as working examples) and change them to the HTTPS form. Do not change a test that uses an SSH URL to test URL parsing.
- [x] Keep the tests that read the documents green (`MarketplaceDocsTests`).

#marketplace