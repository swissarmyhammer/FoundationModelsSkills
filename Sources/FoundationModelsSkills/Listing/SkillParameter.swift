/// One inferred or declared parameter of a skill, merged from up to three
/// frontmatter/body sources by position (plan.md §6.1): `arguments:` (names +
/// order), `argument-hint:` (placeholders + optionality), and body inference
/// (`$0`/`$N`/`$ARGUMENTS[N]` scanning) when neither frontmatter source is
/// present.
///
/// Produced by `ParameterInference.infer(frontmatter:body:)`, carried on
/// `SkillListing.parameters`.
public struct SkillParameter: Sendable, Equatable {
    /// The parameter's name -- from `arguments:` when present, otherwise the
    /// inner text of an `argument-hint:` token (`<message>` -> `"message"`,
    /// `[env]` -> `"env"`), otherwise a synthesized `"arg<position>"` name
    /// for a body-inferred parameter with no frontmatter source at all.
    public var name: String

    /// 0-based position, matching `$0`/`$1`/... and `$ARGUMENTS[N]`.
    public var position: Int

    /// Whether this parameter must be supplied.
    ///
    /// An `argument-hint:` token of `<x>` -> `true`; `[x]` -> `false`; a
    /// bare/unbracketed or malformed hint token (`env`, `[env`) -> `false`
    /// (plan.md §6.1's bare-token rule: only `<x>` marks a hint token
    /// required). A position with no hint token at all (body-inferred, or an
    /// `arguments:`-only position past the hint's arity) defaults to `true`
    /// -- the conservative reading when the source is silent.
    public var required: Bool

    /// Whether this is a trailing variadic parameter -- an `argument-hint:`
    /// token ending in a trailing `...`.
    ///
    /// `false` for every other source.
    public var variadic: Bool

    /// The raw `argument-hint:` token text for display (e.g. `"<message>"`,
    /// `"[env]"`, `"files..."`), or `nil` when no hint token exists at this
    /// position.
    public var placeholder: String?

    /// Creates a `SkillParameter` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - name: The parameter's name.
    ///   - position: 0-based position, matching `$0`/`$1`/... and
    ///     `$ARGUMENTS[N]`.
    ///   - required: Whether this parameter must be supplied.
    ///   - variadic: Whether this is a trailing variadic parameter.
    ///   - placeholder: The raw `argument-hint:` token text for display, or
    ///     `nil` when no hint token exists at this position.
    public init(name: String, position: Int, required: Bool, variadic: Bool, placeholder: String?) {
        self.name = name
        self.position = position
        self.required = required
        self.variadic = variadic
        self.placeholder = placeholder
    }
}
