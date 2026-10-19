@testable import FoundationModelsSkills
import Testing

/// Tests for `SkillsToolDescription.catalogEntries(for:isListed:)`, the
/// entries that the list of the `skills` tool description shows.
///
/// Each test maps the old and the new catalog to entries, and then compares
/// the two lists with the Extras `CatalogChangeNotice(kind:from:to:)`. The
/// list shows each visible skill as its id and its description on one line.
/// Thus only an id that comes or goes, or a one-line description that
/// differs, gives a notice. A change that the list never showed gives none.
struct SkillCatalogEntriesTests {
    @Test func identicalCatalogsGiveNoNotice() {
        let catalog = [Self.skill("alpha", "Does alpha."), Self.skill("beta", "Does beta.")]

        #expect(Self.notice(from: catalog, to: catalog) == nil)
    }

    @Test func aNewVisibleSkillIsAddedInNewCatalogOrder() throws {
        let alpha = Self.skill("alpha", "Does alpha.")
        let beta = Self.skill("beta", "Does beta.")
        let gamma = Self.skill("gamma", "Does gamma.")

        let notice = try #require(Self.notice(from: [alpha], to: [gamma, alpha, beta]))

        #expect(
            notice.added == [
                CatalogEntry(name: "gamma", description: "Does gamma."),
                CatalogEntry(name: "beta", description: "Does beta."),
            ])
        #expect(notice.removed.isEmpty)
        #expect(notice.changed.isEmpty)
    }

    @Test func aDroppedVisibleSkillIsRemovedInOldCatalogOrder() throws {
        let alpha = Self.skill("alpha", "Does alpha.")
        let beta = Self.skill("beta", "Does beta.")
        let gamma = Self.skill("gamma", "Does gamma.")

        let notice = try #require(Self.notice(from: [gamma, alpha, beta], to: [alpha]))

        #expect(
            notice.removed == [
                CatalogEntry(name: "gamma", description: "Does gamma."),
                CatalogEntry(name: "beta", description: "Does beta."),
            ])
        #expect(notice.added.isEmpty)
        #expect(notice.changed.isEmpty)
    }

    @Test func anEditedDescriptionIsChanged() throws {
        let old = Self.skill("alpha", "Does alpha.")
        let new = Self.skill("alpha", "Does alpha better.")

        let notice = try #require(Self.notice(from: [old], to: [new]))

        #expect(notice.changed == [CatalogEntry(name: "alpha", description: "Does alpha better.")])
        #expect(notice.added.isEmpty)
        #expect(notice.removed.isEmpty)
    }

    @Test func whiteSpaceThatTheListCollapsesGivesNoNotice() {
        let old = Self.skill("alpha", "Does alpha\nwell.")
        let new = Self.skill("alpha", "Does   alpha well.  ")

        #expect(Self.notice(from: [old], to: [new]) == nil)
    }

    @Test func aChangeTheListDoesNotShowGivesNoNotice() {
        let old = Self.skill("alpha", "Does alpha.")
        var new = old
        new.parameters = ["<message>"]
        new.source = "skills@1a2b3c4"

        #expect(Self.notice(from: [old], to: [new]) == nil)
    }

    @Test func aSkillThatTurnsHiddenIsRemovedAndOneThatTurnsVisibleIsAdded() throws {
        let alpha = Self.skill("alpha", "Does alpha.")
        let beta = Self.skill("beta", "Does beta.", visible: false)
        var hiddenAlpha = alpha
        hiddenAlpha.isModelVisible = false
        var visibleBeta = beta
        visibleBeta.isModelVisible = true

        let notice = try #require(Self.notice(from: [alpha, beta], to: [hiddenAlpha, visibleBeta]))

        #expect(notice.removed == [CatalogEntry(name: "alpha", description: "Does alpha.")])
        #expect(notice.added == [CatalogEntry(name: "beta", description: "Does beta.")])
        #expect(notice.changed.isEmpty)
    }

    @Test func aHiddenSkillChangeGivesNoNotice() {
        let old = Self.skill("beta", "Does beta.", visible: false)
        let new = Self.skill("beta", "Does beta differently.", visible: false)

        #expect(Self.notice(from: [old], to: [new]) == nil)
    }

    @Test func aCustomPredicateDecidesWhatTheListShows() throws {
        let deploy = Self.skill("deploy", "Deploys.", visible: false)
        let lint = Self.skill("lint", "Lints.")

        let notice = try #require(Self.notice(from: [lint], to: [lint, deploy]) { $0.id == "deploy" })

        #expect(notice.added == [CatalogEntry(name: "deploy", description: "Deploys.")])
        #expect(notice.removed.isEmpty)
        #expect(notice.changed.isEmpty)
    }

    // MARK: - Helpers

    /// Builds one catalog entry.
    ///
    /// - Parameters:
    ///   - id: The skill id.
    ///   - description: The description.
    ///   - visible: Whether the model sees the skill. Defaults to `true`.
    /// - Returns: The metadata row.
    private static func skill(_ id: String, _ description: String, visible: Bool = true) -> SkillMetadata {
        SkillMetadata(id: id, description: description, isModelVisible: visible)
    }

    /// Maps both catalogs to the entries of the list, and compares them with
    /// the Extras compare.
    ///
    /// - Parameters:
    ///   - old: The catalog before the reload, unfiltered.
    ///   - new: The catalog after the reload, unfiltered.
    ///   - isListed: Which skills the list shows. Defaults to
    ///     `SkillMetadata.isModelVisible`.
    /// - Returns: The notice, or `nil` when the list shows no change.
    private static func notice(
        from old: [SkillMetadata], to new: [SkillMetadata],
        isListed: (SkillMetadata) -> Bool = { $0.isModelVisible }
    ) -> CatalogChangeNotice? {
        CatalogChangeNotice(
            kind: .skills,
            from: SkillsToolDescription.catalogEntries(for: old, isListed: isListed),
            to: SkillsToolDescription.catalogEntries(for: new, isListed: isListed))
    }
}
