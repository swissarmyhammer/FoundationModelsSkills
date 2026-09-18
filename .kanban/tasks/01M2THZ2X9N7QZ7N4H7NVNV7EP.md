---
assignees:
- claude-code
position_column: todo
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

- [ ] Change `docs/marketplaces.md` so that the first example and all other examples use the HTTPS form. State that SSH URLs are not supported, and that an SSH URL gives the diagnostic `unsupported URL protocol`.
- [ ] Correct `marketplace.md` decision 10 and all other documents and doc comments that say SSH uses the libgit2 exec transport.
- [ ] Find the SSH marketplace URLs in this repository (manifests, examples, fixtures that are given as working examples) and change them to the HTTPS form. Do not change a test that uses an SSH URL to test URL parsing.
- [ ] Keep the tests that read the documents green (`MarketplaceDocsTests`).

#marketplace