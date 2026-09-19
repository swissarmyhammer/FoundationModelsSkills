import FoundationModels
import FoundationModelsExtras
import Operations

/// The fused `skills` tool that `SkillsTool.make` gives a host: the six
/// skill operations, with the visible catalog in the description and in the
/// schema.
///
/// A model reads the name, the description, and the schema of a tool before
/// it plans. This tool puts the catalog in two of them:
///
/// - `description` holds each visible skill with its description, and the
///   rule to load a skill that matches the task (`SkillsToolDescription`).
/// - `parameters` is the fused schema of the operations, with the `id`
///   field made an enum of the visible skill ids (`SkillsToolSchema`). Thus
///   the model cannot invent an id.
///
/// Both are fixed when the tool is made. A skill that a hot reload adds is
/// found by `search skill`, but its id is not in the enum, thus the model
/// cannot load it with `use skill` until the host makes a new tool for the
/// next session. A hot reload does not rebuild this tool.
///
/// Each call goes to `operationTool`, the `OperationTool` of the
/// `Operations` runtime. It resolves the payload, dispatches the operation,
/// and keeps the retry cap.
///
/// The answer of `use skill` is plain text: the rendered body of the skill,
/// or a corrective sentence. The runtime encodes it as a JSON string, and
/// this tool gives the decoded text (`PlainTextOperations`). The answer of
/// each other operation is JSON, as the runtime gives it.
public struct SkillsCatalogTool: Tool {
    /// The raw payload: an `op` and the fields of one operation.
    public typealias Arguments = GeneratedContent

    /// The plain text of `use skill`, the JSON output of another operation,
    /// or a corrective message.
    public typealias Output = String

    /// The tool that resolves and dispatches each call.
    ///
    /// A command-line host gives it to `OperationCLIDriver`, which reads the
    /// operations from it.
    public let operationTool: OperationTool<SkillsToolContext>

    /// The ids the `id` enum of `parameters` holds, in catalog order.
    ///
    /// Empty when no skill was visible when the tool was made. The `id`
    /// field is then a plain string.
    public let skillIDs: [String]

    /// The fused schema, with the `id` field made an enum of `skillIDs`.
    public let parameters: GenerationSchema

    /// Finds the payloads of `use skill` and decodes their answers to plain
    /// text.
    private let plainTextOperations: PlainTextOperations

    /// Wraps `operationTool` and builds the schema over `skillIDs`.
    ///
    /// - Parameters:
    ///   - operationTool: The tool that resolves and dispatches each call.
    ///     Its description is the description of this tool.
    ///   - skillIDs: The visible skill ids, in catalog order.
    ///   - resolver: The resolver of `operationTool`. It finds the payloads
    ///     of `use skill` with the same rules as the dispatch.
    /// - Throws: Whatever `SkillsToolSchema.make(name:operations:skillIDs:)`
    ///   or `PlainTextOperations.init(resolver:)` throws.
    internal init(
        operationTool: OperationTool<SkillsToolContext>, skillIDs: [String], resolver: OperationResolver
    ) throws {
        self.operationTool = operationTool
        self.skillIDs = skillIDs
        parameters = try SkillsToolSchema.make(
            name: operationTool.name, operations: operationTool.operations, skillIDs: skillIDs)
        plainTextOperations = try PlainTextOperations(resolver: resolver)
    }

    /// The model-facing and command-line name of the tool: `skills`.
    public var name: String {
        operationTool.name
    }

    /// The description the model reads: the fixed sentences and the catalog.
    public var description: String {
        operationTool.description
    }

    /// Whether FoundationModels puts `parameters` into the prompt. The same
    /// value as `operationTool`.
    public var includesSchemaInInstructions: Bool {
        operationTool.includesSchemaInInstructions
    }

    /// Every operation of the tool, in tool order.
    public var operations: [AnyOperation<SkillsToolContext>] {
        operationTool.operations
    }

    /// Resolves `arguments` to one operation and dispatches it through
    /// `operationTool`.
    ///
    /// - Parameter arguments: The payload of the model or the command line.
    /// - Returns: The plain text of `use skill`, the JSON output of another
    ///   operation, or a corrective message.
    /// - Throws: Whatever `OperationTool.call(arguments:)` throws.
    public func call(arguments: GeneratedContent) async throws -> String {
        let answer = try await operationTool.call(arguments: arguments)
        return await plainTextOperations.text(of: answer, for: arguments)
    }
}

/// A child session gets the same tool. `SkillsCatalogTool` is a value type,
/// and `SkillsToolContext` is not a `ForkableContext`, thus the default
/// `forked()`, which gives back `self`, is what `operationTool.forked()`
/// gives too: the same context, shared.
extension SkillsCatalogTool: ForkableTool {}

/// A host that holds only `any Tool` gets the operations of this tool as
/// descriptors, and dispatches one operation with `perform(_:)`, through
/// `operationTool`.
extension SkillsCatalogTool: OperationDescribing {
    /// One descriptor for each operation, in tool order.
    public var operationDescriptors: [OperationDescriptor] {
        operationTool.operationDescriptors
    }

    /// Dispatches one operation through `operationTool` and throws each
    /// refusal.
    ///
    /// - Parameter arguments: The payload with the `op` key and the fields
    ///   of one operation.
    /// - Returns: The plain text of `use skill`, or the JSON output of
    ///   another operation.
    /// - Throws: Whatever `OperationTool.perform(_:)` throws.
    public func perform(_ arguments: GeneratedContent) async throws -> String {
        let answer = try await operationTool.perform(arguments)
        return await plainTextOperations.text(of: answer, for: arguments)
    }
}
