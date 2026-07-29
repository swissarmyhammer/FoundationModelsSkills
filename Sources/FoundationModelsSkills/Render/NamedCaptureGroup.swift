import Foundation

/// Extracts one named regex capture group's matched substring from an `NSRegularExpression`
/// match.
///
/// Shared by every render pass that classifies a match by which alternative of a single
/// combined pattern participated (plan.md §5) -- `ArgumentSubstitution`'s `$`-token grammar and
/// `ShellInjection`'s injection grammar both follow this "one pattern, several named
/// alternatives, discriminate by which group's range is populated" shape, so the group-text
/// extraction step lives here once instead of twice.
enum NamedCaptureGroup {
    /// Extracts `name`'s captured substring from `match`, or `nil` when that alternative did not
    /// participate in the match.
    ///
    /// A named group's range is `NSNotFound` when the alternation branch containing it was not
    /// the one that matched -- this checks that range explicitly rather than assuming the
    /// substring is always safe to extract.
    ///
    /// - Parameters:
    ///   - match: The match to inspect.
    ///   - name: The named capture group to extract, as spelled in the source pattern.
    ///   - text: The text `match` was matched against.
    /// - Returns: The captured substring, or `nil` when `name`'s range is `NSNotFound`.
    static func text(from match: NSTextCheckingResult, name: String, in text: String) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
