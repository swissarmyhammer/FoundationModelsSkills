---
name: spec-clean
description: A pure agentskills.io-spec skill -- no top-level extension fields, portable to any conforming client.
license: MIT
compatibility: "Requires a POSIX shell and git 2.30 or later."
metadata:
  disable-model-invocation: false
  preload: false
---

A skill authored for maximum agentskills.io portability (decision #27): the
top level carries only spec fields (`name`, `description`, `license`,
`compatibility`) -- every one of our own extension fields rides under
`metadata.*` instead of the top level, the spec's designated home for
client-defined properties.
