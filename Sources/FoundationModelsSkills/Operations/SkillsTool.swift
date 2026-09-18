import FoundationModels
import Operations

/// Builds the fused `skills` tool: `SearchSkill`, `ListSkill`, `UseSkill`,
/// and the three resource operations presented to a model (or the CLI) as
/// one `SkillsCatalogTool` over one `OperationTool` (plan.md §7, decision
/// #20).
///
/// The forgiving op/parameter resolution and the return-don't-throw retry
/// cap are inherited from the upstream `Operations` runtime. This type
/// supplies the operation set, the verb aliases decision #21 asks for, and
/// the catalog: the tool description and the `id` enum of the schema.
public enum SkillsTool {
    /// The fused tool's model- and CLI-facing name.
    private static let toolName = "skills"

    /// The default `catalogCharacterLimit` of every `make` factory: the most
    /// characters the catalog list of the tool description may have.
    ///
    /// 8,000 characters is the value Codex uses when it does not know the
    /// size of the context window.
    public static let defaultCatalogCharacterLimit = 8_000

    /// Builds the fused `skills` tool over `context`.
    ///
    /// The six operations dispatch through `AnyOperation` against the
    /// shared `context`, in the order `search` / `list` / `use` / `list
    /// resource` / `read resource` / `run script` -- the order the fused
    /// schema's `op` enum and any unknown-operation corrective list them in.
    ///
    /// The description and the `id` enum of the schema come from the
    /// catalog one time, here: `context.registry.metadata()`, filtered by
    /// `context.visibilityPredicate`, in catalog order. A hot reload does not
    /// change them. See `SkillsCatalogTool`.
    ///
    /// - Parameters:
    ///   - context: The shared context every operation's `execute(in:)` runs
    ///     against.
    ///   - catalogCharacterLimit: The most characters the catalog list of
    ///     the description may have. Defaults to
    ///     `defaultCatalogCharacterLimit`. See `SkillsToolDescription` for
    ///     the steps that make a large catalog fit.
    /// - Returns: The fused `skills` tool, ready to register on a
    ///   `LanguageModelSession`. A command-line host drives
    ///   `SkillsCatalogTool.operationTool`.
    /// - Throws: `SchemaFusionError.reservedParameterName` if an operation
    ///   declares a parameter colliding with the `op` discriminator (not
    ///   expected for this fixed operation set, but propagated per
    ///   `OperationTool.init`'s contract); rethrows `GenerationSchema.SchemaError`
    ///   on any other schema-fusion failure.
    public static func make(
        context: SkillsToolContext, catalogCharacterLimit: Int = defaultCatalogCharacterLimit
    ) throws -> SkillsCatalogTool {
        let catalog = context.registry.metadata().filter(context.visibilityPredicate)
        let operationTool = try OperationTool(
            name: toolName,
            description: SkillsToolDescription.make(catalog: catalog, characterLimit: catalogCharacterLimit),
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
        return try SkillsCatalogTool(operationTool: operationTool, skillIDs: catalog.map(\.id))
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
