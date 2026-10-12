---
name: release-notes
description: Draft release notes from the bundled changelog and build script.
allowed-tools: "Script(scripts/*)"
---

Write the release notes for the next version. Do these steps in this sequence:

1. Read `references/changelog.md` with `read resource`. This file gives the
   changes for each version.
2. Run `scripts/build.sh` with `run script`. This script makes the release
   build.
3. Get the logo `assets/logo.bin` with `read resource`. This file is binary,
   thus the result gives its absolute path. Put that path at the top of the
   release notes.

{% include "references/style.md" %}
