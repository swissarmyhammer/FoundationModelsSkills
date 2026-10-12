import Testing

@testable import FoundationModelsSkills

/// Tests for `ResourcePathRules`, the rules of a resource path that need no
/// file: the well-formed check of a path relative to a layer directory, the
/// hidden-component check, and the text a resource operation gives for a
/// path it denies.
///
/// The filesystem half of the confinement rule belongs to
/// `PathConfinement.isConfined(_:to:)` of `FoundationModelsExtras`, and the
/// tests of that half stand in that package.
struct ResourcePathRulesTests {
    // MARK: - The well-formed check, as a table

    /// Each path shape the check accepts: a file of the skill directory, a file
    /// of a folder under it, and a file deep under it.
    @Test(arguments: ["SKILL.md", "references/rules.md", "scripts/build.sh", "assets/icons/logo.png"])
    func aWellFormedPathIsAccepted(path: String) {
        #expect(ResourcePathRules.isWellFormedRelativePath(path))
    }

    /// Each path shape the check refuses: the empty path, a rooted path, a path
    /// of the home directory, and a path that walks up -- at the head of the
    /// path and inside it alike.
    @Test(arguments: ["", "/etc/passwd", "~/secrets.md", "../outside.md", "references/../../outside.md"])
    func aPathThatIsNotWellFormedIsRefused(path: String) {
        #expect(!ResourcePathRules.isWellFormedRelativePath(path))
    }

    // MARK: - The hidden-component check, as a table

    /// Each path that holds a hidden component: a hidden file at the top, a
    /// hidden file in a folder, a hidden folder above a file, and a hidden
    /// folder deep in the path.
    @Test(arguments: [".env", "references/.secret.md", ".git/config", "assets/.cache/icons/logo.png"])
    func aPathWithAHiddenComponentIsHidden(path: String) {
        #expect(ResourcePathRules.hasHiddenComponent(path))
    }

    /// Each path that holds no hidden component, also a path with a full stop
    /// that is not at the start of a component.
    @Test(arguments: ["SKILL.md", "references/rules.md", "scripts/build.sh", "assets/icons/logo.v2.png"])
    func aPathWithNoHiddenComponentIsNotHidden(path: String) {
        #expect(!ResourcePathRules.hasHiddenComponent(path))
    }

    // MARK: - The denied text

    @Test func theDeniedTextNamesThePathAndTheSkillDirectory() {
        #expect(
            ResourcePathRules.deniedMessage(path: "../outside.md")
                == "The path `../outside.md` is not accessible: it must resolve to a location inside the skill directory."
        )
    }
}
