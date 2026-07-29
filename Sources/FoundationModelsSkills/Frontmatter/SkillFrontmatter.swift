/// A YAML scalar/collection value, used for `SkillFrontmatter.metadata`'s
/// arbitrary-typed values and for `arguments:`'s dual spelling (a
/// space-separated string or a YAML list) -- this package's own YAML-value
/// tree (plan.md decision #27/#29: YAML decoding is ours, with Yams; Extras'
/// `FrontmatterDocument` only does the textual frontmatter/body split).
///
/// `indirect` because `.array`/`.dictionary` recursively contain
/// `FrontmatterValue` -- an ordinary (non-indirect) enum cannot store itself.
public indirect enum FrontmatterValue: Sendable, Equatable, Decodable {
    /// A YAML string scalar.
    case string(String)
    /// A YAML integer scalar.
    case int(Int)
    /// A YAML floating-point scalar.
    case double(Double)
    /// A YAML boolean scalar.
    case bool(Bool)
    /// A YAML sequence.
    case array([FrontmatterValue])
    /// A YAML mapping, keyed by string.
    case dictionary([String: FrontmatterValue])
    /// YAML's explicit or implicit null (`~`, `null`, or an empty scalar).
    case null

    /// Decodes a value of unknown shape by trying each case in turn --
    /// `Bool` before `Int`/`Double` so a boolean scalar is never
    /// misclassified as a number, and scalars before collections.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FrontmatterValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: FrontmatterValue].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not decode FrontmatterValue: unrecognized YAML shape."))
        }
    }
}

extension FrontmatterValue {
    /// This value as a `Bool`, or `nil` if it is not `.bool`.
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// This value as a `String`, or `nil` if it is not `.string`.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The space-separated tokens of this value: `.string` splits on
    /// whitespace; `.array` takes each `.string` element verbatim (order
    /// preserved, non-string elements skipped); anything else tokenizes to
    /// empty. Shared by `allowed-tools:` and `arguments:`, both of which
    /// accept the same two spellings (plan.md §4).
    var spaceSeparatedOrListTokens: [String] {
        switch self {
        case .string(let raw):
            return raw.split(whereSeparator: \.isWhitespace).map(String.init)
        case .array(let items):
            return items.compactMap(\.stringValue)
        default:
            return []
        }
    }
}

/// Decoded frontmatter for one skill -- every agentskills.io spec field plus
/// every one of this package's Claude-compatible extension fields (plan.md
/// §4, decision #27/#29).
///
/// **Spec fields** (`name`, `description`, `license`, `compatibility`,
/// `allowed-tools`, `metadata`) live only at the top level, per the spec.
///
/// **Extension fields** (`preload`, `user-invocable`,
/// `disable-model-invocation`, `arguments`, `argument-hint`, and the retired
/// `partial`) are accepted **both** top-level (this package's canonical
/// spelling, #5) **and** under `metadata.*` (the spec's designated home for
/// client-defined properties, generalizing #5 into #27) -- when both are
/// present for the same field, the top-level value wins and a note is
/// recorded in `notes` (surfaced by `FrontmatterDecoder` as part of a
/// `DecodedSkill`).
///
/// Unknown top-level keys are collected into `unknownTopLevelKeys`, never
/// fatal -- lenient validation loads the skill anyway (plan.md §4).
///
/// This type only decodes; it enforces none of the spec's own rules (required
/// `description`, `name == directoryName`, etc.) -- that is the downstream
/// validator's job, per this task's own scope note.
public struct SkillFrontmatter: Sendable, Equatable {
    // MARK: - Spec fields (top-level only)

    /// The frontmatter `name:` -- compared against the directory name by the
    /// validator (plan.md §4); never the canonical id itself.
    public var name: String?
    /// The frontmatter `description:` -- required by the spec; its
    /// presence/length rules are enforced downstream.
    public var description: String?
    /// The frontmatter `license:` -- free text, data only.
    public var license: String?
    /// The frontmatter `compatibility:` -- free text, data only.
    public var compatibility: String?
    /// The raw, untokenized `allowed-tools:` value, exactly as authored.
    public var allowedToolsRaw: String?
    /// The `metadata:` mapping, keyed by string, values of arbitrary YAML
    /// shape -- both the spec's own client-defined-property bag and this
    /// package's fallback home for extension fields. Empty (never `nil`)
    /// when the key is absent.
    public var metadata: [String: FrontmatterValue]

