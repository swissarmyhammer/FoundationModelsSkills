# Development notes and known deviations

## Known deviations from plan.md

- **A body render suspends, and the shell pass has a timeout and an output
  limit.** Plan.md §5 states the three passes of the render, and decision #25
  states that a shell command runs fresh on each render. It states no limit on
  that command, and it shows a synchronous render. The implementation gives
  the shell pass the same process control that §7.3.1 already gave `run
  script`: the `ProcessRunner` of `FoundationModelsExtras` starts each command
  in a process group of its own, the pid stands in `ProcessRegistry.global`
  while it runs, the whole group dies with `SIGKILL` at
  `RenderPolicy.shellCommandTimeout`, and the read of the output stops at
  `RenderPolicy.shellOutputByteLimit`. A command that passes either limit
  gives an inert marker in place of its output, and the render of the rest of
  the body goes on. That runner is `async`, thus pass 2 is `async`, and with
  it `RenderPipeline.renderBody`, `SkillsRegistry.call(id:arguments:)` and
  `SkillsRegistry.preloadedBodies()`. A blocking bridge was refused: a render
  runs on the cooperative pool, and a blocked cooperative thread for each
  parallel render can starve the pool. The metadata render runs passes 1 and 3
  only, thus it stays synchronous and every catalog reader keeps its
  signature. The pass protocol splits in two for that reason: `RenderPass`
  for the synchronous passes 1 and 3, and `ShellRenderPass` for pass 2.
- **`read resource` adds a per-call content byte budget.** Plan.md §7.3
  states one cap: 500 lines maximum for each call, and `totalLines` tells
  the model to page with `start`/`end`. The implementation keeps that cap
  and adds a second one: 1,000,000 content bytes for each call. Thus the
  memory one call retains stays bounded for all line lengths. The
  operation streams the file in 64 KiB parts and never loads the full
  file. Each call scans to the end of the file, thus `totalLines` is
  exact. When the next line of the window would push the content over the
  byte budget, the window stops at the last line that fits, and `end`
  reports that line. The model pages on from `end + 1` as before. If a
  single line alone exceeds the budget, the operation refuses with a
  corrective message that names the line, because no window can return
  it. The §7.3 non-UTF-8 corrective is unchanged: the scan stops at the
  first invalid byte, and the reported byte size comes from `stat`, thus
  the operation never materializes a binary asset.
- **Op-level correctives do not count toward upstream's retry cap.**
  Plan.md §7 / decision #22 says: "upstream's retry cap (default 2) stops
  loops." `OperationTool.call(arguments:)`, in the `Operations` module of
  `FoundationModelsExtras`, only counts *resolver-level* failures —
  an unknown op, a missing required parameter, an unparseable value —
  through `recordCorrective`. When dispatch reaches an operation's own
  `execute(in:)`, that call counts as a success and resets the counter
  (`retryState.reset()`), also when the op returns
  `CorrectiveOutcome.corrective(_:)` (for example, `use skill` with an
  unknown id, or `read resource` with an inaccessible path). Thus a model
  that loops on a bad `id` never hits the cap. A correct repair needs an
  upstream signal on `AnyOperation.run`'s result (an `isCorrective` flag,
  or an enum that separates the two cases). `OperationTool.Output` is an
  opaque `String` at this time, thus the fused tool cannot see which
  channel an operation's own JSON came from. That is a protocol-level
  change to the `Operations` module of `FoundationModelsExtras`, which
  other consumers also use. (`FoundationModelsOperationTool` was retired
  on 2026-08-29; it held that module until then.) It is out of this
  package's scope to land alone. It is not yet coordinated upstream;
  this note tracks it.
  `SkillOperationsTests.repeatedUnknownIDUseSkillDispatchesAreNeverCappedByUpstreamsRetryLimit`
  pins the current (uncapped) behavior, thus a future upstream repair
  shows here as a test failure, not silently.

## Development

- **Sibling dependencies are remote, not local `path:`.**
  `FoundationModelsExtras` and `FoundationModelsMetadataRegistry` both pin
  to `git@github.com:swissarmyhammer/<name>.git` (`main` branch) in
  `Package.swift`. This matches the family convention: each sibling reaches
  the next one the same way, for example
  `FoundationModelsMetadataRegistry -> FoundationModelsRanker`. A local
  `path:` dependency here caused a SwiftPM "Conflicting identity" warning:
  this package pulled one and the same sibling in two times, once by path
  and once transitively by URL. SwiftPM says this "will be escalated to an
  error in future versions." Remote wiring for each sibling resolves the
  identity to a single reference. It also matches the family's shared
  `swift-ci.yaml` reusable workflow, which only checks out the calling
  repository — a `path:` dependency on an uncommitted sibling checkout
  would not exist there.
