---
name: missing-description
---

A lenient-validation fixture (plan.md §4, §11): `description` is required by
the agentskills.io spec (1-1024 chars, non-empty), and it is missing here
entirely. Per the lenient-validation posture, a skill like this loads with a
diagnostic and is excluded from the model surface -- it cannot be disclosed
without a description -- but stays user-invocable, our one deliberate
softening of the client-implementation guide's skip-entirely rule.
