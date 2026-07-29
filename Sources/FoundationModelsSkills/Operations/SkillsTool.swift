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
    /// The three operations dispatch through `AnyOperation` against the
    /// shared `context`, in the order `search` / `list` / `use` -- the order
    /// the fused schema's `op` enum and any unknown-operation corrective
    /// list them in.
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
            ],
            resolver: makeResolver()
        )
    }

    /// Builds the forgiving resolver `make(context:)` fuses the tool with.
    ///
    /// - Returns: A resolver layering `skillVerbAliases` onto the upstream
    ///   defaults.
    private static func makeResolver() -> OperationResolver {
        OperationResolver(verbAliases: skillVerbAliases)
    }

    /// The verb aliases decision #21 asks for: `find`/`discover` → `search`;
    /// `call`/`run`/`invoke`/`get` → `use`.
    ///
    /// Derived from the operations' own `verb` statics so this table cannot
    /// drift from them (matches the sibling `FileTool`'s
    /// `fileVerbSelfAliases` convention).
    ///
    /// `OperationResolver.matchOpString` applies a verb alias
    /// unconditionally once one exists for a query's verb token -- it never
    /// falls back to trying the literal, unaliased verb against a
    /// same-spelled real operation. That makes this `"run": UseSkill.verb`
    /// entry a known forward tension with plan.md §7.3's future `run
    /// script` operation (M6, joining this same fused tool): once `run
    /// script` exists, a bare `run script` query would resolve here first
    /// (rewritten to `use script`, which doesn't exist) rather than to the
    /// real `run script` op, unless M6 revisits this table. Recorded (and
    /// pinned by `SkillOperationsTests`' `"run skill"` case) so that
    /// collision is caught by a test, not discovered in the field.
    private static let skillVerbAliases: [String: String] = [
        "find": SearchSkill.verb,
        "discover": SearchSkill.verb,
        "call": UseSkill.verb,
        "run": UseSkill.verb,
        "invoke": UseSkill.verb,
        "get": UseSkill.verb,
    ]
}
