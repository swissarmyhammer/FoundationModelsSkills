import Testing

@testable import FoundationModelsSkills

/// Tests for `SkillFilesText.appending(_:to:)`: the join of the rendered body
/// and the list of the files of the skill; and for the `run script` line of
/// `SkillFilesText.text(id:rows:mode:)` in each tool mode.
///
/// `UseSkillPlainTextTests` reads the full answer of `use skill` for fixture
/// skills, and the body of each fixture ends with a line break. These tests
/// read the join for a body with no line break at its end, and for no list.
struct SkillFilesTextTests {
    /// A body with no line break at its end.
    private static let bodyWithNoLineBreak = "Do the work."

    /// The same body with a line break at its end.
    private static let bodyWithLineBreak = "Do the work.\n"

    /// A list of the files of a skill.
    private static let filesText = "Files of this skill:\n- references/guide.md (reference)"

    /// The answer for each of the two bodies: one blank line between the body
    /// and the list.
    private static let joinedAnswer = "Do the work.\n\nFiles of this skill:\n- references/guide.md (reference)"

    @Test func aBodyWithNoLineBreakAtItsEndGetsOneBlankLineBeforeTheList() {
        #expect(SkillFilesText.appending(Self.filesText, to: Self.bodyWithNoLineBreak) == Self.joinedAnswer)
    }

    @Test func aBodyWithALineBreakAtItsEndGetsOneBlankLineBeforeTheList() {
        #expect(SkillFilesText.appending(Self.filesText, to: Self.bodyWithLineBreak) == Self.joinedAnswer)
    }

    /// The id of the skill that the files text names.
    private static let skillID = "with-script"

    /// The rows of a skill with one script.
    private static let scriptRows = [
        ResourceRow(path: "scripts/run.sh", kind: ListResource.scriptKind, bytes: 0, executable: true)
    ]

    /// The first words of the `run script` line.
    private static let runInstructionPrefix = "To run a script"

    @Test func theOpenModeGivesTheRunLineForAScript() throws {
        let text = try #require(SkillFilesText.text(id: Self.skillID, rows: Self.scriptRows, mode: .open))

        #expect(text.contains(Self.runInstructionPrefix))
    }

    @Test func theSandboxedModeGivesNoRunLineForAScript() throws {
        let text = try #require(SkillFilesText.text(id: Self.skillID, rows: Self.scriptRows, mode: .sandboxed))

        #expect(!text.contains(Self.runInstructionPrefix))
    }

    @Test func noListGivesTheBodyWithNoChange() {
        #expect(SkillFilesText.appending(nil, to: Self.bodyWithNoLineBreak) == Self.bodyWithNoLineBreak)
    }
}
