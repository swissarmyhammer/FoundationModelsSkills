import FoundationModels
import Operations

/// Builds the fused schema of `SkillsCatalogTool`: the flat union of the
/// `Operations` runtime, with no root description.
///
/// `SchemaFusion.fuse` builds the shape: a required `op` enum of each op
/// string in operation order, then one optional field for each parameter
/// name. The `id` field is a plain string, as each other string field is.
/// It is not an enum of the visible skill ids. A skill that a hot reload
/// adds is then loadable in the same session, and the schema stays the
/// same for the whole session. The live registry checks the id at call
/// time, and an unusable id gets the corrective of `UnusableSkillIDText`.
///
/// The root schema has no description. The tool description already holds
/// the catalog, thus the catalog is not in the prompt two times.
internal enum SkillsToolSchema {
    /// Builds the fused schema.
    ///
    /// - Parameters:
    ///   - name: The root type name: the tool name.
    ///   - operations: The operations of the tool, in tool order.
    /// - Returns: The fused schema.
    /// - Throws: Whatever `SchemaFusion.fuse(_:name:description:)` throws.
    internal static func make(name: String, operations: [AnyOperation<SkillsToolContext>]) throws -> GenerationSchema {
        try SchemaFusion.fuse(operations, name: name)
    }
}
