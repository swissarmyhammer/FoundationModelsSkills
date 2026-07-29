import Foundation

/// Pass 1 of the §5 render pipeline: Claude-compatible argument and special-variable
/// substitution.
///
/// Resolves every `$`-token plan.md §5 defines -- `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N` (0-based
/// positional), `$name` (declared via the skill's `arguments:` frontmatter, threaded through
/// `RenderRequest.argumentNames`), and `${SKILL_DIR}` (plus any future special variable added
/// to `specialVariables`) -- in one left-to-right scan over the *original* input text. The scan
/// never re-examines its own substituted output, satisfying `RenderPass`'s single-shot
/// contract: a supplied argument value that itself contains `$1`-shaped text is inserted
/// verbatim, never re-evaluated. `\$` escapes a literal `$`, consuming only the backslash --
/// the text that follows is copied through untouched, never evaluated as a token.
///
/// A `$name` or `${VAR}` token this pass does not recognize -- not a declared argument name,
/// not a known special variable -- is left untouched, verbatim. This is how a bare
/// `$HOME`-style environment reference survives pass 1 for pass 3's `{{ env.* }}` templating
/// (plan.md §5) to pick up later, and it means an unrecognized token is never mistaken for
/// "missing".
///
/// A recognized-but-unsupplied reference -- a positional index or a declared name past the
/// argument count actually supplied -- substitutes to an empty string. This pass raises no
/// diagnostic for that case: plan.md §5 assigns corrective messaging (from the §6.1 `required`
/// flags) to the ops layer built on top of this pipeline, not to the pass itself.
///
/// `$ARGUMENTS`'s positional siblings (`$ARGUMENTS[N]`/`$N`) are derived by tokenizing all
/// supplied arguments -- joined with a single space to reconstruct "as typed" -- through a
/// small shell-style tokenizer (`Self.shellStyleTokens`) that understands double/single quotes
/// and backslash escapes, so a caller-supplied multi-word argument (e.g. a quoted commit
/// message) splits the way a shell would, not on every whitespace character.
public struct ArgumentSubstitution: RenderPass {
    /// Creates an `ArgumentSubstitution` pass.
    ///
    /// Takes no configuration -- every instance behaves identically, driven entirely by the
    /// `RenderRequest` each `render(_:request:)` call receives.
    public init() {}

    /// Substitutes every recognized `$`-token in `text` per plan.md §5's Claude-compatible
    /// grammar, then appends the `ARGUMENTS: <value>` no-data-loss fallback when warranted.
    ///
    /// - Parameters:
    ///   - text: The input text to substitute -- the render request's original body/metadata
    ///     text, since this pass always runs first in both `RenderPipeline` pass-sets.
    ///   - request: The render request this pass runs under; `arguments`, `argumentNames`, and
    ///     `skillDirectory` supply this pass's substitution values.
    /// - Returns: `text` with every recognized `$`-token substituted, plus the
    ///   `ARGUMENTS: <value>` auto-append when `request.arguments` is non-empty and `text` has
    ///   no bare `$ARGUMENTS` reference (the no-data-loss fallback).
    /// - Throws: Never; this pass performs no I/O and every branch has a defined fallback.
    public func render(_ text: String, request: RenderRequest) throws -> String {
        let rawArgumentsText = request.arguments.joined(separator: " ")
        let positionalArguments = Self.shellStyleTokens(rawArgumentsText)

        var output = ""
        var sawBareArgumentsReference = false
        var lastEnd = text.startIndex

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in Self.tokenPattern.matches(in: text, range: fullRange) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            output += text[lastEnd..<matchRange.lowerBound]
            lastEnd = matchRange.upperBound

            switch Self.classify(match, in: text) {
            case .escape:
                output += "$"
            case .specialVariable(let name):
                output += Self.specialVariables[name]?.resolve(request) ?? String(text[matchRange])
            case .argumentsIndexed(let index), .positional(let index):
                // `index` is `nil` when the digit run didn't fit `Int` (an implausibly large
                // literal, but still valid input text) -- treated the same as an out-of-range
                // index: substitutes empty, never a crash.
                output += index.flatMap { positionalArguments[safe: $0] } ?? ""
            case .argumentsBare:
                sawBareArgumentsReference = true
                output += rawArgumentsText
            case .named(let name):
                if let position = request.argumentNames.firstIndex(of: name) {
                    output += positionalArguments[safe: position] ?? ""
                } else {
                    output += String(text[matchRange])
                }
            }
        }
        output += text[lastEnd...]

