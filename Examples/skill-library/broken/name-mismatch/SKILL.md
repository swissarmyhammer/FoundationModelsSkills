---
name: totally-different-name
description: A skill whose frontmatter name does not match its own directory name.
---

A lenient-validation fixture: agentskills.io requires
`name == directoryName`, but this frontmatter's `name` is
`totally-different-name` while the directory is `name-mismatch`. The
directory name stays canonical regardless -- this mismatch draws a
diagnostic, and the skill still loads under the directory-name id.
