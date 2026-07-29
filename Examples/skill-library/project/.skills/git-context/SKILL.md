---
name: git-context
description: Report the current repository context, refreshed on every render.
preload: true
# Deterministic `echo` stands in for `git status` here (not the real
# command) so this fixture's golden renders stay hermetic and reproducible,
# independent of this checkout's actual git state when tests run.
---

Repository context:

!`echo "on branch main, working tree clean"`