        if !request.arguments.isEmpty, !sawBareArgumentsReference {
            output += "\n\nARGUMENTS: \(rawArgumentsText)"
        }

        return output
    }

    // MARK: - Token classification

    /// One recognized `$`-token category, discriminated from a `tokenPattern` match by
    /// `classify(_:in:)`.
    ///
    /// Mirrors the token forms plan.md §5 defines one-for-one; `render(_:request:)` switches
    /// over this type to decide each match's substitution, so every case here corresponds to
    /// exactly one branch there.
    private enum TokenKind {
        /// `\$` -- a literal `$`, no substitution.
        ///
        /// The backslash is consumed; nothing after it is treated as part of the token.
        case escape
        /// `${NAME}` -- a special variable, looked up in `specialVariables`.
        ///
        /// An unrecognized name is left untouched by the caller, not by this case itself --
        /// `render(_:request:)` falls back to the original matched text when the lookup misses.
        case specialVariable(name: String)
        /// `$ARGUMENTS[N]` -- 0-based positional, indexing `positionalArguments`.
        ///
        /// `index` is `nil` when `N`'s digit run is too large to fit `Int` -- still a
        /// well-formed token (the grammar has no digit-count limit), just an implausibly large
        /// literal; treated the same as an out-of-range index (substitutes empty), never a
        /// parse failure.
        case argumentsIndexed(index: Int?)
        /// `$ARGUMENTS` -- all arguments, joined as typed.
        ///
        /// Also marks `sawBareArgumentsReference` in `render(_:request:)`, which gates the
        /// `ARGUMENTS: <value>` auto-append.
        case argumentsBare
        /// `$N` -- 0-based positional, indexing `positionalArguments`.
        ///
        /// `index` is `nil` under the same too-large-for-`Int` condition as
        /// `argumentsIndexed`.
        case positional(index: Int?)
        /// `$name` -- a declared `arguments:` name, resolved through `RenderRequest.argumentNames`.
        ///
        /// An undeclared name is left untouched by the caller, the same fallback
        /// `specialVariable` uses.
        case named(name: String)
    }

    /// The named capture group names `tokenPattern`'s regex string and `classify(_:in:)`'s
    /// `range(withName:)`/`NamedCaptureGroup.text(from:name:in:)` lookups share.
    ///
    /// Defined once here so the group names embedded in the regex pattern and the strings used
    /// to look those groups back up can never drift out of sync.
    private enum GroupName {
        static let escape = "escape"
        static let specialVar = "specialVar"
        static let argumentsIndex = "argumentsIndex"
        static let argumentsBare = "argumentsBare"
        static let position = "position"
        static let namedArg = "namedArg"
    }

    /// Classifies one `tokenPattern` match into a `TokenKind` by checking each alternative's
    /// named capture group *range* -- not whether its text happens to parse -- in the
    /// grammar's own precedence order (escape, `${VAR}`, `$ARGUMENTS[N]`, bare `$ARGUMENTS`,
    /// `$N`, `$name`).
    ///
    /// Exactly one alternative's range is ever populated for a given match,
    /// since `tokenPattern`'s alternatives are mutually exclusive by construction; checking the
    /// range first (rather than gating on `Int(digits) != nil`) means an implausibly large
    /// digit run for `$ARGUMENTS[N]`/`$N` still classifies correctly, carrying `index: nil`,
    /// instead of falling through to an alternative that never actually matched.
    ///
    /// - Parameters:
    ///   - match: One match produced by `tokenPattern` against `text`.
    ///   - text: The text `match` was matched against, needed to extract named-group substrings.
    /// - Returns: The token kind `match` represents.
    private static func classify(_ match: NSTextCheckingResult, in text: String) -> TokenKind {
        // Extracted so `$ARGUMENTS[N]` and `$N` -- the only two alternatives carrying a
        // numeric index -- share one digit-parsing step instead of repeating it; review
        // found the two inline copies near-verbatim duplicated.
        /// Extracts `groupName`'s digit-run capture, parses it, and builds the resulting
        /// `TokenKind` via `makeKind`.
        ///
        /// `Int` failing to parse (an implausibly large digit run) is not an error here --
        /// see `TokenKind.argumentsIndexed`'s doc comment -- so `makeKind` always receives
        /// a value, `nil` included, and the caller never needs its own fallback.
        func digitGroupTokenKind(groupName: String, makeKind: (Int?) -> TokenKind) -> TokenKind {
            let digits = NamedCaptureGroup.text(from: match, name: groupName, in: text) ?? ""
            return makeKind(Int(digits))
        }

        // Extracted so `${VAR}` and `$name` -- the only two alternatives that capture a
        // name directly, rather than a digit run -- share one name-extraction step instead
        // of repeating it; review found the two inline `if let name = groupText(...)` copies
        // near-verbatim duplicated, differing only in group name and `TokenKind` constructor.
        /// Extracts `groupName`'s captured name substring and builds the resulting
        /// `TokenKind` via `makeKind`.
        ///
        /// Mirrors `digitGroupTokenKind` for the name-capturing alternatives. Callers check
        /// `groupName`'s range before calling, so the `?? ""` fallback is defensive and never
        /// reached in practice.
        func nameGroupTokenKind(groupName: String, makeKind: (String) -> TokenKind) -> TokenKind {
            let name = NamedCaptureGroup.text(from: match, name: groupName, in: text) ?? ""
            return makeKind(name)
        }

        if match.range(withName: GroupName.escape).location != NSNotFound {
            return .escape
        }
        if match.range(withName: GroupName.specialVar).location != NSNotFound {
            return nameGroupTokenKind(groupName: GroupName.specialVar) { .specialVariable(name: $0) }
        }
        if match.range(withName: GroupName.argumentsIndex).location != NSNotFound {
            return digitGroupTokenKind(groupName: GroupName.argumentsIndex) { .argumentsIndexed(index: $0) }
        }
        if match.range(withName: GroupName.argumentsBare).location != NSNotFound {
            return .argumentsBare
        }
        if match.range(withName: GroupName.position).location != NSNotFound {
            return digitGroupTokenKind(groupName: GroupName.position) { .positional(index: $0) }
        }
        if match.range(withName: GroupName.namedArg).location != NSNotFound {
            return nameGroupTokenKind(groupName: GroupName.namedArg) { .named(name: $0) }
        }
        preconditionFailure("ArgumentSubstitution.tokenPattern matched but no known alternative captured.")
    }

    /// The single-pass `$`-token grammar (plan.md §5).
    ///
    /// Six alternatives -- escape, `${VAR}`, `$ARGUMENTS[N]`, bare `$ARGUMENTS`, `$N`, then
    /// `$name` -- tried in this order via alternation, so `$ARGUMENTS`'s reserved spelling is
    /// never captured by the generic `$name` alternative, and `$ARGUMENTS[N]` is never captured
    /// by the bare `$ARGUMENTS` alternative.
    private static let tokenPattern = try! NSRegularExpression(
        pattern:
            #"(?<\#(GroupName.escape)>\\\$)|\$\{(?<\#(GroupName.specialVar)>[A-Za-z_][A-Za-z0-9_]*)\}|\$ARGUMENTS\[(?<\#(GroupName.argumentsIndex)>\d+)\]|(?<\#(GroupName.argumentsBare)>\$ARGUMENTS)\b|\$(?<\#(GroupName.position)>\d+)\b|\$(?<\#(GroupName.namedArg)>[A-Za-z_][A-Za-z0-9_]*)\b"#
    )

    // MARK: - Special variables

    /// One `${NAME}` special variable pass 1 resolves.
    ///
    /// A single table drives every `${...}` lookup -- plan.md §5's "leave room for more special
    /// vars behind one table" -- so adding a future variable (e.g. an analog of Claude's
    /// `${CLAUDE_PROJECT_DIR}`) is one new table entry, never a new branch in `render(_:request:)`.
    private struct SpecialVariable {
        /// This variable's bare name, as it appears inside `${...}` (no braces, case-sensitive).
        ///
        /// Used as `specialVariables`'s dictionary key.
        let name: String
        /// Resolves this variable's value for one render request.
        ///
        /// Takes the whole `RenderRequest`, not just `skillDirectory`, so a future entry can
        /// read any other field it needs without changing this type's shape.
        let resolve: @Sendable (RenderRequest) -> String
    }

    /// This pass's special-variable table, keyed by `SpecialVariable.name` for lookup.
    ///
    /// Currently just `${SKILL_DIR}` (plan.md §5's analog of Claude's `${CLAUDE_SKILL_DIR}`); a
    /// `${...}` token whose name is not a key here is left untouched, verbatim.
    private static let specialVariables: [String: SpecialVariable] = Dictionary(
        uniqueKeysWithValues: [
            SpecialVariable(name: "SKILL_DIR") { request in request.skillDirectory.path }
        ].map { ($0.name, $0) })

    // MARK: - Shell-style argument tokenizer

    /// Splits `text` into positional argument tokens using shell-style quoting: double quotes
    /// group whitespace-containing tokens (backslash escapes `"`, `\`, `` ` ``, and `$` inside
    /// them), single quotes group tokens with no escape processing at all, and a backslash
    /// outside any quote escapes the single character that follows it (including whitespace, so
    /// it does not split the token).
    ///
    /// Quote characters are delimiters, never included in the resulting token; an empty quoted
    /// string (`""`/`''`) produces one empty-string token rather than being dropped, matching
    /// shell behavior. An unterminated quote at the end of `text` is read leniently -- whatever
    /// was accumulated so far becomes the final token. Package-visible (not `private`) so
    /// `StencilPass` can derive the same positional values for pass 3's explicit Stencil context
    /// (plan.md §5.3's "skill arguments land [in the explicit context] too") -- `$name`/`$N` and
    /// `{{ name }}` must index identical positions, so both passes share this one tokenizer
    /// rather than each maintaining its own.
    ///
    /// - Parameter text: The raw, as-typed argument text (already joined across every supplied
    ///   argument -- see `render(_:request:)`).
    /// - Returns: The tokenized positional arguments, in order; empty when `text` is empty.
    static func shellStyleTokens(_ text: String) -> [String] {
        /// Which quote (if any) the scan is currently inside -- determines how a backslash and
        /// a closing-quote character behave.
        enum QuoteState {
            case none
            case single
            case double
        }

        /// Characters a backslash escapes when scanning inside a double-quoted span --
        /// anything else, the backslash is copied through literally alongside its next
        /// character (POSIX `dquote` escaping is narrower than the unquoted case).
        let doubleQuoteEscapable: Set<Character> = ["\"", "\\", "$", "`"]

        var tokens: [String] = []
        var current = ""
        var hasCurrentToken = false
        var quote: QuoteState = .none

        // Extracted so the whitespace-boundary branch below (and the final flush after the
        // loop) sit at one nesting level under their `switch`/`while`, not two -- review found
        // the previous inline `if hasCurrentToken { ... }` pushed that branch to 4 levels deep.
        /// Appends the currently accumulated token to `tokens`, if any, and resets the
        /// accumulator.
        ///
        /// Shared by the whitespace-boundary branch inside the scan loop and by the final
        /// flush after the loop ends, so both call sites agree on what counts as "a token is
        /// pending".
        func flushPendingToken() {
            guard hasCurrentToken else { return }
            tokens.append(current)
            current = ""
            hasCurrentToken = false
        }

        let characters = Array(text)
        var index = 0

        // Extracted so the unquoted-backslash branch inside the scan loop's
        // `switch`/`while` sits at one nesting level under `case .none`, not two --
        // review found the inline `if index + 1 < characters.count { ... }` pushed that
        // branch to 4 levels deep (while > switch case > if > if).
        /// Consumes an unquoted backslash escape: marks a token as pending, and -- when a
        /// character follows the backslash -- appends that character and advances past
        /// it.
        ///
        /// A trailing backslash with nothing after it still marks a token pending,
        /// matching this tokenizer's lenient handling of an unterminated escape.
        func consumeUnquotedBackslash() {
            hasCurrentToken = true
            guard index + 1 < characters.count else { return }
            index += 1
            current.append(characters[index])
        }

        while index < characters.count {
            let character = characters[index]
            switch quote {
            case .none:
                if character.isWhitespace {
                    flushPendingToken()
                } else if character == "\"" {
                    quote = .double
                    hasCurrentToken = true
                } else if character == "'" {
                    quote = .single
                    hasCurrentToken = true
                } else if character == "\\" {
                    consumeUnquotedBackslash()
                } else {
                    hasCurrentToken = true
                    current.append(character)
                }
            case .double:
                if character == "\"" {
                    quote = .none
                } else if character == "\\", index + 1 < characters.count,
                    doubleQuoteEscapable.contains(characters[index + 1])
                {
                    index += 1
                    current.append(characters[index])
                } else {
                    current.append(character)
                }
            case .single:
                if character == "'" {
                    quote = .none
                } else {
                    current.append(character)
                }
            }
            index += 1
        }
        flushPendingToken()
        return tokens
    }
}

extension Array {
    /// Safe subscript that returns `nil` for out-of-range indices, where absence represents
    /// no value supplied, not an error.
    ///
    /// Package-visible (not `private`/`fileprivate`) so `StencilPass` can look up a positional
    /// argument value the same bounds-checked way this file's own `.named` substitution does,
    /// keeping `$name` (pass 1) and `{{ name }}` (pass 3) in agreement for a declared name past
    /// the supplied argument count.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
