import Foundation
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Table-driven tests for `ArgumentSubstitution`, pass 1 of the §5 render pipeline (plan.md
/// §5): every `$`-token form, the shell-style quoting tokenizer that derives positional args,
/// the `\$` escape, the `$ARGUMENTS` auto-append matrix, missing-reference handling, and the
/// single-shot no-re-scan invariant -- plus an end-to-end render of the `commit` fixture.
struct ArgumentSubstitutionTests {
    private let pass = ArgumentSubstitution()

    /// Builds a `RenderRequest` with sensible fixed defaults -- callers override only the
    /// fields the test cares about. Mirrors `RenderPipelineTests`' own helper.
    private func request(
        text: String, arguments: [String] = [], argumentNames: [String] = []
    ) -> RenderRequest {
        RenderRequest(
            text: text,
            arguments: arguments,
            argumentNames: argumentNames,
            skillDirectory: URL(
                fileURLWithPath: "/tmp/argument-substitution-tests/skill", isDirectory: true),
            winningLayer: DotfolderStack.Layer(
                source: .project,
                root: URL(
                    fileURLWithPath: "/tmp/argument-substitution-tests/.skills", isDirectory: true)),
            policy: RenderPolicy())
    }

    /// Runs `pass.render` over `text` with the given arguments/names, using `text` itself as
    /// both the render input and `RenderRequest.text` -- matches how `RenderPipeline` always
    /// invokes pass 1 first, on the request's original text.
    private func render(
        _ text: String, arguments: [String] = [], argumentNames: [String] = []
    ) throws -> String {
        try pass.render(
            QuarantinedText(original: text),
            request: request(text: text, arguments: arguments, argumentNames: argumentNames)
        ).flattened
    }

    // MARK: - Every $-token form

    @Test(
        "each $-token form substitutes its expected value",
        arguments: [
            (
                name: "$ARGUMENTS bare joins all args as typed",
                body: "$ARGUMENTS", arguments: ["fix", "the bug"], argumentNames: [String](),
                expected: "fix the bug"
            ),
            (
                name: "$ARGUMENTS[0] is 0-based positional",
                body: "$ARGUMENTS[0]", arguments: ["one", "two"], argumentNames: [String](),
                expected: "one"
            ),
            (
                name: "$ARGUMENTS[1] is 0-based positional",
                body: "$ARGUMENTS[1]", arguments: ["one", "two"], argumentNames: [String](),
                expected: "two"
            ),
            (
                name: "$0 is the first positional arg",
                body: "$0", arguments: ["one", "two"], argumentNames: [String](), expected: "one"
            ),
            (
                name: "$1 is the second positional arg",
                body: "$1", arguments: ["one", "two"], argumentNames: [String](), expected: "two"
            ),
            (
                name: "$name resolves through argumentNames position",
                body: "$message", arguments: ["hello"], argumentNames: ["message"],
                expected: "hello"
            ),
            (
                name: "${SKILL_DIR} resolves to the skill directory path",
                body: "${SKILL_DIR}", arguments: [String](), argumentNames: [String](),
                expected: "/tmp/argument-substitution-tests/skill"
            ),
        ])
    func tokenFormSubstitutesExpectedValue(
        name: String, body: String, arguments: [String], argumentNames: [String], expected: String
    ) throws {
        // `hasPrefix`, not `==`: several rows here supply non-empty `arguments` on a body with
        // no bare `$ARGUMENTS` reference, which correctly triggers the auto-append fallback
        // (its own matrix is covered separately below) -- this test cares about the substituted
        // prefix, not that unrelated suffix.
        let result = try render(body, arguments: arguments, argumentNames: argumentNames)
        #expect(result.hasPrefix(expected), "\(name)")
    }

    // MARK: - Shell-style quoting for positional splitting

    @Test(
        "positional args are pre-split with shell-style quoting",
        arguments: [
            (
                name: "unquoted single token",
                rawArgument: "hello", expected: "hello"
            ),
            (
                name: "double-quoted multi-word token",
                rawArgument: "\"hello world\"", expected: "hello world"
            ),
            (
                name: "single-quoted multi-word token",
                rawArgument: "'hello world'", expected: "hello world"
            ),
            (
                name: "backslash-escaped space outside quotes stays one token",
                rawArgument: "hello\\ world", expected: "hello world"
            ),
            (
                name: "backslash-escaped quote inside double quotes",
                rawArgument: #""say \"hi\"""#, expected: #"say "hi""#
            ),
            (
                name: "single quotes never process escapes",
                rawArgument: #"'no \n escape'"#, expected: #"no \n escape"#
            ),
        ])
    func positionalSplittingHandlesShellStyleQuoting(name: String, rawArgument: String, expected: String)
        throws
    {
        // `hasPrefix`: a non-empty `arguments` with no bare `$ARGUMENTS` in the body triggers
        // the auto-append fallback, tested separately below.
        let result = try render("$0", arguments: [rawArgument])
        #expect(result.hasPrefix(expected), "\(name)")
    }

    @Test func quotedFirstTokenAndTrailingTokenSplitIntoSeparatePositions() throws {
        let result = try render("$0|$1", arguments: ["\"fix the bug\" --amend"])
        #expect(result.hasPrefix("fix the bug|--amend"))
    }

    // MARK: - \$ escape

    @Test func escapedDollarSurvivesAsLiteralDollarSign() throws {
        let result = try render("\\$HOME")
        #expect(result == "$HOME")
    }

    @Test func unescapedDollarNameNotInArgumentNamesIsUntouched() throws {
        let result = try render("$HOME")
        #expect(result == "$HOME")
    }

    @Test func escapedDollarNeverSubstitutesEvenWhenNameIsDeclared() throws {
        let result = try render("\\$message", arguments: ["hello"], argumentNames: ["message"])
        #expect(result.hasPrefix("$message"))
    }

    // MARK: - ${VAR} whose name is not a special variable stays literal

    @Test func unresolvedSpecialVariableStaysLiteralAndIsNotQuarantined() throws {
        // Pins the fallback branch of the `.specialVariable` case: a `${VAR}` token whose
        // name is not a `specialVariables` key is original text, not untrusted input, so
        // it passes through verbatim inside the surrounding `.original` span and never
        // becomes a `.quarantined` one. `SpecialVariable.resolve` returns a non-optional
        // `String`, so a missing table key is the only way into that branch -- no entry
        // can hand `nil` back.
        let body = "before ${NOT_A_REAL_VARIABLE} after"
        let substituted = try pass.render(QuarantinedText(original: body), request: request(text: body))

        #expect(substituted.spans == [.original(body)])
        #expect(substituted.flattened == body)
    }

    // MARK: - Missing positional/named references substitute empty

    @Test func missingPositionalReferenceSubstitutesEmpty() throws {
        let result = try render("[$5]", arguments: ["only"])
        #expect(result.hasPrefix("[]"))
    }

    @Test func missingArgumentsIndexReferenceSubstitutesEmpty() throws {
        let result = try render("[$ARGUMENTS[5]]", arguments: ["only"])
        #expect(result.hasPrefix("[]"))
    }

    @Test func missingNamedReferenceSubstitutesEmpty() throws {
        let result = try render("[$message]", arguments: [], argumentNames: ["message"])
        #expect(result == "[]")
    }

    // MARK: - $name position space is the shell-tokenized positions, not raw `arguments` indices

    @Test func namedResolutionUsesRetokenizedPositionsNotRawArgumentsIndices() throws {
        // Pins `RenderRequest.argumentNames`'s documented (if surprising) contract: position
        // `i` in `argumentNames` matches position `i` of the *shell-tokenized* positional
        // arguments -- the same array `$0`/`$1` index -- not raw index `i` of `arguments`
        // itself. An unprotected multi-word `arguments` element re-splits on retokenization, so
        // it does not line up 1:1 with declared names unless the caller quotes it, exactly like
        // `$N`/`$ARGUMENTS[N]` already require.
        let result = try render(
            "$first|$1", arguments: ["hello world", "second"], argumentNames: ["first", "second"])
        #expect(result.hasPrefix("hello|world"))
    }

    // MARK: - Digit runs too large for Int substitute empty rather than trapping

    @Test func oversizedPositionalDigitsSubstituteEmptyRatherThanTrapping() throws {
        let result = try render("[$99999999999999999999]", arguments: ["only"])
        #expect(result.hasPrefix("[]"))
    }

    @Test func oversizedArgumentsIndexDigitsSubstituteEmptyRatherThanTrapping() throws {
        let result = try render("[$ARGUMENTS[99999999999999999999]]", arguments: ["only"])
        #expect(result.hasPrefix("[]"))
    }

    // MARK: - $ARGUMENTS auto-append matrix

    @Test(
        "auto-append fires only when args are supplied and the body lacks $ARGUMENTS",
        arguments: [
            (argsSupplied: true, bodyHasArguments: true),
            (argsSupplied: true, bodyHasArguments: false),
            (argsSupplied: false, bodyHasArguments: true),
            (argsSupplied: false, bodyHasArguments: false),
        ])
    func autoAppendFiresOnlyWhenArgsSuppliedAndBodyLacksArguments(
        argsSupplied: Bool, bodyHasArguments: Bool
    ) throws {
        let body = bodyHasArguments ? "Body: $ARGUMENTS" : "Body: no reference"
        let arguments = argsSupplied ? ["value"] : []
        let result = try render(body, arguments: arguments)

        let expectedAppend = argsSupplied && !bodyHasArguments
        #expect(result.contains("ARGUMENTS: value") == expectedAppend)
    }

    // MARK: - Single-shot: no re-scan of substituted output

    @Test func substitutedValueContainingDollarOneIsNotReSubstituted() throws {
        let result = try render("$0", arguments: ["literal$1value"])
        #expect(result.hasPrefix("literal$1value"))
    }

    // MARK: - commit fixture: quoted multi-word args end to end

    @Test func commitFixtureRendersDollarZeroAndArgumentsForQuotedMultiWordArgs() throws {
        let url = FixtureLibrary.url(relativePath: "project/.skills/commit/SKILL.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        guard case .decoded(let skill) = FrontmatterDecoder.decode(text: text) else {
            Issue.record("expected the commit fixture to decode")
            return
        }

        let rawArgument = "\"fix the off-by-one bug\""
        let result = try pass.render(
            QuarantinedText(original: skill.body),
            request: RenderRequest(
                text: skill.body,
                arguments: [rawArgument],
                argumentNames: skill.frontmatter.arguments,
                skillDirectory: FixtureLibrary.url(relativePath: "project/.skills/commit"),
                winningLayer: DotfolderStack.Layer(
                    source: .project, root: FixtureLibrary.url(relativePath: "project/.skills")),
                policy: RenderPolicy())
        ).flattened

        #expect(
            result.contains(
                "Commit the currently staged changes using the message: fix the off-by-one bug"))
        #expect(result.contains(rawArgument))
    }
}
