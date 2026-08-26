import Foundation
import FoundationModelsSkills
import Testing

/// Table-driven tests for `ParameterInference` (plan.md §6.1): the merge
/// matrix over `arguments:`, `argument-hint:`, and body inference (each
/// source alone, and `arguments:` + `argument-hint:` together, including an
/// arity mismatch), the `argument-hint:` grammar (`<a> [b] c...`), the
/// gap-filling body-inference case, and the `acceptsTrailingArguments`
/// bare-`$ARGUMENTS`-only rule.
struct ParameterInferenceTests {
    // MARK: - Single source: arguments: only

    @Test func argumentsOnlyProducesRequiredParametersWithNoPlaceholder() {
        let frontmatter = SkillFrontmatter(argumentsRaw: .string("message env"))
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "no dollar refs here")

        #expect(
            result.parameters == [
                SkillParameter(name: "message", position: 0, required: true, variadic: false, placeholder: nil),
                SkillParameter(name: "env", position: 1, required: true, variadic: false, placeholder: nil),
            ])
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Single source: argument-hint: only -- the `<a> [b] c...` grammar

    @Test func hintOnlyParsesRequiredOptionalAndBareVariadicGrammar() {
        // `c...` is a bare (unbracketed) token: only `<x>` marks a hint
        // token required (plan.md §6.1), so the bare variadic reads optional.
        let frontmatter = SkillFrontmatter(argumentHint: "<a> [b] c...")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "no dollar refs here")

        #expect(
            result.parameters == [
                SkillParameter(name: "a", position: 0, required: true, variadic: false, placeholder: "<a>"),
                SkillParameter(name: "b", position: 1, required: false, variadic: false, placeholder: "[b]"),
                SkillParameter(name: "c", position: 2, required: false, variadic: true, placeholder: "c..."),
            ])
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Single source: argument-hint: only -- bare tokens are optional (plan.md §6.1)

    @Test func hintBareTokenWithoutBracketsIsOptional() {
        // plan.md §6.1's bare-token rule: `argument-hint:` is display text,
        // and only the explicit `<x>` form marks a token required. A bare
        // word such as `env` must never block dispatch with a
        // missing-argument corrective, so it reads `required: false`.
        let frontmatter = SkillFrontmatter(argumentHint: "env")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(
            result.parameters == [
                SkillParameter(name: "env", position: 0, required: false, variadic: false, placeholder: "env")
            ])
        #expect(result.diagnostics.isEmpty)
    }

    @Test func hintMalformedUnclosedBracketTokenIsOptional() {
        // Deliberate: a malformed placeholder such as `[env` (an unclosed
        // bracket) is not a well-formed `<x>` or `[x]` token, so it falls
        // through to the bare-token rule and reads optional -- the same
        // reading a bare word gets. The raw text is kept verbatim as the
        // placeholder and as the name; no bracket is stripped.
        let frontmatter = SkillFrontmatter(argumentHint: "[env <target")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(
            result.parameters == [
                SkillParameter(name: "[env", position: 0, required: false, variadic: false, placeholder: "[env"),
                SkillParameter(
                    name: "<target", position: 1, required: false, variadic: false, placeholder: "<target"),
            ])
    }

    @Test func hintBareTokenMergedWithArgumentsNameIsOptional() {
        // The bare-token rule also holds through the `arguments:` merge:
        // the hint token supplies optionality by position, so `arguments:
        // env` + `argument-hint: env` reads optional, unlike `arguments:`
        // alone (whose silent positions default to required).
        let frontmatter = SkillFrontmatter(argumentsRaw: .string("env"), argumentHint: "env")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(
            result.parameters == [
                SkillParameter(name: "env", position: 0, required: false, variadic: false, placeholder: "env")
            ])
        #expect(result.diagnostics.isEmpty)
    }

    @Test func hintVariadicSuffixAppliesToBracketedTokensToo() {
        let frontmatter = SkillFrontmatter(argumentHint: "<files>... [more]...")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(
            result.parameters == [
                SkillParameter(
                    name: "files", position: 0, required: true, variadic: true, placeholder: "<files>..."),
                SkillParameter(
                    name: "more", position: 1, required: false, variadic: true, placeholder: "[more]..."),
            ])
    }

    // MARK: - Single source: body inference only -- gap filling

    @Test func bodyOnlySkillWithDollarZeroAndDollarTwoSynthesizesGapFilledPositions() {
        let frontmatter = SkillFrontmatter()
        let body = "First: $0\nThird: $2\n"
        let result = ParameterInference.infer(frontmatter: frontmatter, body: body)

        #expect(
            result.parameters == [
                SkillParameter(name: "arg0", position: 0, required: true, variadic: false, placeholder: nil),
                SkillParameter(name: "arg1", position: 1, required: true, variadic: false, placeholder: nil),
                SkillParameter(name: "arg2", position: 2, required: true, variadic: false, placeholder: nil),
            ])
        #expect(result.diagnostics.isEmpty)
    }

    @Test func bodyOnlySkillWithArgumentsBracketNotationSynthesizesPositions() {
        let frontmatter = SkillFrontmatter()
        let body = "Use \\$ARGUMENTS[0] and \\$ARGUMENTS[1]".replacingOccurrences(of: "\\$", with: "$")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: body)

        #expect(
            result.parameters == [
                SkillParameter(name: "arg0", position: 0, required: true, variadic: false, placeholder: nil),
                SkillParameter(name: "arg1", position: 1, required: true, variadic: false, placeholder: nil),
            ])
    }

    @Test func noSourceAtAllProducesEmptyParameters() {
        let frontmatter = SkillFrontmatter()
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "Nothing positional here.")
        #expect(result.parameters.isEmpty)
    }

    // MARK: - arguments: + argument-hint: merge, matching arity

    @Test func argumentsAndHintMergeByPositionWhenArityMatches() {
        let frontmatter = SkillFrontmatter(
            argumentsRaw: .string("message"), argumentHint: "<message>")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "$0")

        #expect(
            result.parameters == [
                SkillParameter(
                    name: "message", position: 0, required: true, variadic: false, placeholder: "<message>")
            ])
        #expect(result.diagnostics.isEmpty)
    }

    @Test func argumentsNameWinsOverHintInnerNameOnMerge() {
        // arguments: is authoritative for names (plan.md §6.1) -- even though
        // the hint token's own inner text ("msg") differs from the
        // arguments: name ("message"), the merged parameter keeps the
        // arguments: name and only borrows the hint's placeholder/optionality.
        let frontmatter = SkillFrontmatter(
            argumentsRaw: .string("message"), argumentHint: "<msg>")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(result.parameters == [
            SkillParameter(
                name: "message", position: 0, required: true, variadic: false, placeholder: "<msg>")
        ])
    }

    // MARK: - arguments: + argument-hint: merge, mismatched arity -- diagnostic, not a failure

    @Test func mismatchedArityBetweenArgumentsAndHintProducesDiagnosticNotFailure() {
        let frontmatter = SkillFrontmatter(
            argumentsRaw: .string("message env"), argumentHint: "<message>")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        // Still a full, usable merge -- arguments: wins for names/order;
        // the position with no matching hint token defaults conservatively.
        #expect(
            result.parameters == [
                SkillParameter(
                    name: "message", position: 0, required: true, variadic: false, placeholder: "<message>"),
                SkillParameter(name: "env", position: 1, required: true, variadic: false, placeholder: nil),
            ])
        #expect(!result.diagnostics.isEmpty)
    }

    @Test func hintLongerThanArgumentsProducesDiagnosticAndIgnoresExtraTokens() {
        // The sibling of the above: argument-hint: has MORE tokens than
        // arguments: this time, not fewer. arguments: is still authoritative
        // for names/order (plan.md §6.1), so the merge stays truncated to
        // arguments:'s single name -- the extra hint token is unused, not an
        // error.
        let frontmatter = SkillFrontmatter(
            argumentsRaw: .string("message"), argumentHint: "<message> [env] more...")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(
            result.parameters == [
                SkillParameter(
                    name: "message", position: 0, required: true, variadic: false, placeholder: "<message>")
            ])
        #expect(!result.diagnostics.isEmpty)
    }

    // MARK: - acceptsTrailingArguments -- bare $ARGUMENTS only

    @Test func acceptsTrailingArgumentsIsTrueWhenBodyReferencesBareArguments() {
        let frontmatter = SkillFrontmatter(argumentsRaw: .string("message"), argumentHint: "<message>")
        let result = ParameterInference.infer(
            frontmatter: frontmatter, body: "Use $0.\n\nFallback: $ARGUMENTS")
        #expect(result.acceptsTrailingArguments == true)
    }

    @Test func acceptsTrailingArgumentsIsFalseWhenBodyLacksArguments() {
        let frontmatter = SkillFrontmatter(argumentsRaw: .string("message"), argumentHint: "<message>")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "Use $0 only, no fallback.")
        #expect(result.acceptsTrailingArguments == false)
    }

    @Test func acceptsTrailingArgumentsIsFalseForArgumentsBracketNotationAlone() {
        // $ARGUMENTS[N] is the positional spelling, not the free-form-tail
        // marker -- it must NOT set acceptsTrailingArguments on its own.
        let frontmatter = SkillFrontmatter()
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "First is $ARGUMENTS[0].")
        #expect(result.acceptsTrailingArguments == false)
    }

    @Test func acceptsTrailingArgumentsIsFalseWithNoBodyAtAll() {
        let frontmatter = SkillFrontmatter()
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")
        #expect(result.acceptsTrailingArguments == false)
    }

    @Test func acceptsTrailingArgumentsIsFalseForArgumentsEmbeddedInLongerWord() {
        // The word-boundary sibling of the $ARGUMENTS[N] case above: a body
        // token where "$ARGUMENTS" is only a prefix of a longer identifier
        // must not be misread as the bare-reference marker either.
        let frontmatter = SkillFrontmatter()
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "Set $ARGUMENTSX here.")
        #expect(result.acceptsTrailingArguments == false)
    }

    // MARK: - Body inference: multi-digit positions

    @Test func bodyInferenceHandlesMultiDigitPositions() {
        // $10 must parse as position 10 (not "position 1 followed by a
        // literal 0"), and gap-filling must synthesize every position from
        // 0 through 10, not just 0 and 10.
        let frontmatter = SkillFrontmatter()
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "Use $10 here.")

        #expect(result.parameters.count == 11)
        #expect(result.parameters.map(\.position) == Array(0...10))
        #expect(result.parameters.map(\.name) == (0...10).map { "arg\($0)" })
        #expect(result.parameters.allSatisfy { $0.required && !$0.variadic && $0.placeholder == nil })
    }

    // MARK: - argument-hint: grammar edge cases -- degenerate tokens

    @Test func hintParsesDegenerateEmptyBracketAndTooShortTokensWithoutCrashing() {
        // <> and [] are well-formed brackets around an empty name; a bare
        // "<" is too short (< 2 chars) to be recognized as either bracket
        // form, so it falls through to the bare-token rule (optional).
        let frontmatter = SkillFrontmatter(argumentHint: "<> [] <")
        let result = ParameterInference.infer(frontmatter: frontmatter, body: "")

        #expect(
            result.parameters == [
                SkillParameter(name: "", position: 0, required: true, variadic: false, placeholder: "<>"),
                SkillParameter(name: "", position: 1, required: false, variadic: false, placeholder: "[]"),
                SkillParameter(name: "<", position: 2, required: false, variadic: false, placeholder: "<"),
            ])
    }
}