    // MARK: - Extension fields (top-level canonical, resolved against metadata.*)

    /// `preload:` -- resolved: top-level wins over `metadata.preload` when
    /// both are present (a note is recorded in `notes`).
    public var preload: Bool?
    /// `user-invocable:` -- resolved the same way as `preload`.
    public var userInvocable: Bool?
    /// `disable-model-invocation:` -- resolved the same way as `preload`.
    public var disableModelInvocation: Bool?
    /// The resolved, untokenized `arguments:` value (string or YAML list) --
    /// resolved the same way as `preload`. Use `arguments` for the tokenized
    /// list.
    public var argumentsRaw: FrontmatterValue?
    /// `argument-hint:` -- resolved the same way as `preload`.
    public var argumentHint: String?
    /// The retired `partial:` flag (plan.md decision #29) -- resolved the
    /// same way as `preload`; still decoded (never fatal) so a diagnostic can
    /// be raised downstream.
    public var partial: Bool?

    // MARK: - Diagnostics

    /// Top-level keys this decoder does not recognize, sorted for
    /// determinism -- collected, never fatal (plan.md §4).
    public var unknownTopLevelKeys: [String]
    /// Diagnostic-worthy notes accumulated while decoding this frontmatter,
    /// currently just the "present both top-level and under metadata.*"
    /// conflict case. `FrontmatterDecoder` folds these into a
    /// `DecodedSkill`'s own `notes` (which may add a quoting-fallback-retry
    /// note of its own).
    public var notes: [String]

