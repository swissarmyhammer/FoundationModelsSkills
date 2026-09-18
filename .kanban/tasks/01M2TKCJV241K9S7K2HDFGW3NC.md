---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'SkillWatcherTests: the debounce burst test fails now and then in a full parallel run'
---
## What

`SkillWatcherTests.burstOfWritesWithinTheDebounceWindowProducesExactlyOneCallback` failed one time in a full `swift test` run on 2026-09-18, during the work on card `^nvnv7ep`. The subsequent full run passed with no change to the code, thus the failure depends on timing.

The two failed expectations were:

- `afterFirst == baseline + 1`
- `afterSettling == baseline + 1`

The work on `^nvnv7ep` changed only documents, doc comments, and two text strings. It did not touch `SkillWatcher`.

## The work

- [ ] Run the test many times under a loaded parallel run and find why the count is not `baseline + 1`.
- [ ] Correct the cause. Do not add a retry, and do not only increase a time limit.
- [ ] Make sure that the full `swift test` run is stable.