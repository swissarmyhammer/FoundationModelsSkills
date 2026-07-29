---
name: partial-flag
description: A skill using the retired partial:true frontmatter flag from before the _partials/ redesign.
partial: true
---

A lenient-validation fixture (plan.md §4, §6, §11): `partial: true` is
retired (decision #29) -- shared building blocks are now `_partials/*.md`
files in the stack (see `user/_partials/header.md`), not skill directories
carrying this flag. Encountering `partial: true` should draw a diagnostic and
hide the skill from every surface, preserving the old intent without reviving
the field.
