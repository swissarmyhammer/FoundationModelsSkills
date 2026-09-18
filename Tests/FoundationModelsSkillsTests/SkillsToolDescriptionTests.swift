import Foundation
@testable import FoundationModelsSkills
import Testing

/// Tests for `SkillsToolDescription`, the text that the `skills` tool gives
/// the model as its description.
///
/// The text has two fixed sentences, then a list of the visible skills. The
/// list has a character limit. The text tries four steps in order and stops
/// at the first one that fits: (a) each skill with its full description,
/// (b) each description shortened to the menu length, (c) the ids only on
/// one line, and (d) as many ids as fit and a count of the others. Each case
/// below makes a catalog that stops at one step.
struct SkillsToolDescriptionTests {
    // MARK: - Constants

    /// A limit that each small catalog of these cases fits in.
    private static let generousLimit = 8_000

    /// The length of each long description in the limit cases. It is longer
    /// than the menu length, thus step (b) shortens it.
    private static let longDescriptionLength = 300

    /// The most characters a description has after step (b): the menu
    /// length and one ellipsis.
    private static let shortenedDescriptionMaximum = 201

    /// The number of skills in the case that stops at step (b).
    private static let fewSkillCount = 3

    /// A limit that holds the few skills with shortened descriptions, but
    /// not with their full descriptions.
    private static let shortenLimit = 700

    /// The number of skills in the case that stops at step (c).
    private static let manySkillCount = 20

    /// A limit that holds each id of the many skills on one line, but not a
    /// shortened description for each of them.
    private static let idOnlyLimit = 900

    /// The number of skills in the case that stops at step (d).
    private static let hugeSkillCount = 200

    /// A limit that cannot hold each id of the huge catalog.
    private static let dropLimit = 700

    /// The two fixed sentences and the blank line after them, word for word
    /// from the card.
    private static let header =
        "Skills are procedures for kinds of work. Each one tells you how to do the work and which tools to use.\n"
        + "When a task matches a skill below, you must load that skill with `use skill` "
        + "and follow its instructions before you do the work.\n\n"

    /// The words of the step (d) note, after the count.
    private static let notListedNote = "more skills are not listed. Find them with `search skill`."

    // MARK: - (a) The full descriptions fit

    @Test func aCatalogThatFitsGivesTheFixedSentencesAndEachSkillWithItsDescription() {
        let catalog = [
            Self.skill(id: "explore", description: "Understand how code works before you change it."),
            Self.skill(id: "code-context", description: "Find symbols and their callers."),
        ]

        let text = SkillsToolDescription.make(catalog: catalog, characterLimit: Self.generousLimit)

        #expect(
            text == Self.header
                + "- explore: Understand how code works before you change it.\n"
                + "- code-context: Find symbols and their callers.")
    }

    @Test func aDescriptionOnManyLinesBecomesOneLine() {
        let catalog = [Self.skill(id: "explore", description: "Understand code.\n  Then change it.")]

        let text = SkillsToolDescription.make(catalog: catalog, characterLimit: Self.generousLimit)

        #expect(text.hasSuffix("- explore: Understand code. Then change it."))
    }

    // MARK: - No skill

    @Test func anEmptyCatalogGivesTheFirstSentenceAndTheNoSkillsLine() {
        let text = SkillsToolDescription.make(catalog: [], characterLimit: Self.generousLimit)

        #expect(text == "Skills are procedures for kinds of work.\nNo skills are installed now.")
    }

    // MARK: - (b) The descriptions shorten

    @Test func overTheLimitEachDescriptionShortensToTheMenuLength() throws {
        let catalog = Self.longCatalog(count: Self.fewSkillCount)

        let text = SkillsToolDescription.make(catalog: catalog, characterLimit: Self.shortenLimit)

        let list = try Self.list(in: text)
        #expect(list.count <= Self.shortenLimit)
        let lines = list.split(separator: "\n")
        #expect(lines.count == catalog.count)
        for (line, entry) in zip(lines, catalog) {
            let prefix = "- \(entry.id): "
            #expect(line.hasPrefix(prefix))
            #expect(line.hasSuffix("…"), "a shortened description ends with an ellipsis")
            #expect(line.count - prefix.count <= Self.shortenedDescriptionMaximum)
        }
    }

    // MARK: - (c) The ids only

    @Test func overTheLimitWithShortenedDescriptionsTheIDsShowOnOneLine() throws {
        let catalog = Self.longCatalog(count: Self.manySkillCount)

        let text = SkillsToolDescription.make(catalog: catalog, characterLimit: Self.idOnlyLimit)

        #expect(try Self.list(in: text) == catalog.map(\.id).joined(separator: ", "))
    }

    // MARK: - (d) Some ids drop

    @Test func overTheLimitWithTheIDsOnlyTheRestDropAndTheCountShows() throws {
        let catalog = Self.longCatalog(count: Self.hugeSkillCount)

        let text = SkillsToolDescription.make(catalog: catalog, characterLimit: Self.dropLimit)

        let list = try Self.list(in: text)
        #expect(list.count <= Self.dropLimit)
        let lines = list.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        let shown = try #require(lines.first).components(separatedBy: ", ")
        #expect(shown == Array(catalog.map(\.id).prefix(shown.count)))
        #expect(lines.last == "\(catalog.count - shown.count) \(Self.notListedNote)")
    }

    // MARK: - Fixtures

    /// Gives the list part of `text`: the text after the fixed sentences.
    ///
    /// - Parameter text: A full description.
    /// - Returns: The list part.
    /// - Throws: A `#require` failure when `text` does not start with the
    ///   fixed sentences.
    private static func list(in text: String) throws -> String {
        try #require(text.hasPrefix(header), "the fixed sentences are never cut")
        return String(text.dropFirst(header.count))
    }

    /// Makes one visible skill.
    ///
    /// - Parameters:
    ///   - id: The skill id.
    ///   - description: The skill description.
    /// - Returns: The metadata row.
    private static func skill(id: String, description: String) -> SkillMetadata {
        SkillMetadata(id: id, description: description, isModelVisible: true)
    }

    /// Makes `count` skills whose descriptions are each about
    /// `longDescriptionLength` characters of words.
    ///
    /// - Parameter count: The number of skills.
    /// - Returns: The catalog, in id order.
    private static func longCatalog(count: Int) -> [SkillMetadata] {
        let word = "word "
        let words = String(repeating: word, count: longDescriptionLength / word.count)
            .trimmingCharacters(in: .whitespaces)
        return (0..<count).map { index in
            skill(id: "skill-\(paddedIndex(index))", description: words)
        }
    }

    /// The width of each index in a fixture id.
    private static let indexWidth = 3

    /// Pads `index` with leading zeros to `indexWidth` digits.
    ///
    /// - Parameter index: The index to pad.
    /// - Returns: The padded index.
    private static func paddedIndex(_ index: Int) -> String {
        let digits = String(index)
        return String(repeating: "0", count: max(0, indexWidth - digits.count)) + digits
    }
}
