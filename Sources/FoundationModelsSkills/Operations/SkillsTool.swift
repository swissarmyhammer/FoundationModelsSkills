import FoundationModels
import Operations

/// Builds the fused `skills` tool: `SearchSkill`, `ListSkill`, and `UseSkill`
/// presented to a model (or the CLI) as one `OperationTool` (plan.md §7,
/// decision #20).
///
/// The fusion, the flat-union schema, the forgiving op/parameter resolution,
/// and the return-don't-throw retry cap are all inherited from the upstream
/// `Operations` runtime -- this type only supplies the operation set and the
/// verb aliases decision #21 asks for.
public enum SkillsTool {
    /// The fused tool's model- and CLI-facing name.
    private static let toolName = "skills"

    /// A human- and model-facing summary of the fused tool.
    private static let toolDescription = "Search, list, and use skills from the local skill library."

    /// Builds the fused `skills` `OperationTool` over `context`.
    ///
    /// The six operations dispatch through `AnyOperation` against the
    /// shared `context`, in the order `search` / `list` / `use` / `list
    /// resource` / `read resource` / `run script` -- the order the fused
    /// schema's `op` enum and any unknown-operation corrective list them in.
    ///
    /// - Parameter context: The shared context every operation's
    ///   `execute(in:)` runs against.
    /// - Returns: The fused `skills` tool, ready to register on a
    ///   `LanguageModelSession` or drive from the CLI.
    /// - Throws: `SchemaFusionError.reservedParameterName` if an operation
    ///   declares a parameter colliding with the `op` discriminator (not
    ///   expected for this fixed operation set, but propagated per
    ///   `OperationTool.init`'s contract); rethrows `GenerationSchema.SchemaError`
    ///   on any other schema-fusion failure.
    public static func make(context: SkillsToolContext) throws -> OperationTool<SkillsToolContext> {
        try OperationTool(
            name: toolName,
            description: toolDescription,
            context: context,
            operations: [
                AnyOperation(SearchSkill.self),
                AnyOperation(ListSkill.self),
                AnyOperation(UseSkill.self),
                AnyOperation(ListResource.self),
                AnyOperation(ReadResource.self),
                AnyOperation(RunScript.self),
            ],
            resolver: makeResolver()
        )
    }

    /// Builds the forgiving resolver `make(context:)` fuses the tool with.
    ///
    /// - Returns: A resolver layering `verbAliasOverrides` onto the upstream
    ///   defaults.
    private static func makeResolver() -> OperationResolver {
        OperationResolver(verbAliases: verbAliasOverrides)
    }

    /// The verb aliases this tool's operation set needs, layered onto
    /// `OperationResolver.defaultVerbAliases`: decision #21's `find`/
    /// `discover` → `search` and `call`/`invoke`/`get` → `use`, plus a
    /// `"read"` self-mapping override (below) `ReadResource` needs to be
    /// reachable at all.
    ///
    /// Derived from the operations' own `verb` statics so this table cannot
    /// drift from them (matches the sibling `FileTool`'s
    /// `fileVerbSelfAliases` convention).
    ///
    /// `OperationResolver.matchOpString` applies a verb alias
    /// unconditionally once one exists for a query's verb token -- it never
    /// falls back to trying the literal, unaliased verb against a
    /// same-spelled real operation. Decision #21 originally listed `run` as
    /// a fourth `use` synonym alongside `call`/`invoke`/`get`, and this
    /// table carried a `"run": UseSkill.verb` entry through M4/M5 with a
    /// documented forward-tension warning about the M6 `run script`
    /// operation this exact unconditional-rewrite behavior would collide
    /// with. M6 (`RunScript`) has now landed, and the collision is real: a
    /// `"run": UseSkill.verb` entry would rewrite a literal `"run script"`
    /// query to `"use script"` (which doesn't exist) before it ever reaches
    /// `RunScript`. Resolved by dropping the `"run"` → `use` alias entirely
    /// -- `"run skill"` no longer resolves (pinned by
    /// `SkillOperationsTests`' `resolverDoesNotAcceptRunSkillNowThatRunIsClaimedByRunScript`
    /// case), while `call`/`invoke`/`get` remain as non-colliding `use`
    /// synonyms.
    ///
    /// The same unconditional-rewrite behavior is why `"read":
    /// ReadResource.verb` is here: `OperationResolver.defaultVerbAliases`
    /// already maps `"read"` → `"get"` (a CRUD-verb convenience for tools
    /// with no `"read"` operation of their own). Without this self-mapping
    /// override, `ReadResource`'s own literal `"read resource"` query would
    /// be rewritten to `"get resource"` before matching and never reach it,
    /// since nothing here is registered under verb `"get"` for the
    /// `"resource"` noun. Pinned by `ResourceOpsTests`.
    private static let verbAliasOverrides: [String: String] = [
        "find": SearchSkill.verb,
        "discover": SearchSkill.verb,
        "call": UseSkill.verb,
        "invoke": UseSkill.verb,
        "get": UseSkill.verb,
        "read": ReadResource.verb,
    ]
}
