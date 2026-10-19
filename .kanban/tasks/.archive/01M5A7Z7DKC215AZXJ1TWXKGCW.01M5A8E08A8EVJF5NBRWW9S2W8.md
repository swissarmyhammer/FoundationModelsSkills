---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5a84qjxesba3znwc7n0fph7
  text: |-
    Agreed with foundationmodelsagents-93 (2026-10-19):

        The skills listed in the `skills` tool description have changed. These entries replace the listed ones:
        Added:
        - name: description
        Changed:
        - name: description
        Removed:
        - name

    - One notice per reload that has a visible change.
    - The order is Added, Changed, Removed. A section with no entries is left out. Each list keeps catalog order.
    - Lines give the full one-line description, never the truncated one.
    - Agents uses the same text with `agents` in place of `skills`.
    - Tell foundationmodelsagents-93 if the words change.
  timestamp: 2026-10-19T14:13:12.413208+00:00
- actor: claude-code
  id: 01m5a8dt8cthjs73csacvd091p
  text: 'Superseded on 2026-10-19. The notice text is `CatalogChangeNotice.text` in FoundationModelsExtras e6b2bf9, for example ``Skills changed. New: `x`: does x. Removed: `y`.``. Skills and agents share it, so this package writes no notice text of its own. The text agreed above is not used. Archiving this task.'
  timestamp: 2026-10-19T14:18:10.060207+00:00
depends_on:
- 01M5A7Z0YGYG5Y3MR7EBQ1DX6D
position_column: todo
position_ordinal: '8180'
title: Write the catalog-change notice text, in the same form as the agents notice
---
#skills

## What
Turn a non-empty `SkillCatalogChange` into the body text of ONE notice. Put it in `SkillCatalogText` next to `descriptionUseRule`, so the description and the notice use the same line form.

- Lines for added and changed skills use the description-list form exactly: `SkillCatalogText.line(id:description:)` → `- name: description`.
- Removed skills are listed by id.
- A short lead sentence says that the skill list in the `skills` tool description has changed, and that this notice replaces it for the named entries.

## Coordination
The agents tool (session foundationmodelsagents-93) writes the same notice for agents. Agree on one shared form with that session before this task is done: lead sentence, section words (added / removed / changed), and order. Record the agreed text in a comment on this task.

## TDD: failing tests first
- [ ] added-only, removed-only, changed-only, and mixed changes each give the exact expected text
- [ ] an added line is byte-equal to the line that `SkillsToolDescription.make` would write for that skill
- [ ] the description is not truncated in the notice (it lists only changed entries)

## Acceptance
- [ ] Text agreed with foundationmodelsagents-93
- [ ] Tests written first and seen failing, then passing; full `swift test` green