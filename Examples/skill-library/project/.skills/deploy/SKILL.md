---
name: deploy
description: Deploy the current build to the target environment.
disable-model-invocation: true
---

Deploy the current build. This skill is listed in the user `/` menu but
hidden from the model surface (`disable-model-invocation: true`, §6) -- a
user-only command such as `/deploy`, never something the model can search
for, list, or invoke on its own.
