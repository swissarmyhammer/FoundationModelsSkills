import FoundationModels
import Operations

/// Builds the fused schema of `SkillsCatalogTool`: the flat union of the
/// `Operations` runtime, with the `id` field made an enum of the visible
/// skill ids.
///
/// `SchemaFusion.fuse` in the `Operations` runtime gives each string field a
/// plain string schema. It does not read `ParamMeta.allowedValues`, and a
/// `ParamMeta` is static on its operation type, thus it cannot hold the ids
/// of one catalog. This builder makes the same shape as that fusion: a
/// required `op` enum of each op string in operation order, then one
/// optional field for each parameter name, ordered by the first operation
/// that declares it and then by name, with the first description on a name
/// collision. The one difference is the `id` field, which holds a skill id
/// in each operation that declares it: here it is an enum of `skillIDs`.
///
/// The root schema has no description. The tool description already holds
/// the catalog, thus the catalog is not in the prompt two times.
internal enum SkillsToolSchema {
    /// The fused field that holds a skill id in each operation that declares
    /// it.
    private static let idFieldName = "id"

    /// The description of the `op` field.
    private static let opFieldDescription = "The operation to perform, as \"verb noun\"."

    /// Builds the fused schema.
    ///
    /// - Parameters:
    ///   - name: The root type name: the tool name.
    ///   - operations: The operations of the tool, in tool order.
    ///   - skillIDs: The ids the `id` field accepts. When it is empty, the
    ///     `id` field stays a plain string, because an empty enum accepts no
    ///     value at all.
    /// - Returns: The fused schema.
    /// - Throws: `GenerationSchema.SchemaError` when FoundationModels refuses
    ///   the assembled schema.
    internal static func make(
        name: String, operations: [AnyOperation<SkillsToolContext>], skillIDs: [String]
    ) throws -> GenerationSchema {
        let opField = DynamicGenerationSchema.Property(
            name: OperationKeys.opFieldName,
            description: opFieldDescription,
            schema: DynamicGenerationSchema(
                name: OperationKeys.opFieldName, description: opFieldDescription,
                anyOf: operations.map(\.opString)),
            isOptional: false)
        let fields = fieldUnion(of: operations).map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: fieldSchema(for: parameter, skillIDs: skillIDs),
                isOptional: true)
        }
        let root = DynamicGenerationSchema(name: name, properties: [opField] + fields)
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Gives one parameter for each parameter name in `operations`, in the
    /// order of the `Operations` fusion.
    ///
    /// - Parameter operations: The operations of the tool, in tool order.
    /// - Returns: The first declaration of each name, ordered by the index
    ///   of the operation that declares it first, then by name.
    private static func fieldUnion(of operations: [AnyOperation<SkillsToolContext>]) -> [ParamMeta] {
        var seenNames: Set<String> = []
        var fields: [ParamMeta] = []
        for operation in operations {
            let newFields = operation.parameters
                .filter { seenNames.insert($0.name).inserted }
                .sorted { $0.name < $1.name }
            fields.append(contentsOf: newFields)
        }
        return fields
    }

    /// Gives the value schema of one field.
    ///
    /// - Parameters:
    ///   - parameter: The first declaration of the field.
    ///   - skillIDs: The ids the `id` field accepts.
    /// - Returns: An enum of `skillIDs` for a non-empty `id` field, otherwise
    ///   the schema of the parameter type.
    private static func fieldSchema(for parameter: ParamMeta, skillIDs: [String]) -> DynamicGenerationSchema {
        guard parameter.name == idFieldName, !skillIDs.isEmpty else {
            return typeSchema(for: parameter.type)
        }
        return DynamicGenerationSchema(name: parameter.name, description: parameter.description, anyOf: skillIDs)
    }

    /// Gives the value schema of one parameter type.
    ///
    /// - Parameter type: The parameter type.
    /// - Returns: The schema that FoundationModels uses for that type.
    private static func typeSchema(for type: ParamType) -> DynamicGenerationSchema {
        switch type {
        case .string:
            DynamicGenerationSchema(type: String.self)
        case .integer:
            DynamicGenerationSchema(type: Int.self)
        case .number:
            DynamicGenerationSchema(type: Double.self)
        case .boolean:
            DynamicGenerationSchema(type: Bool.self)
        case .array(let element):
            DynamicGenerationSchema(arrayOf: typeSchema(for: element))
        }
    }
}
