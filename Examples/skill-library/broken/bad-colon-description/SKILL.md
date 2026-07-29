---
name: bad-colon-description
description: Deploy to staging: verify smoke tests pass first, then promote.
---

A lenient-validation fixture (plan.md §4, §11): the unquoted colon-space
inside `description` is a common cross-client authoring mistake -- it reads
as a nested YAML mapping to a strict parser, so this frontmatter fails to
parse as-is. The spec's client-implementation guide calls for a
quoting-fallback retry rather than an outright skip; this fixture is the test
data for that retry path, kept out of the happy-path three-layer stack so it
never accidentally shadows a real fixture id.
