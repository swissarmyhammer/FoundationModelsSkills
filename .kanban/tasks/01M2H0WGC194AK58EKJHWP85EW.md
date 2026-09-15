---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jq59071fa6zqpdg4my69fq
  text: |-
    Research done. Findings:
    - libgit2 http.c `handle_auth` calls the credentials callback with `git_net_url_fmt(server->url)`. This is the server URL, not the source URL. After a redirect it can have another host. The format drops a default port, so the gate compares the effective port (443 for https).
    - libgit2 calls the callback again only when the server refuses the last credential. Thus a second request means a bad token. The callback returns GIT_EUSER for it.
    - Proxy credentials use `proxy_opts.credentials`. The transport does not set that callback, so a marketplace credential never goes to a proxy.
    - GIT_EUSER maps to `.cancelled` in `LibGit2Transport.transportError`. A refused credential request also gives GIT_EUSER. The transport must map a refusal to `.unreachable` (authentication failed), not to `.cancelled`. The gate records a refusal for this.
    - `git_treebuilder_insert` does not look up the object for mode 160000. Thus `GitFixtureRepository` can write a submodule entry with any commit SHA.
    - `CatalogPath.normalized(path:)` gives the path rule of the tree source. `LocalCatalogFileSource` sorts entries by name; the tree source sorts the same way for parity.
    - The only callers of `remoteHead` and `fetch` are in `GitTransportTests.swift`.
  timestamp: 2026-09-15T14:22:28.871650+00:00
- actor: claude-code
  id: 01m2jsawkwbnb4z5jtbt3709z2
  text: |
    The earlier implementer stopped because an LSP call did not return. `sourcekit-lsp` is not on this machine. Thus the build check and the warning check were `swift build --build-tests`, and the test check was `swift test`.

    Checked each item of the card against the files on the disk. Each item is complete:
    - `GitTreeFileSource` reads a file and lists a folder from the commit tree, maps each mode, and puts `rootPath` before each lookup.
    - `MarketplaceCredential`, the `credentials` parameter on both `GitTransport` methods, `CredentialGate`, and the libgit2 `credentials` callback in `LibGit2Transport` are in place.
    - The two test suites cover each listed case, and the parity tests compare `CatalogResolver` over the tree source with the same resolver over `LocalCatalogFileSource`.

    Corrected one warning in `GitTransportTests.swift`: `'#require(_:_:)' is redundant because 'first' never equals 'nil'`. The cause was `#require(first)` inside the argument of `git_credential_get_username`, whose parameter is an implicitly unwrapped pointer. Thus the compiler took the not-optional form of the macro. The test now unwraps the pointer into a typed value first, and then it reads the user name.

    ### implement — changed
    - evidence: 1 file — /Users/wballard/github/swissarmyhammer/FoundationModelsSkills/Tests/FoundationModelsSkillsTests/GitTransportTests.swift; `swift build --build-tests` gives 0 warnings; `swift test` gives 549 tests in 39 suites, all passed
    - next: /review
  timestamp: 2026-09-15T15:00:29.948456+00:00
depends_on:
- 01M2H0RFR101FGE3GT88HD33M4
- 01M2H0QNGBQDQWBB3H1NSGYGDN
position_column: doing
position_ordinal: '80'
title: Read a fetched commit as a CatalogFileSource and add the HTTPS credential callback
---
## What

marketplace.md §5.1 (the libgit2 call table and HTTPS rules) and §7.3 step 3. Read catalog and skill files directly from the commit tree. There is no checkout and no work tree.

- `Sources/FoundationModelsSkills/Marketplace/Git/GitTreeFileSource.swift`: `struct GitTreeFileSource: CatalogFileSource` over a bare repository and a commit SHA. `contents(atPath:)`: `git_commit_lookup` → `git_commit_tree` → `git_tree_entry_bypath` → `git_blob_rawcontent`. `entries(inDirectory:)` maps modes: `100644` → `.file(isExecutable: false)`, `100755` → `.file(isExecutable: true)`, `040000` → `.directory`, `120000` → `.symlink(target:)` (the blob text), `160000` → `.submodule`. The optional `path:` field of a source is a prefix on every lookup.
- Credentials: add `MarketplaceCredential` (username, token). Add a `credentials: (@Sendable (URL) async -> MarketplaceCredential?)?` parameter to the `GitTransport` methods. The concrete `LibGit2Transport` resolves the credential **before** the libgit2 call, and the C `credentials` callback returns it one time as `git_credential_userpass_plaintext_new`. It returns `GIT_EUSER` on a second request, so a bad token does not loop. It gives the credential only when the request URL has the same scheme, host, and port as the source URL. SSH URLs use the exec transport and never call it.
- Put the origin check and the one-time rule in a pure internal type `CredentialGate`, so it can be tested with no server.

- [x] `GitTreeFileSource.contents(atPath:)` and `entries(inDirectory:)`
- [x] The `path:` prefix
- [x] `MarketplaceCredential`, the `credentials` parameter, and `CredentialGate`
- [x] Wire the libgit2 `credentials` callback in `LibGit2Transport`

## Acceptance Criteria
- [x] For the same content, `CatalogResolver` over `GitTreeFileSource` and over `LocalCatalogFileSource` gives equal results
- [x] File modes map correctly, including executable, symlink, and submodule
- [x] `CredentialGate` refuses another origin and a second request

## Tests
- [x] `Tests/FoundationModelsSkillsTests/GitTreeFileSourceTests.swift`, with `GitFixtureRepository`: read a file, list a folder, each mode, the `path:` prefix, a missing path gives `nil`; a parity test against `LocalCatalogFileSource` over the same fixture content
- [x] `Tests/FoundationModelsSkillsTests/CredentialGateTests.swift`: same origin gives the credential once; a second request is refused; another host, scheme, or port is refused; an SSH URL never asks
- [x] Run `swift test --filter "GitTreeFileSourceTests|CredentialGateTests"`; then `swift test`; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #marketplace