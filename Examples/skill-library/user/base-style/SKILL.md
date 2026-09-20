---
name: base-style
description: The user-layer copy of base-style; its SKILL.md wins over the defaults copy of that one file.
---

# Base Style (User Override)

This is the **user**-layer copy of `base-style`, and decision #3, as decision
#32 corrects it, decides what a reader gets.
The unit of override is the file. Because `user` outranks `defaults`, this
document -- and not `defaults/base-style/SKILL.md` -- is what discovery
observes when both layers are loaded. The override reaches this one path, and
a file that only the `defaults` directory holds stays in the skill.
