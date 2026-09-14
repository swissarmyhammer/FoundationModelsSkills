---
assignees:
- claude-code
depends_on:
- 01M2H0RFR101FGE3GT88HD33M4
- 01M2H0QNGBQDQWBB3H1NSGYGDN
position_column: todo
position_ordinal: '8980'
title: Read a fetched commit as a CatalogFileSource and add the HTTPS credential callback
---
## What

marketplace.md §5.1 (the libgit2 call table and HTTPS rules) and §7.3 step 3. Read catalog and skill files directly from the commit tree. There is no checkout and no work tree.

- `Sources/FoundationModelsSkills/Marketplace/Git/GitTreeFileSource.swift`: `struct GitTreeFileSource: CatalogFileSource` over a bare repository and a commit SHA. `contents(atPath:)`: `git_commit_lookup` → `git_commit_tree` → `git_tree_entry_bypath` → `git_blob_rawcontent`. `entries(inDirectory:)` maps modes: `100644` → `.file(isExecutable: false)`, `100755` → `.file(isExecutable: true)`, `040000` → `.directory`, `120000` → `.symlink(target:)` (the blob text), `160000` → `.submodule`. The optional `path:` field of a source is a prefix on every lookup.
- Credentials: add `MarketplaceCredential` (username, token). Add a `credentials: (@Sendable (URL) async -> MarketplaceCredential?)?` parameter to the `GitTransport` methods. The concrete `LibGit2Transport` resolves the credential **before** the libgit2 call, and the C `credentials` callback returns it one time as `git_credential_userpass_plaintext_new`. It returns `GIT_EUSER` on a second request, so a bad token does not loop. It gives the credential only when the request URL has the same scheme, host, and port as the source URL. SSH URLs use the exec transport and never call it.
- Put the origin check and the one-time rule in a pure internal type `CredentialGate`, so it can be tested with no server.

- [ ] `GitTreeFileSource.contents(atPath:)` and `entries(inDirectory:)`
- [ ] The `path:` prefix
- [ ] `MarketplaceCredential`, the `credentials` parameter, and `CredentialGate`
- [ ] Wire the libgit2 `credentials` callback in `LibGit2Transport`

## Acceptance Criteria
- [ ] For the same content, `CatalogResolver` over `GitTreeFileSource` and over `LocalCatalogFileSource` gives equal results
- [ ] File modes map correctly, including executable, symlink, and submodule
- [ ] `CredentialGate` refuses another origin and a second request

## Tests
- [ ] `Tests/FoundationModelsSkillsTests/GitTreeFileSourceTests.swift`, with `GitFixtureRepository`: read a file, list a folder, each mode, the `path:` prefix, a missing path gives `nil`; a parity test against `LocalCatalogFileSource` over the same fixture content
- [ ] `Tests/FoundationModelsSkillsTests/CredentialGateTests.swift`: same origin gives the credential once; a second request is refused; another host, scheme, or port is refused; an SSH URL never asks
- [ ] Run `swift test --filter "GitTreeFileSourceTests|CredentialGateTests"`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace