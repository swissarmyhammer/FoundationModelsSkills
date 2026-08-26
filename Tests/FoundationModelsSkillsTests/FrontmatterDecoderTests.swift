import Foundation
import FoundationModelsSkills
import Testing

/// Table-driven tests for `FrontmatterDecoder` and its `SkillFrontmatter` model
/// (plan.md §4, decision #27/#29): every spec + extension field spelling (both
/// top-level and `metadata.*`), both `arguments:` spellings, the
/// quoting-fallback retry (success and failure), and unknown-key collection.
///
/// `FrontmatterDecoder.decode(text:)` never throws (plan.md §4's lenient
/// posture) -- every case here asserts on its `Outcome`, not on a caught
/// error.
struct FrontmatterDecoderTests {
    /// Wraps `frontmatterYAML` between `---` fences with a trivial body and
    /// decodes it, unwrapping the `.decoded` case.
    ///
    /// Built by explicit `\n`-joined concatenation, never a triple-quoted
    /// literal, so the leading `---` fence line is guaranteed to carry no
    /// stray indentation (`FrontmatterDocument.split` requires the opening
    /// fence to be *exactly* `---` on the first line).
    private func decodeFrontmatter(
        _ frontmatterYAML: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> SkillFrontmatter {
        let text = "---\n" + frontmatterYAML + "\n---\nBody text.\n"
        let outcome = FrontmatterDecoder.decode(text: text)
        guard case .decoded(let skill) = outcome else {
            Issue.record("expected .decoded, got \(outcome)", sourceLocation: sourceLocation)
            throw DecodeExpectationFailure.notDecoded
        }
        return skill.frontmatter
    }

    private enum DecodeExpectationFailure: Error {
        case notDecoded
    }

    // MARK: - Spec string fields (top-level)

    @Test(
        "spec string fields decode from top level",
        arguments: [
            ("name", "my-skill"),
            ("description", "Does a thing."),
            ("license", "MIT"),
            ("compatibility", "Requires bash."),
        ])
    func specStringFieldDecodesFromTopLevel(key: String, value: String) throws {
        let frontmatter = try decodeFrontmatter("\(key): \(value)")
        switch key {
        case "name": #expect(frontmatter.name == value)
        case "description": #expect(frontmatter.description == value)
        case "license": #expect(frontmatter.license == value)
        case "compatibility": #expect(frontmatter.compatibility == value)
        default: Issue.record("unexpected key \(key)")
        }
    }

    // MARK: - allowed-tools: raw + tokenized

    @Test func allowedToolsIsKeptRawAndTokenized() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nallowed-tools: \"Read Write Script(scripts/*)\"")
        #expect(frontmatter.allowedToolsRaw == "Read Write Script(scripts/*)")
        #expect(frontmatter.allowedTools == ["Read", "Write", "Script(scripts/*)"])
    }

    @Test func allowedToolsIsEmptyWhenAbsent() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d")
        #expect(frontmatter.allowedToolsRaw == nil)
        #expect(frontmatter.allowedTools == [])
    }

    // MARK: - metadata: arbitrary value types

    @Test func metadataDecodesArbitraryValueTypes() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nmetadata:\n  foo: bar\n  count: 3\n  flag: true")
        #expect(frontmatter.metadata["foo"] == .string("bar"))
        #expect(frontmatter.metadata["count"] == .int(3))
        #expect(frontmatter.metadata["flag"] == .bool(true))
    }

    @Test func metadataIsEmptyMapWhenAbsent() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d")
        #expect(frontmatter.metadata.isEmpty)
    }

    @Test func metadataFloatDecodesAsDouble() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\nmetadata:\n  ratio: 1.5")
        #expect(frontmatter.metadata["ratio"] == .double(1.5))
    }

    // Yams reads every scalar shape it cannot classify as a string, so a
    // bare timestamp lands on `.string`, never on `FrontmatterValue`'s
    // "unrecognized YAML shape" throw -- that branch has no reachable input
    // through Yams (see ^bqjkrpc).
    @Test func metadataBareTimestampDecodesAsString() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nmetadata:\n  when: 2026-08-26T00:00:00Z")
        #expect(frontmatter.metadata["when"] == .string("2026-08-26T00:00:00Z"))
    }

    // MARK: - Extension boolean fields: top-level

    @Test(
        "extension boolean fields decode from top level",
        arguments: [
            "preload",
            "user-invocable",
            "disable-model-invocation",
            "partial",
        ])
    func extensionBooleanFieldDecodesFromTopLevel(key: String) throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\n\(key): true")
        #expect(boolField(key, of: frontmatter) == true)
    }

    // MARK: - Extension boolean fields: metadata.*

    @Test(
        "extension boolean fields decode from metadata.*",
        arguments: [
            "preload",
            "user-invocable",
            "disable-model-invocation",
            "partial",
        ])
    func extensionBooleanFieldDecodesFromMetadata(key: String) throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nmetadata:\n  \(key): true")
        #expect(boolField(key, of: frontmatter) == true)
    }

    // MARK: - Extension fields present both places: top-level wins + note

    @Test(
        "top-level wins over metadata.* on conflict and records a note",
        arguments: [
            "preload",
            "user-invocable",
            "disable-model-invocation",
            "partial",
        ])
    func topLevelWinsOverMetadataOnConflict(key: String) throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\n\(key): true\nmetadata:\n  \(key): false")
        #expect(boolField(key, of: frontmatter) == true)
        #expect(frontmatter.notes.contains { $0.contains(key) })
    }

    // `arguments` and `argument-hint` aren't `Bool`, so they can't join the
    // table above -- covered individually here, same both-present-wins-with-
    // a-note contract (plan.md §4: every extension field is resolved the
    // same way).

    @Test func topLevelArgumentsWinsOverMetadataOnConflictAndRecordsANote() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\narguments: message env\nmetadata:\n  arguments: other")
        #expect(frontmatter.arguments == ["message", "env"])
        #expect(frontmatter.notes.contains { $0.contains("arguments") })
    }

    @Test func topLevelArgumentHintWinsOverMetadataOnConflictAndRecordsANote() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nargument-hint: \"<message>\"\nmetadata:\n  argument-hint: \"<other>\""
        )
        #expect(frontmatter.argumentHint == "<message>")
        #expect(frontmatter.notes.contains { $0.contains("argument-hint") })
    }

    // MARK: - Extension fields present under metadata.* with the wrong type: advisory note

    @Test(
        "a mistyped boolean extension field under metadata.* draws an advisory note and is ignored",
        arguments: [
            "preload",
            "user-invocable",
            "disable-model-invocation",
            "partial",
        ])
    func mistypedBooleanExtensionFieldUnderMetadataRecordsANoteAndIsIgnored(key: String) throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nmetadata:\n  \(key): \"true\"")
        #expect(boolField(key, of: frontmatter) == nil)
        #expect(frontmatter.notes.contains { $0.contains("metadata.\(key)") })
    }

    @Test func mistypedArgumentsUnderMetadataRecordsANoteAndIsIgnored() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\nmetadata:\n  arguments: 42")
        #expect(frontmatter.argumentsRaw == nil)
        #expect(frontmatter.notes.contains { $0.contains("metadata.arguments") })
    }

    @Test func mistypedTopLevelArgumentsRecordsANoteAndIsIgnored() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\narguments: 42")
        #expect(frontmatter.argumentsRaw == nil)
        #expect(frontmatter.notes.contains { $0.contains("'arguments'") })
    }

    @Test(
        "null arguments (top-level or under metadata.*) record no mismatch note",
        arguments: [
            "name: x\ndescription: d\narguments: ~",
            "name: x\ndescription: d\nmetadata:\n  arguments: ~",
        ])
    func nullArgumentsRecordsNoMismatchNote(yaml: String) throws {
        let frontmatter = try decodeFrontmatter(yaml)
        #expect(frontmatter.argumentsRaw == nil)
        #expect(frontmatter.notes.isEmpty)
    }

    @Test func mistypedArgumentHintUnderMetadataRecordsANoteAndIsIgnored() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\nmetadata:\n  argument-hint: 42")
        #expect(frontmatter.argumentHint == nil)
        #expect(frontmatter.notes.contains { $0.contains("metadata.argument-hint") })
    }

    @Test(
        "a correctly-typed boolean extension field under metadata.* draws no mistyped-value note",
        arguments: [
            "preload",
            "user-invocable",
            "disable-model-invocation",
            "partial",
        ])
    func correctlyTypedBooleanExtensionFieldUnderMetadataRecordsNoMismatchNote(key: String) throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\nmetadata:\n  \(key): true")
        #expect(!frontmatter.notes.contains { $0.contains("metadata.\(key)") })
    }

    @Test func nullExtensionFieldUnderMetadataRecordsNoMismatchNote() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\nmetadata:\n  preload: ~")
        #expect(frontmatter.preload == nil)
        #expect(frontmatter.notes.isEmpty)
    }

    // MARK: - argument-hint: top-level and metadata.*

    @Test func argumentHintDecodesFromTopLevel() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nargument-hint: \"<message>\"")
        #expect(frontmatter.argumentHint == "<message>")
    }

    @Test func argumentHintDecodesFromMetadata() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nmetadata:\n  argument-hint: \"<message>\"")
        #expect(frontmatter.argumentHint == "<message>")
    }

    // MARK: - arguments: both spellings, top-level

    @Test(
        "arguments accepts both the space-separated string and YAML-list spellings at top level",
        arguments: [
            "name: x\ndescription: d\narguments: message env",
            "name: x\ndescription: d\narguments:\n  - message\n  - env",
        ])
    func argumentsAcceptsBothSpellingsAtTopLevel(yaml: String) throws {
        let frontmatter = try decodeFrontmatter(yaml)
        #expect(frontmatter.arguments == ["message", "env"])
    }

    // MARK: - arguments: both spellings, metadata.*

    @Test(
        "arguments accepts both the space-separated string and YAML-list spellings under metadata.*",
        arguments: [
            "name: x\ndescription: d\nmetadata:\n  arguments: message env",
            "name: x\ndescription: d\nmetadata:\n  arguments:\n    - message\n    - env",
        ])
    func argumentsAcceptsBothSpellingsUnderMetadata(yaml: String) throws {
        let frontmatter = try decodeFrontmatter(yaml)
        #expect(frontmatter.arguments == ["message", "env"])
    }

    @Test func argumentsIsEmptyWhenAbsent() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d")
        #expect(frontmatter.arguments == [])
    }

    @Test func bareIntegerArgumentsDecodesAndTokenizesToEmpty() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\narguments: 42")
        #expect(frontmatter.arguments == [])
    }

    // `argumentsRaw` is a public stored property, so a caller can hold a
    // shape `init(from:)` would have dropped -- tokenizing must still give
    // an empty list rather than fail.
    @Test(
        "arguments tokenizes to empty for every non-string, non-list raw value",
        arguments: [
            FrontmatterValue.int(42),
            .double(1.5),
            .bool(true),
            .dictionary(["key": .string("value")]),
            .null,
        ])
    func nonTokenizableArgumentsRawTokenizesToEmpty(raw: FrontmatterValue) {
        let frontmatter = SkillFrontmatter(argumentsRaw: raw)
        #expect(frontmatter.arguments == [])
    }

    // MARK: - Unknown top-level keys: collected, never fatal

    @Test func unknownTopLevelKeysAreCollectedNeverFatal() throws {
        let frontmatter = try decodeFrontmatter(
            "name: x\ndescription: d\nfrobnicate: true\nwidget: 1")
        #expect(Set(frontmatter.unknownTopLevelKeys) == Set(["frobnicate", "widget"]))
    }

    @Test func unknownTopLevelKeysIsEmptyWhenAllKeysAreKnown() throws {
        let frontmatter = try decodeFrontmatter("name: x\ndescription: d\npreload: true")
        #expect(frontmatter.unknownTopLevelKeys.isEmpty)
    }

    // MARK: - Retry: success against the real broken/ fixture

    @Test func brokenBadColonDescriptionFixtureDecodesViaQuotingFallbackRetry() throws {
        let text = try String(
            contentsOf: FixtureLibrary.url(relativePath: "broken/bad-colon-description/SKILL.md"),
            encoding: .utf8)
        let outcome = FrontmatterDecoder.decode(text: text)
        guard case .decoded(let skill) = outcome else {
            Issue.record("expected .decoded via quoting-fallback retry, got \(outcome)")
            return
        }
        #expect(skill.frontmatter.name == "bad-colon-description")
        #expect(
            skill.frontmatter.description
                == "Deploy to staging: verify smoke tests pass first, then promote.")
        #expect(skill.notes.contains { $0.localizedCaseInsensitiveContains("retry") })
    }

    // MARK: - Retry: attempted but still fails -> skipped, never throws

    @Test func retryIsAttemptedButStillFailsYieldsSkippedWithDiagnostic() {
        let text =
            "---\nname: broken\ndescription: Has a colon: here\nbogus: [1, 2\n---\nBody.\n"
        let outcome = FrontmatterDecoder.decode(text: text)
        guard case .skipped(let reason) = outcome else {
            Issue.record("expected .skipped, got \(outcome)")
            return
        }
        // Distinguishes this from the immediate-skip path (no `description:`
        // line at all, covered separately below): this input DOES have an
        // unquoted-colon `description:` line, so the retry must actually
        // fire (and still fail, thanks to the unrelated unclosed `bogus:`
        // sequence) -- the reason text says so.
        #expect(reason.localizedCaseInsensitiveContains("retry"))
    }

    // MARK: - Truly unparseable, no description: line at all -> skipped, never throws

    @Test func trulyUnparseableYAMLWithNoDescriptionLineSkipsWithoutThrowing() {
        let text = "---\nname: [unterminated\n---\nBody.\n"
        let outcome = FrontmatterDecoder.decode(text: text)
        guard case .skipped(let reason) = outcome else {
            Issue.record("expected .skipped, got \(outcome)")
            return
        }
        #expect(!reason.isEmpty)
    }

    // MARK: - No frontmatter block at all: decodes to empty fields, never skipped

    @Test func noFrontmatterBlockDecodesToEmptyFieldsNeverSkipped() {
        let outcome = FrontmatterDecoder.decode(text: "Just a body, no frontmatter fence.\n")
        guard case .decoded(let skill) = outcome else {
            Issue.record("expected .decoded, got \(outcome)")
            return
        }
        #expect(skill.frontmatter.name == nil)
        #expect(skill.frontmatter.description == nil)
        #expect(skill.body == "Just a body, no frontmatter fence.\n")
    }

    // MARK: - Helpers

    /// Reads the named boolean extension field off `frontmatter` by key
    /// spelling, so the parameterized tests above can assert generically.
    private func boolField(_ key: String, of frontmatter: SkillFrontmatter) -> Bool? {
        switch key {
        case "preload": return frontmatter.preload
        case "user-invocable": return frontmatter.userInvocable
        case "disable-model-invocation": return frontmatter.disableModelInvocation
        case "partial": return frontmatter.partial
        default:
            Issue.record("unexpected key \(key)")
            return nil
        }
    }
}
