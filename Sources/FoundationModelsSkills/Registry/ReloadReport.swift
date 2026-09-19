/// What one hot reload of a ``SkillsRegistry`` changed, as lines a host can
/// write.
///
/// A host that follows ``SkillsRegistry/onReload`` shows what each reload
/// carried: how many skills the registry published, how many of them the
/// model sees, how long the refreshed preload text is, and which skills the
/// refreshed `/` listing holds. The report reads those four things one time,
/// and the host writes ``lines``. Thus no host keeps its own copy of the
/// reading or of the wording.
public struct ReloadReport: Sendable, Equatable {
    /// How many skills the reload published.
    public let skillCount: Int

    /// How many of those skills the model sees.
    public let modelVisibleCount: Int

    /// How many characters the refreshed preload text holds.
    public let preloadedCharacterCount: Int

    /// The ids of the refreshed `/` command listing, in listing order.
    public let commandIDs: [String]

    /// What goes between two ids of the listing line.
    private static let idSeparator = ", "

    /// Reads the report of one reload.
    ///
    /// The call renders every preloaded body, thus it suspends. A body that
    /// carries a shell command runs that command under the limits of the
    /// render policy of the registry.
    ///
    /// - Parameters:
    ///   - metadata: The refreshed metadata that ``SkillsRegistry/onReload``
    ///     published.
    ///   - registry: The registry to read the refreshed preload text and the
    ///     refreshed `/` listing from.
    /// - Returns: The report of that reload.
    public static func make(
        metadata: [SkillMetadata], registry: SkillsRegistry
    ) async -> ReloadReport {
        ReloadReport(
            skillCount: metadata.count,
            modelVisibleCount: metadata.filter(\.isModelVisible).count,
            preloadedCharacterCount: await registry.preloadedBodies().count,
            commandIDs: registry.commandListing().map(\.id))
    }

    /// The lines of the report, in write order, each one with no line break
    /// at its end.
    public var lines: [String] {
        [
            "reload: \(skillCount) skills, \(modelVisibleCount) model-visible",
            "preload: \(preloadedCharacterCount) rendered characters",
            "listing: \(commandIDs.joined(separator: Self.idSeparator))",
        ]
    }
}