    /// The tokenized `allowed-tools:` value -- whitespace-separated, empty
    /// when `allowedToolsRaw` is `nil`.
    public var allowedTools: [String] {
        (allowedToolsRaw ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The tokenized `arguments:` value -- accepts both the space-separated
    /// string and YAML-list spellings (plan.md §4), empty when
    /// `argumentsRaw` is `nil`.
    public var arguments: [String] {
        argumentsRaw?.spaceSeparatedOrListTokens ?? []
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        license: String? = nil,
        compatibility: String? = nil,
        allowedToolsRaw: String? = nil,
        metadata: [String: FrontmatterValue] = [:],
        preload: Bool? = nil,
        userInvocable: Bool? = nil,
        disableModelInvocation: Bool? = nil,
        argumentsRaw: FrontmatterValue? = nil,
        argumentHint: String? = nil,
        partial: Bool? = nil,
        unknownTopLevelKeys: [String] = [],
        notes: [String] = []
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.allowedToolsRaw = allowedToolsRaw
        self.metadata = metadata
        self.preload = preload
        self.userInvocable = userInvocable
        self.disableModelInvocation = disableModelInvocation
        self.argumentsRaw = argumentsRaw
        self.argumentHint = argumentHint
        self.partial = partial
        self.unknownTopLevelKeys = unknownTopLevelKeys
        self.notes = notes
    }
}

extension SkillFrontmatter: Decodable {
    /// A `CodingKey` accepting any string -- lets `init(from:)` both look up
    /// known field spellings by name and enumerate every key actually
    /// present, for `unknownTopLevelKeys`.
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Every top-level key this decoder recognizes -- spec fields plus
    /// extension-field spellings. Anything else lands in
    /// `unknownTopLevelKeys`.
    private static let knownTopLevelKeys: Set<String> = [
        "name", "description", "license", "compatibility", "allowed-tools", "metadata",
        "preload", "user-invocable", "disable-model-invocation", "arguments", "argument-hint",
        "partial",
    ]

    /// Extension-field spellings, shared between top-level lookup and
    /// `metadata.*` lookup so the two stay in lockstep.
    private enum ExtensionKey: String {
        case preload
        case userInvocable = "user-invocable"
        case disableModelInvocation = "disable-model-invocation"
        case arguments
        case argumentHint = "argument-hint"
        case partial
    }

    /// Resolves one extension field between its top-level value and its
    /// `metadata.*` value: top-level wins on conflict, recording a note; only
    /// `metadata.*` present -> its value; neither -> `nil`.
    private static func resolvedExtensionField<T>(
        _ key: ExtensionKey, topLevel: T?, metadataValue: T?, notes: inout [String]
    ) -> T? {
        guard let topLevel else { return metadataValue }
        if metadataValue != nil {
            notes.append(
                "'\(key.rawValue)' is set both top-level and under metadata.\(key.rawValue); "
                    + "using the top-level value.")
        }
        return topLevel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        name = try container.decodeIfPresent(String.self, forKey: AnyCodingKey(stringValue: "name"))
        description = try container.decodeIfPresent(
            String.self, forKey: AnyCodingKey(stringValue: "description"))
        license = try container.decodeIfPresent(
            String.self, forKey: AnyCodingKey(stringValue: "license"))
        compatibility = try container.decodeIfPresent(
            String.self, forKey: AnyCodingKey(stringValue: "compatibility"))
        allowedToolsRaw = try container.decodeIfPresent(
            String.self, forKey: AnyCodingKey(stringValue: "allowed-tools"))
        metadata =
            try container.decodeIfPresent(
                [String: FrontmatterValue].self, forKey: AnyCodingKey(stringValue: "metadata"))
            ?? [:]

        let topLevelPreload = try container.decodeIfPresent(
            Bool.self, forKey: AnyCodingKey(stringValue: ExtensionKey.preload.rawValue))
        let topLevelUserInvocable = try container.decodeIfPresent(
            Bool.self, forKey: AnyCodingKey(stringValue: ExtensionKey.userInvocable.rawValue))
        let topLevelDisableModelInvocation = try container.decodeIfPresent(
            Bool.self,
            forKey: AnyCodingKey(stringValue: ExtensionKey.disableModelInvocation.rawValue))
        let topLevelArguments = try container.decodeIfPresent(
            FrontmatterValue.self, forKey: AnyCodingKey(stringValue: ExtensionKey.arguments.rawValue))
        let topLevelArgumentHint = try container.decodeIfPresent(
            String.self, forKey: AnyCodingKey(stringValue: ExtensionKey.argumentHint.rawValue))
        let topLevelPartial = try container.decodeIfPresent(
            Bool.self, forKey: AnyCodingKey(stringValue: ExtensionKey.partial.rawValue))

        var notes: [String] = []
        preload = Self.resolvedExtensionField(
            .preload, topLevel: topLevelPreload,
            metadataValue: metadata[ExtensionKey.preload.rawValue]?.boolValue, notes: &notes)
        userInvocable = Self.resolvedExtensionField(
            .userInvocable, topLevel: topLevelUserInvocable,
            metadataValue: metadata[ExtensionKey.userInvocable.rawValue]?.boolValue, notes: &notes)
        disableModelInvocation = Self.resolvedExtensionField(
            .disableModelInvocation, topLevel: topLevelDisableModelInvocation,
            metadataValue: metadata[ExtensionKey.disableModelInvocation.rawValue]?.boolValue,
            notes: &notes)
        argumentsRaw = Self.resolvedExtensionField(
            .arguments, topLevel: topLevelArguments,
            metadataValue: metadata[ExtensionKey.arguments.rawValue], notes: &notes)
        argumentHint = Self.resolvedExtensionField(
            .argumentHint, topLevel: topLevelArgumentHint,
            metadataValue: metadata[ExtensionKey.argumentHint.rawValue]?.stringValue, notes: &notes)
        partial = Self.resolvedExtensionField(
            .partial, topLevel: topLevelPartial,
            metadataValue: metadata[ExtensionKey.partial.rawValue]?.boolValue, notes: &notes)

        self.notes = notes
        self.unknownTopLevelKeys =
            container.allKeys
            .map(\.stringValue)
            .filter { !Self.knownTopLevelKeys.contains($0) }
            .sorted()
    }
}
