import FoundationModels
import FoundationModelsExtras
import Operations

/// Builds the fused `skills` tool: `SearchSkill`, `ListSkill`, `UseSkill`,
/// the three resource operations, and the three write operations
/// (`AddSkill`, `EditSkill`, `RemoveSkill`) presented to a model (or the CLI)
/// as one `SkillsCatalogTool` over one `OperationTool`.
///
/// The forgiving op/parameter resolution and the return-don't-throw retry
/// cap are inherited from the upstream `Operations` runtime. This type
/// supplies the operation set, the verb aliases, and the catalog of the
/// tool description. The `id` field of the schema is a plain string.
public enum SkillsTool {
    /// The fused tool's model- and CLI-facing name.
    ///
    /// `SkillCatalogText` names the tool in the load instruction of a
    /// `search skill` or `list skill` answer.
    internal static let toolName = "skills"

    /// The default `catalogCharacterLimit` of every `make` factory: the most
    /// characters the catalog list of the tool description may have.
    ///
    /// 8,000 characters is the value Codex uses when it does not know the
    /// size of the context window.
    public static let defaultCatalogCharacterLimit = 8_000

    /// Builds the fused `skills` tool over `context`.
    ///
    /// The operations dispatch through `AnyOperation` against the shared
    /// `context`, in the order `search` / `list` / `use` / `list resource` /
    /// `read resource` / `run script` / `add skill` / `edit skill` / `remove
    /// skill` -- the order the fused schema's `op` enum and any
    /// unknown-operation corrective list them in.
    ///
    /// `context.mode` picks the set. In `ToolMode.open` the tool has all nine
    /// operations. In `ToolMode.sandboxed` it has no `run script`: the App
    /// Sandbox does not let a script of a skill run, thus the schema, the
    /// unknown-operation corrective and the description do not name it.
    ///
    /// The description comes from the catalog one time, here:
    /// `context.registry.metadata()`, filtered by
    /// `context.visibilityPredicate`, in catalog order. A hot reload does not
    /// change it, and it does not change the schema. The `id` field of the
    /// schema is a plain string, thus a skill that a hot reload adds loads
    /// with `use skill` in the same session. See `SkillsCatalogTool`.
    ///
    /// The tool gets `context.catalogNoticeBoard`. Thus each tool made from
    /// one context shares one board, and a session learns of a reload from
    /// the one notice that `context.catalogNoticeFollower` posts there.
    ///
    /// The tool also gets the `skills` GraphQL endpoint (`SkillsGraph`) over
    /// `context.registry`, made one time here. Each copy and each fork of
    /// the tool gives that same endpoint through `GraphQLEndpointTool`.
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
    ///   on any other schema-fusion failure, and an error of the GraphQL
    ///   schema builder from `SkillsGraph.init(registry:)`.
    public static func make(
        context: SkillsToolContext, catalogCharacterLimit: Int = defaultCatalogCharacterLimit
    ) throws -> SkillsCatalogTool {
        let catalog = context.registry.metadata().filter(context.visibilityPredicate)
        return try SkillsCatalogTool(
            context: context, name: toolName,
            description: SkillsToolDescription.make(catalog: catalog, characterLimit: catalogCharacterLimit),
            operations: operations(for: context.mode), resolver: makeResolver(), skillIDs: catalog.map(\.id),
            skillsGraph: SkillsGraph(registry: context.registry))
    }

    /// The operations of the tool in `mode`, in schema order.
    ///
    /// - Parameter mode: The mode of the tools of the host.
    /// - Returns: All nine operations in `ToolMode.open`; each operation but
    ///   `RunScript` in `ToolMode.sandboxed`.
    private static func operations(for mode: ToolMode) -> [AnyOperation<SkillsToolContext>] {
        let scriptOperations = mode == .open ? [AnyOperation(RunScript.self)] : []
        return [
            AnyOperation(SearchSkill.self),
            AnyOperation(ListSkill.self),
            AnyOperation(UseSkill.self),
            AnyOperation(ListResource.self),
            AnyOperation(ReadResource.self),
        ] + scriptOperations + [
            AnyOperation(AddSkill.self),
            AnyOperation(EditSkill.self),
            AnyOperation(RemoveSkill.self),
        ]
    }

    /// Builds the forgiving resolver `make(context:)` fuses the tool with.
    ///
    /// - Returns: A resolver layering `verbAliasOverrides` onto the upstream
    ///   defaults.
    private static func makeResolver() -> OperationResolver {
        OperationResolver(verbAliases: verbAliasOverrides)
    }

    /// The verb aliases this tool's operation set needs, layered onto
    /// `OperationResolver.defaultVerbAliases`: `find`/
    /// `discover` → `search`, `call`/`invoke`/`get` → `use`, `update` →
    /// `edit`, plus a `"read"` self-mapping override (below) `ReadResource`
    /// needs to be reachable at all, and the `remove` overrides (below) that
    /// `RemoveSkill` needs.
    ///
    /// Derived from the operations' own `verb` statics so this table cannot
    /// drift from them (matches the sibling `FileTool`'s
    /// `fileVerbSelfAliases` convention).
    ///
    /// `OperationResolver.matchOpString` applies a verb alias
    /// unconditionally once one exists for a query's verb token -- it never
    /// falls back to trying the literal, unaliased verb against a
    /// same-spelled real operation. Thus `run` is not a `use` synonym: a
    /// `"run": UseSkill.verb` entry would rewrite a literal `"run script"`
    /// query to `"use script"` (which does not exist) before it reaches
    /// `RunScript`. `"run skill"` does not resolve (pinned by
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
    ///
    /// The same rule holds for `RemoveSkill`. The defaults map `remove`,
    /// `rm` and `del` to `delete`, and no operation here has the verb
    /// `delete`. Thus `"remove"` maps to itself, and `delete`, `rm` and `del`
    /// map to `remove`. The default `create`/`new` → `add` aliases reach
    /// `AddSkill` with no override. No default maps `edit` or `update`, thus
    /// `update` → `edit` is safe: no operation has the verb `update`. Pinned
    /// by `SkillOperationsTests`.
    private static let verbAliasOverrides: [String: String] = [
        "find": SearchSkill.verb,
        "discover": SearchSkill.verb,
        "call": UseSkill.verb,
        "invoke": UseSkill.verb,
        "get": UseSkill.verb,
        "read": ReadResource.verb,
        "update": EditSkill.verb,
        "remove": RemoveSkill.verb,
        "delete": RemoveSkill.verb,
        "rm": RemoveSkill.verb,
        "del": RemoveSkill.verb,
    ]
}
