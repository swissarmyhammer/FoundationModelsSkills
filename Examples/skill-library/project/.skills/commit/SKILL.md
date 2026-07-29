---
name: commit
description: Create a git commit for the currently staged changes using the given message.
arguments:
  - message
argument-hint: "<message>"
---

Commit the currently staged changes using the message: $0

If no arguments were given, fall back to the full raw argument text instead:

$ARGUMENTS
