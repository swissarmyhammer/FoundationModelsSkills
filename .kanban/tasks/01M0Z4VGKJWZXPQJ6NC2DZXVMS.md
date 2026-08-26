---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: PathConfinement denies a missing path under a /private-prefixed skill root instead of the unreadable corrective
---
`Sources/FoundationModelsSkills/Resources/PathConfinement.swift`

On macOS, `SkillDiscovery` lists skill directories with `FileManager.contentsOfDirectory(at:)`, which gives a `/private/var/...` path for a root under the temp directory. `PathConfinement.resolvedURL(relativePath:in:)` then calls `resolvingSymlinksInPath()` on the skill directory. Foundation removes the `/private` prefix from a path that exists, but it leaves a path that does not exist (a missing file, a dangling symbolic link) unchanged. The two paths then do not share a prefix, and `isContained` says `false`.

Result: a `read resource` call for a missing file or a dangling symbolic link under such a root draws the confinement corrective (\"is not accessible\") in place of the unreadable corrective (\"could not be read\"). The refusal is safe, but the message is wrong.

Measured with a probe script on 2026-08-26: listed directory `/private/var/.../dangling`, resolved directory `/var/.../dangling`, dangling candidate `/private/var/.../dangling/dangling-link`, contained `false`.

Fix: compare the two paths after the same normalization, for example resolve the parent directory of the candidate and append the last component, or remove the `/private` prefix from both sides. Add a test that reads a missing file under a temp root and expects \"could not be read\". #bug