import Foundation

/// One diagnostic-worthy finding `SkillValidator` raised while applying
/// lenient domain validation to a discovered skill (plan.md §4, decision
/// #27) -- never fatal to the surrounding load in isolation; the practical
/// consequence (load anyway, exclude from a surface, hide entirely, or skip)
/// is a property of which rule raised it, not of this type.
public struct SkillDiagnostic: Sendable, Equatable {
    /// How serious a diagnostic is, from least to most consequential.
    ///
    /// `advisory` findings never change how a skill loads (a shadowed id, an
    /// oversized body, unknown top-level keys). `warning` findings accompany
    /// a rule violation whose skill still loads, possibly with changed
    /// visibility (`name` irregularities, an over-limit `description` or
    /// `compatibility`, a missing `description`, the retired `partial: true`
    /// flag). `skip` means the skill did not load at all (unparseable YAML).
    public enum Severity: String, Sendable, Equatable, CaseIterable {
        case advisory
        case warning
        case skip
    }

    /// Where a diagnostic's skill was loaded from -- the discovery layer
    /// that won full-replace precedence (plan.md §4, decision #3), carried
    /// so a diagnostic surface can report provenance even for a skill that
    /// failed to decode at all.
    public struct Provenance: Sendable, Equatable {
        /// The winning root's position in the roots list `SkillDiscovery`
        /// was given, lowest precedence first.
        public var rootIndex: Int
        /// The winning root itself.
        public var root: URL

        /// Creates a `Provenance` by directly assigning both fields.
        ///
        /// - Parameters:
        ///   - rootIndex: The winning root's position in the roots list,
        ///     lowest precedence first.
        ///   - root: The winning root itself.
        public init(rootIndex: Int, root: URL) {
            self.rootIndex = rootIndex
            self.root = root
        }

        /// Creates a `Provenance` from the layer that won a `DiscoveredSkill`
        /// -- its own `rootIndex`/`root`, never one of its shadowed
        /// candidates'.
        ///
        /// - Parameter discovered: The discovered skill to take provenance
        ///   from.
        public init(discovered: DiscoveredSkill) {
            self.init(rootIndex: discovered.rootIndex, root: discovered.root)
        }
    }

    /// How serious this diagnostic is.
    public var severity: Severity
    /// The canonical id (directory name) of the skill this diagnostic is
    /// about.
    public var skillID: String
    /// Where the skill was loaded from -- the winning layer's provenance.
    public var provenance: Provenance
    /// Human-readable diagnostic text.
    public var message: String

    /// Creates a `SkillDiagnostic` by directly assigning every field.
    ///
    /// - Parameters:
    ///   - severity: How serious this diagnostic is.
    ///   - skillID: The canonical id (directory name) of the skill this
    ///     diagnostic is about.
    ///   - provenance: Where the skill was loaded from.
    ///   - message: Human-readable diagnostic text.
    public init(severity: Severity, skillID: String, provenance: Provenance, message: String) {
        self.severity = severity
        self.skillID = skillID
        self.provenance = provenance
        self.message = message
    }
}
