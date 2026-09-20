---
name: base-style
description: A plain example skill demonstrating the baseline SKILL.md shape -- just name and description, no extensions.
---

# Base Style

This is the **defaults**-layer copy of the `base-style` skill: the lowest
layer of the three-layer `.skills` dotfolder stack (plan.md §11).

The `user` layer holds a copy of the same id at `user/base-style/SKILL.md`.
The unit of override is the file (decision #32), thus that higher copy of
`SKILL.md` wins and a discovery pass over the whole stack surfaces the
user-layer text, never this one. Each other file that only this directory
holds would stay in the skill.
