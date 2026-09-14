---
assignees:
- claude-code
position_column: todo
position_ordinal: '9580'
title: 'ACPAgent: map DotfolderStack.Source.marketplace in ConfigurationLayerName'
---
## What

**Cross-repository task.** Run it from a session opened in `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent`. The `/finish` pipeline in FoundationModelsSkills cannot do it, because that pipeline commits only in FoundationModelsSkills.

FoundationModelsExtras `main` (d0048eb) added `DotfolderStack.Source.marketplace`. In ACPAgent, `ConfigurationLayerName.init(_ source: DotfolderStack.Source?)` (`Sources/FoundationModelsACPAgent/Configuration/ConfigurationLayerName.swift`) is an exhaustive switch with no `default`. ACPAgent stops compiling when it next resolves Extras `main`.

- Run `swift package update FoundationModelsExtras`.
- Add a `marketplace` case to `ConfigurationLayerName`, and add `case .marketplace?: self = .marketplace` to `init(_:)`. Fix every switch that the compiler then reports.
- Commit `Package.resolved` and the change. The push is an operator step.

- [ ] Update the Extras pin
- [ ] Add the `marketplace` case and the mapping; fix the reported switches
- [ ] Test and commit

## Acceptance Criteria
- [ ] ACPAgent builds and all its tests pass, with zero warnings, against Extras d0048eb or later
- [ ] `ConfigurationLayerName(.marketplace)` gives `.marketplace`

## Tests
- [ ] Add a test in ACPAgent's configuration tests: `ConfigurationLayerName(.marketplace) == .marketplace`
- [ ] Run `swift test` in ACPAgent; all green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo