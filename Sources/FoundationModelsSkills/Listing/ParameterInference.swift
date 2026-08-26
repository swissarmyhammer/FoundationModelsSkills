import Foundation

/// Merges a skill's three parameter sources -- `arguments:`, `argument-hint:`,
/// and body inference -- into the structured `[SkillParameter]` list
/// `SkillListing` carries, plus the `acceptsTrailingArguments` flag (plan.md
/// §6.1).
///
/// Precedence: `arguments:` (authoritative names/order) > `argument-hint:`
/// (placeholders + optionality, merged by position when `arguments:` is also
/// present) > body inference (`$0`/`$N`/`$ARGUMENTS[N]` scanning), used only
/// when both frontmatter sources are absent, so the listing is never empty
/// for a skill that clearly takes arguments in its body.
public enum ParameterInference {
    /// The outcome of merging one skill's sources: the merged parameters,
    /// the `$ARGUMENTS`-reference flag, and any source-mismatch diagnostics.
    ///
    /// A mismatch (e.g. `argument-hint:`'s token count disagreeing with
    /// `arguments:`'s name count) is recorded in `diagnostics` but **never**
    /// fails the merge -- plan.md §6.1's "diagnostics flag mismatches
    /// between sources" is advisory, matching this package's lenient
    /// validation posture (plan.md §4) elsewhere.
    public struct Result: Sendable, Equatable {
        /// The merged, position-ordered parameters.
        public var parameters: [SkillParameter]
        /// Whether the body references bare `$ARGUMENTS` (not
        /// `$ARGUMENTS[N]`).
        public var acceptsTrailingArguments: Bool
        /// Source-mismatch diagnostics, empty when every source agreed.
        public var diagnostics: [String]

        /// Creates a `Result` by directly assigning every field.
        public init(parameters: [SkillParameter], acceptsTrailingArguments: Bool, diagnostics: [String]) {
            self.parameters = parameters
            self.acceptsTrailingArguments = acceptsTrailingArguments
            self.diagnostics = diagnostics
        }
    }

    /// One parsed `argument-hint:` token -- an intermediate shape used only
    /// while merging; `SkillParameter` is the public result.
    private struct HintToken {
        /// The raw token text, verbatim, for `SkillParameter.placeholder`.
        let placeholder: String
        /// The token's inner name (brackets and trailing `...` stripped),
        /// used only when no `arguments:` name exists at this position.
        let name: String
        let required: Bool
        let variadic: Bool
    }

    /// Merges `frontmatter`'s `arguments:`/`argument-hint:` and `body`'s
    /// `$0`/`$N`/`$ARGUMENTS[N]` references into a `Result`, following the
    /// plan.md §6.1 precedence: `arguments:` > `argument-hint:` > body
    /// inference.
    ///
    /// - Parameters:
    ///   - frontmatter: The skill's decoded frontmatter.
    ///   - body: The skill's render-pipeline body text (`DecodedSkill.body`).
    /// - Returns: The merged parameters, the `acceptsTrailingArguments` flag,
    ///   and any source-mismatch diagnostics.
    public static func infer(frontmatter: SkillFrontmatter, body: String) -> Result {
        let argumentNames = frontmatter.arguments
        let hintTokens = parseHint(frontmatter.argumentHint)

        var diagnostics: [String] = []
        let parameters: [SkillParameter]
        if !argumentNames.isEmpty {
            parameters = mergeArgumentsWithHint(
                names: argumentNames, hintTokens: hintTokens, diagnostics: &diagnostics)
        } else if !hintTokens.isEmpty {
            parameters = hintTokens.enumerated().map { position, token in
                SkillParameter(
                    name: token.name, position: position, required: token.required,
                    variadic: token.variadic, placeholder: token.placeholder)
            }
        } else {
            parameters = inferFromBody(body)
        }

        return Result(
            parameters: parameters,
            acceptsTrailingArguments: referencesArguments(body),
            diagnostics: diagnostics)
    }

    // MARK: - arguments: + argument-hint: merge

    /// Merges authoritative `arguments:` names/order with `argument-hint:`
    /// placeholders/optionality by position.
    ///
    /// A hint token at the same position supplies
    /// `required`/`variadic`/`placeholder`; a position with no matching hint
    /// token defaults to `required: true, variadic: false, placeholder: nil`
    /// -- the same conservative default used everywhere else a source is
    /// silent. An arity mismatch between the two sources draws a diagnostic
    /// but never fails the merge.
    ///
    /// - Parameters:
    ///   - names: `arguments:`'s tokenized names, in order.
    ///   - hintTokens: `argument-hint:`'s parsed tokens, in order.
    ///   - diagnostics: Accumulates an arity-mismatch note, if any.
    /// - Returns: One `SkillParameter` per `arguments:` name.
    private static func mergeArgumentsWithHint(
        names: [String], hintTokens: [HintToken], diagnostics: inout [String]
    ) -> [SkillParameter] {
        if !hintTokens.isEmpty, hintTokens.count != names.count {
            diagnostics.append(
                "argument-hint: has \(hintTokens.count) token(s) but arguments: has \(names.count) "
                    + "name(s); using arguments: for names/order, argument-hint: for placeholders "
                    + "by position where available.")
        }
        return names.enumerated().map { position, name in
            let hint = position < hintTokens.count ? hintTokens[position] : nil
            return SkillParameter(
                name: name, position: position, required: hint?.required ?? true,
                variadic: hint?.variadic ?? false, placeholder: hint?.placeholder)
        }
    }

    // MARK: - argument-hint: grammar

    /// Parses `argument-hint:`'s space-separated token grammar (plan.md
    /// §6.1): `<x>` required, `[x]` optional, a trailing `...` (on either
    /// bracket form, or on a bare unbracketed token) variadic.
    ///
    /// **Bare-token rule (plan.md §6.1):** a token with neither bracket form
    /// -- a bare word such as `env`, or a malformed placeholder such as
    /// `[env` (unclosed bracket) -- reads `required: false`. `argument-hint:`
    /// is display text, and only the explicit `<x>` form marks a token
    /// required; a display-only word must never block dispatch with a
    /// missing-argument corrective. This is deliberately the opposite of
    /// the `required: true` default `mergeArgumentsWithHint` and
    /// `inferFromBody` use for a position **no** hint token describes: there
    /// the source is silent, here the author wrote a token and declined to
    /// mark it `<required>`. A malformed token's raw text is kept verbatim
    /// as both `placeholder` and `name`; no bracket is stripped.
    ///
    /// - Parameter hint: The raw `argument-hint:` string, or `nil`.
    /// - Returns: One `HintToken` per whitespace-separated token, in order;
    ///   empty when `hint` is `nil` or blank.
    private static func parseHint(_ hint: String?) -> [HintToken] {
        guard let hint else { return [] }
        return hint.split(whereSeparator: \.isWhitespace).map { substring in
            parseHintToken(String(substring))
        }
    }

    /// One bracket form `argument-hint:` tokens may use, and the optionality
    /// it signals -- data for `parseHintToken`'s single lookup, rather than
    /// one hand-written branch per bracket type.
    private struct BracketPattern {
        let open: Character
        let close: Character
        let required: Bool
    }

    /// `<x>` required, `[x]` optional -- plan.md §6.1's `argument-hint:`
    /// grammar.
    private static let bracketPatterns = [
        BracketPattern(open: "<", close: ">", required: true),
        BracketPattern(open: "[", close: "]", required: false),
    ]

    /// Parses one `argument-hint:` token (e.g. `"<message>"`, `"[env]"`,
    /// `"files..."`) into a `HintToken`, applying `parseHint`'s bare-token
    /// rule to any token that is not a well-formed bracket pair.
    private static func parseHintToken(_ token: String) -> HintToken {
        var stripped = Substring(token)
        let variadic = stripped.hasSuffix("...")
        if variadic { stripped = stripped.dropLast(3) }

        let required: Bool
        let name: String
        if stripped.count >= 2,
            let bracket = bracketPatterns.first(
                where: { stripped.first == $0.open && stripped.last == $0.close })
        {
            required = bracket.required
            name = String(stripped.dropFirst().dropLast())
        } else {
            required = false
            name = String(stripped)
        }
        return HintToken(placeholder: token, name: name, required: required, variadic: variadic)
    }

    // MARK: - Body inference

    /// Synthesizes positional parameters from `$0`/`$N`/`$ARGUMENTS[N]`
    /// references in `body`, filling any gap positions so the result is
    /// contiguous from `0` through the highest referenced position (e.g. a
    /// body referencing only `$0` and `$2` synthesizes positions `0`, `1`,
    /// `2`) -- positional substitution depends on every intermediate index
    /// existing, even one the body never named explicitly.
    ///
    /// Synthesized parameters have no name/placeholder source, so they get a
    /// deterministic `"arg<position>"` name, `required: true`, and
    /// `variadic: false`.
    ///
    /// - Parameter body: The skill's render-pipeline body text.
    /// - Returns: `[]` when `body` references no position at all.
    private static func inferFromBody(_ body: String) -> [SkillParameter] {
        let positions = referencedPositions(in: body)
        guard let highest = positions.max() else { return [] }
        return (0...highest).map { position in
            SkillParameter(
                name: "arg\(position)", position: position, required: true, variadic: false,
                placeholder: nil)
        }
    }

    /// The `$N`/`$ARGUMENTS[N]` positional regex -- capture group 1 is `$N`'s
    /// digits, group 2 is `$ARGUMENTS[N]`'s digits.
    ///
    /// **Known limitation:** this matches any literal `$<digits>` token, so a
    /// body that mentions a dollar amount in prose (e.g. "costs $5") is
    /// misread as a positional reference and synthesizes spurious
    /// parameters. This follows plan.md §6.1's grammar literally (`$N`
    /// scanning has no further disambiguation rule); accepted for now since
    /// disambiguating "looks like a price" from "looks like an argument" has
    /// no reliable heuristic without author intent.
    private static let positionalReferencePattern = try! NSRegularExpression(
        pattern: #"\$(\d+)\b|\$ARGUMENTS\[(\d+)\]"#)

    /// The `$ARGUMENTS` bare-reference regex (plan.md §5) -- the negative
    /// lookahead on `[` excludes `$ARGUMENTS[N]`.
    private static let argumentsReferencePattern = try! NSRegularExpression(
        pattern: #"\$ARGUMENTS\b(?!\[)"#)

    /// Every 0-based position `body` references via `$N` or
    /// `$ARGUMENTS[N]`.
    private static func referencedPositions(in body: String) -> Set<Int> {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var positions: Set<Int> = []
        positionalReferencePattern.enumerateMatches(in: body, range: range) { match, _, _ in
            guard let match else { return }
            for groupIndex in 1...2 {
                let groupRange = match.range(at: groupIndex)
                guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: body)
                else { continue }
                if let value = Int(body[swiftRange]) { positions.insert(value) }
            }
        }
        return positions
    }

    /// Whether `body` references bare `$ARGUMENTS` (not `$ARGUMENTS[N]`).
    private static func referencesArguments(_ body: String) -> Bool {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return argumentsReferencePattern.firstMatch(in: body, range: range) != nil
    }
}
