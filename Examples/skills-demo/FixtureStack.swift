import Foundation
import FoundationModelsExtras

/// Resolves the checked-in `Examples/skill-library` fixture stack, hermetically.
///
/// Resolution walks up from the calling source file's own `#filePath`, so it
/// never depends on -- and can never resolve into -- the real home directory
/// or `$XDG_CONFIG_HOME`, matching plan.md §11's "explicit `defaultsDirectory`/
/// `userDirectory` fixture URLs" requirement. Every file in this target lives
/// directly under `Examples/skills-demo/`, so the two-levels-up derivation is
/// identical regardless of which file calls it.
enum FixtureStack {
    /// Builds the `DotfolderStack` over `defaults`/`user`/`project` inside
    /// `Examples/skill-library`.
    ///
    /// - Parameter thisFile: The calling source file's path; defaults to the
    ///   call site's `#filePath`.
    /// - Returns: The fixture stack, ready for `SkillsRegistry(stack:)`.
    static func make(thisFile: String = #filePath) -> DotfolderStack {
        let libraryRoot = URL(fileURLWithPath: thisFile)
            .deletingLastPathComponent()  // <file>.swift -> skills-demo/
            .deletingLastPathComponent()  // skills-demo/ -> Examples/
            .appendingPathComponent("skill-library", isDirectory: true)
        return DotfolderStack(
            name: "skills",
            workingDirectory: libraryRoot.appendingPathComponent("project", isDirectory: true),
            defaultsDirectory: libraryRoot.appendingPathComponent("defaults", isDirectory: true),
            userDirectory: libraryRoot.appendingPathComponent("user", isDirectory: true))
    }
}
