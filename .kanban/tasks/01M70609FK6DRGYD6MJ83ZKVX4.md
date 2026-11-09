---
assignees:
- claude-code
position_column: done
position_ordinal: ffa980
title: Render skill text with a host session template context (tools.<group>.enabled)
---
Requested by the FoundationModelsACPAgent session: skill bodies must branch on the session's tool config, e.g. `{% if tools.kanban.enabled %}…{% endif %}`, without the model probing `Object.keys(tools)`.

## What
- `SkillsRegistry` public inits take `templateContext: [String: TemplateValue]` (default `[:]`).
- `StencilPass` carries it into the stenciled stack's structured variables.
- Ladder (highest first): named arguments > templateContext > environment > well-known values. The session context sits above the environment so an ambient env var such as `tools` can never shadow host config; named arguments stay on top because the skill author declared them for this call.
- One pass serves body, description/metadata, and `{% include "references/x.md" %}` (SkillFileInclude) renders, so all three see the context.

## Depends on
FoundationModelsExtras (foundationmodelsextras-1f): `StenciledDotfolderStack` taking structured (`TemplateValue`) variables.

## Acceptance
- [x] Body `{% if tools.kanban.enabled %}K{% endif %}` renders "K" with tools.kanban.enabled=true, "" with false, "" with no context.
- [x] Same for an included `references/x.md` with that text.
- [x] Same for a description render.
- [x] Context beats an environment value of the same key; a named argument beats the context.
- [x] `swift test` green; pushed; sha sent to foundationmodelsacpagent-96. #skills #render