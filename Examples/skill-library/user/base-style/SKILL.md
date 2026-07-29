---
name: base-style
description: The user-layer override of base-style; replaces the defaults copy entirely rather than merging with it.
---

# Base Style (User Override)

This is the **user**-layer copy of `base-style`. Layer precedence is
nearest-wins full-replace (decision #3): because `user` outranks `defaults`,
this document -- not `defaults/base-style/SKILL.md` -- is what discovery
observes when both layers are loaded, with no field-by-field merge between
the two.
