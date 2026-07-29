---
comments:
- actor: claude-code
  id: 01kypakm3c3052hf3mjq7x9b60
  text: |-
    Implemented via TDD.

    Research: read plan.md §3/§4/§10/§11 and decisions #3/#19/#29 (confirmed #29's 2026-07-28 amendment: host supplies roots, package names no directory convention). Read FoundationModelsExtras' DotfolderStack.swift directly -- `layers: [Layer]` is already ordered lowest-to-highest precedence (defaults < user < project), so the stack->roots helper is a direct `stack.layers.map(\.root)` projection, no reordering needed.

    RED: wrote Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift first (7 tests covering the fixture-root snapshot, base-style shadowing provenance, non-shadowed skills, user/_partials/ exclusion, a nonexistent root, .git/node_modules exclusion over a temp dir, and DotfolderStack-helper equivalence). Confirmed it failed to compile (cannot find type 'DiscoveredSkill' in scope) before writing any production code.

    GREEN: added Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift (record: id, skillDirectory, skillFileURL, winning rootIndex+root, shadowedCandidates: [ShadowedCandidate] each carrying rootIndex+root+skillDirectory) and Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift (struct holding `roots: [URL]`; `init(roots:)` does no I/O; `init(stack:)` + static `roots(from:)` are the DotfolderStack convenience, `SkillDiscovery(stack: stack).discover()` is the one-line §10 path; `discover()` walks each root's immediate subdirectories once -- no recursion, so scan depth is structurally bounded rather than counter-bounded -- excludes `.git`/`node_modules` by name, keeps only directories containing SKILL.md, and folds same-id hits last-root-wins, pushing the replaced record onto shadowedCandidates). All 7 new tests passed first try; full suite green at 95/95.

    Discovery/discrepancy worth recording: the task's acceptance criteria lists the expected fixture ids as exactly base-style, commit, deploy, lint, spec-clean (5). The actual on-disk `project/.skills/` fixture directory already contains a sixth valid skill directory, `git-context/SKILL.md` (landed by an earlier task -- it's already exercised directly by ShellInjectionTests' `gitContextFixturePreloadsAndRendersItsDeterministicInjection`). Discovery is specified to be purely structural (no YAML parsing, no content judgment), so a correct implementation necessarily also discovers git-context. Excluding it to match the acceptance-criteria list would mean hardcoding a name-based skip with no basis in the plan -- actively wrong. I implemented the generically-correct structural behavior and wrote the discovery-snapshot test against the real current fixture set (6 ids, git-context included), rather than the stale 5-id list. Flagging this here rather than silently deviating from the written acceptance criteria.

    swift build: clean (only pre-existing, unrelated SwiftPM package-identity-conflict warnings from the wider dependency graph). swift test: 95/95 passed, 0 failures.
  timestamp: 2026-07-29T06:57:17.932423+00:00
- actor: claude-code
  id: 01kypb44j4gwwv4kq1naaa13v2
  text: |-
    really-done verification complete.

    Adversarial double-check round 1 (double-check agent, fresh `swift test --filter SkillDiscoveryTests` run + hand-traced the shadow-fold logic): verdict REVISE -- no correctness bugs, but flagged 3 test-coverage gaps: (1) no 3+ root shadow-chain test, (2) no test that a root which is a regular file (not a directory) is skipped without throwing, (3) no empty-roots-array test.

    Closed all three by adding threeRootShadowChainAccumulatesShadowedCandidatesInPrecedenceOrder(), rootThatIsARegularFileIsSkippedWithoutThrowing(), and emptyRootsListDiscoversNoSkills() to SkillDiscoveryTests.swift.

    Round 2 (re-check, bounded per really-done's "at most once" loop): verdict PASS -- confirmed each new test asserts the right thing (order/rootIndex/root across all 3 shadow levels, not just a count) and independently re-ran the suite fresh (exit 0).

    Final state: swift build clean; swift test -- 98/98 passed, 0 failures, 0 warnings introduced. Task left in `doing` for `/review` per the implement skill's process (not moved to review by this agent).
  timestamp: 2026-07-29T07:06:19.076936+00:00
depends_on:
- 01KYNCQ6ZFGBMZSHBY2W3EN080
position_column: done
position_ordinal: '8780'
title: Directory-shaped skill discovery over host-supplied layer roots
---
## What
Layer-3 discovery (plan §3, §4, decisions #19/#29 — #29 as amended 2026-07-28: **the host supplies the roots**; the package names no directory convention).

- `Sources/FoundationModelsSkills/Discovery/DiscoveredSkill.swift` — record: canonical `id` (directory name), `skillDirectory: URL`, `skillFileURL: URL` (the `SKILL.md`), the winning root (index + URL, the provenance the diagnostics surface), plus the list of shadowed lower-precedence candidates for the shadowing advisory.
- `Sources/FoundationModelsSkills/Discovery/SkillDiscovery.swift` — input: an **ordered `[URL]` of layer roots, lowest precedence first**. For each root, enumerate immediate `name/SKILL.md` directories. **Later roots shadow earlier** by directory name (full-replace, decision #3; last-root-wins). Skip `.git` and `node_modules`; bound scan depth. Skip directories without `SKILL.md`. No YAML parsing here; discovery is purely structural. Nonexistent roots are skipped silently (a host may pass `~/.skills` that does not exist yet).
- `DotfolderStack` is NOT the input — it is one host-side convenience for computing roots (`stack.layers` → root URLs). Provide a small helper that maps a `DotfolderStack` to the ordered root list so §10's convenience path stays one line.
- Construction does no I/O beyond the explicit discovery call.

## Acceptance Criteria
- [x] Discovery over the §11 fixture roots (explicit fixture URLs in defaults→user→project order — hermetic) finds exactly: `base-style` (winner = user root, defaults copy recorded as shadowed), `commit`, `deploy`, `lint`, `spec-clean` -- plus `git-context` (a legitimate 6th fixture that landed on disk after this criterion was written; discovery is purely structural so it is correctly discovered too; see task comments)
- [x] `user/_partials/` is NOT discovered as a skill; a directory without `SKILL.md` is ignored
- [x] A nonexistent root in the list is skipped without error
- [x] Provenance on each record names the winning root
- [x] The `DotfolderStack`→roots helper produces the same discovery result as passing the URLs directly

## Tests
- [x] `Tests/FoundationModelsSkillsTests/SkillDiscoveryTests.swift` — fixture-root discovery snapshot; shadowing (last-root-wins, including a 3-root shadow chain); nonexistent-root case; `.git`/`node_modules` skip over a temp directory; stack-helper equivalence; empty-roots and file-as-root edge cases
- [x] `swift test` — exit 0 (98/98 passed)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.