import Foundation
import FoundationModelsExtras

/// The layer of a registry that `SkillWriter` can write: the user layer or
/// the project layer.
///
/// The name of the option and its values are the same as the `layer` option
/// of the `agents` tool (AG-9, FoundationModelsAgents), thus a model gives the
/// same words to the two tools. ``default`` is `user` (D175).
///
/// The `.defaults` and `.marketplace` layers of a `DotfolderStack` are
/// read-only, thus this type has no case for them.
public enum SkillWriteLayer: String, CaseIterable, Sendable, Encodable {
    /// The user layer, for all projects. In the app its root is
    /// `<iCloud container>/Documents/Agents/_skills/`.
    case user

    /// The project layer, for this project only. In the app its root is
    /// `<cwd>/.skills/`.
    case project

    /// The layer of a write that names no layer.
    public static let `default`: SkillWriteLayer = .user

    /// The source of the registry layer that this value names.
    public var source: DotfolderStack.Source {
        switch self {
        case .user: .user
        case .project: .project
        }
    }

    /// The writable layer of `source`, or `nil` for a read-only source.
    ///
    /// - Parameter source: The source of a registry layer.
    init?(source: DotfolderStack.Source) {
        switch source {
        case .user: self = .user
        case .project: self = .project
        case .defaults, .marketplace: return nil
        }
    }
}

/// What one successful write of `SkillWriter` changed.
public struct SkillWriteResult: Sendable, Equatable, Encodable {
    /// The name of the skill: the name of its folder.
    public var name: String

    /// The layer that the write changed.
    public var layer: SkillWriteLayer

    /// The absolute path that the write changed: the file that `add` or
    /// `edit` wrote, or the folder that `remove` deleted.
    public var path: String

    /// Creates a result by directly assigning every field.
    ///
    /// - Parameters:
    ///   - name: The name of the skill.
    ///   - layer: The layer that the write changed.
    ///   - path: The absolute path that the write changed.
    public init(name: String, layer: SkillWriteLayer, path: String) {
        self.name = name
        self.layer = layer
        self.path = path
    }
}

/// The outcome of one write of `SkillWriter`: what the write changed, or a
/// corrective message for the model when the write did not occur.
public typealias SkillWriteOutcome = CorrectiveOutcome<SkillWriteResult>

/// Adds, edits and removes the files of a skill in the `.user` or `.project`
/// layer of a `SkillsRegistry`, and then reloads the registry.
///
/// The target root of a write is the root of the highest-precedence layer of
/// `registry.layers` whose source is the source of the `SkillWriteLayer`.
/// The host gives these roots through its `DotfolderStack`; this type never
/// computes a path of its own. A registry from `init(roots:)` labels each root
/// `.project` (`untrustedLayers(for:)`), thus such a registry has no `.user`
/// layer, and a write to `.user` gives a corrective.
///
/// The `.defaults` and `.marketplace` layers are read-only. A write never
/// changes them. To change a skill that only a read-only layer holds, the
/// model adds a skill of the same name in a writable layer, which overrides
/// it.
///
/// Each refusal is a corrective message, and the refused write changes no
/// file:
///
/// - a name that is not one path component;
/// - a layer that the registry does not have;
/// - `add` of a folder that the layer already holds;
/// - `edit` or `remove` of a folder that the layer does not hold;
/// - `edit` of a path that leaves the skill folder (the path rules of
///   `ReadResource`);
/// - a `SKILL.md` that `SkillValidator` gives a warning or a skip for.
///
/// A failure of the file system is not a refusal: it throws. After each
/// successful write the writer calls `registry.reload()`, thus
/// `registry.metadata()` shows the change when the call returns, and
/// `onReload` gives one value. No gate stands in front of a write (D78, D87).
public struct SkillWriter: Sendable {
    /// The registry whose layers this writer writes and reloads.
    public let registry: SkillsRegistry

    /// Creates a writer of the layers of `registry`.
    ///
    /// - Parameter registry: The registry to write and reload.
    public init(registry: SkillsRegistry) {
        self.registry = registry
    }

    /// Makes the folder `<root>/<name>/` and its `SKILL.md` in `layer`.
    ///
    /// - Parameters:
    ///   - name: The name of the new skill, which is the name of its folder.
    ///   - skillMarkdown: The full text of the `SKILL.md`.
    ///   - layer: The layer to write. The default is ``SkillWriteLayer/default``.
    /// - Returns: The file that the write made, or a corrective message.
    /// - Throws: Whatever the file system throws when it makes the folder or
    ///   writes the file. The writer then removes the folder that it made.
    public func add(
        name: String, skillMarkdown: String, layer: SkillWriteLayer = .default
    ) throws -> SkillWriteOutcome {
        try write(name: name, layer: layer) { target in
            guard !target.holdsFolder else {
                return .corrective(Self.existingFolderMessage(target))
            }
            let fileURL = target.folder.appendingPathComponent(Self.skillFileName)
            if let message = Self.invalidSkillFileMessage(skillMarkdown, at: fileURL, of: target) {
                return .corrective(message)
            }
            try Self.makeFolder(target.folder, thenWrite: skillMarkdown, to: fileURL)
            return .success(target.result(path: fileURL))
        }
    }

    /// Writes `content` to the file `path` of the skill `name` in `layer`.
    ///
    /// The skill folder must be in `layer`. The path uses the rules of
    /// `ReadResource`: it is relative, it has no `..` component, and it stays
    /// in `<root>/<name>/` after its symbolic links are resolved. A new file
    /// gets the folders above it. A write of `SKILL.md` is valid only when
    /// `SkillValidator` gives no warning and no skip for it.
    ///
    /// - Parameters:
    ///   - name: The name of the skill.
    ///   - path: The path of the file, relative to the skill folder.
    ///   - content: The full new text of the file.
    ///   - layer: The layer to write. The default is ``SkillWriteLayer/default``.
    /// - Returns: The file that the write changed, or a corrective message.
    /// - Throws: Whatever the file system throws when it makes a folder or
    ///   writes the file.
    public func edit(
        name: String, path: String, content: String, layer: SkillWriteLayer = .default
    ) throws -> SkillWriteOutcome {
        try write(name: name, layer: layer) { target in
            guard target.holdsFolder else {
                return .corrective(missingFolderMessage(target, for: .edit))
            }
            let fileURL = target.folder.appendingPathComponent(path)
            guard ResourcePathRules.isWellFormedRelativePath(path),
                let relativePath = PathConfinement.relativePath(of: fileURL, in: target.folder)
            else {
                return .corrective(ResourcePathRules.deniedMessage(path: path))
            }
            if relativePath == Self.skillFileName,
                let message = Self.invalidSkillFileMessage(content, at: fileURL, of: target)
            {
                return .corrective(message)
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success(target.result(path: fileURL))
        }
    }

    /// Deletes the folder `<root>/<name>/` in `layer`, with all its files.
    ///
    /// A copy of the skill in another layer stays.
    ///
    /// - Parameters:
    ///   - name: The name of the skill.
    ///   - layer: The layer to write. The default is ``SkillWriteLayer/default``.
    /// - Returns: The folder that the write deleted, or a corrective message.
    /// - Throws: Whatever the file system throws when it deletes the folder.
    public func remove(name: String, layer: SkillWriteLayer = .default) throws -> SkillWriteOutcome {
        try write(name: name, layer: layer) { target in
            guard target.holdsFolder else {
                return .corrective(missingFolderMessage(target, for: .remove))
            }
            try FileManager.default.removeItem(at: target.folder)
            return .success(target.result(path: target.folder))
        }
    }

    // MARK: - The target of a write

    /// The skill folder of one write, in the layer that the write changes.
    private struct Target {
        /// The name of the skill.
        let name: String

        /// The writable layer that the model named.
        let writeLayer: SkillWriteLayer

        /// The registry layer of `writeLayer`.
        let layer: DotfolderStack.Layer

        /// The position of `layer` in the layers of the registry, lowest
        /// precedence first.
        let layerIndex: Int

        /// The skill folder, `<root>/<name>/`.
        var folder: URL {
            layer.root.appendingPathComponent(name, isDirectory: true)
        }

        /// Whether `layer` holds the skill folder, as a folder that stays in
        /// the layer root.
        var holdsFolder: Bool {
            !DotfolderStack(layers: [layer]).layerDirectories(name).isEmpty
        }

        /// The result of a write of this target that changed `url`.
        ///
        /// - Parameter url: The file or the folder that the write changed.
        /// - Returns: The result.
        func result(path url: URL) -> SkillWriteResult {
            SkillWriteResult(name: name, layer: writeLayer, path: url.path)
        }
    }

    /// Finds the target of a write, runs `body` on it, and reloads the
    /// registry when `body` gives a success.
    ///
    /// - Parameters:
    ///   - name: The name of the skill.
    ///   - layer: The writable layer that the model named.
    ///   - body: The write of the target.
    /// - Returns: The outcome of `body`, or a corrective message for a bad
    ///   name or for a layer that the registry does not have.
    /// - Throws: Whatever `body` throws.
    private func write(
        name: String, layer: SkillWriteLayer, _ body: (Target) throws -> SkillWriteOutcome
    ) throws -> SkillWriteOutcome {
        guard Self.isSinglePathComponent(name) else {
            return .corrective(Self.badNameMessage(name))
        }
        guard let layerIndex = registry.layers.lastIndex(where: { $0.source == layer.source }) else {
            return .corrective(missingLayerMessage(layer))
        }
        let target = Target(
            name: name, writeLayer: layer, layer: registry.layers[layerIndex], layerIndex: layerIndex)
        let outcome = try body(target)
        if case .success = outcome {
            registry.reload()
        }
        return outcome
    }

    /// The file name of the skill file of a skill folder.
    private static let skillFileName = SkillDiscovery.skillFileName

    /// The separator of the components of a path.
    private static let pathSeparator: Character = "/"

    /// The names that are a path component but name no child folder: the
    /// folder itself and the folder above it.
    private static let relativeFolderNames: Set<String> = [".", ".."]

    /// Whether `name` is one path component that names a child folder: not
    /// empty, with no `/`, and not `.` or `..`.
    ///
    /// - Parameter name: The name of a skill.
    /// - Returns: `true` for a name that is safe to join onto a layer root.
    private static func isSinglePathComponent(_ name: String) -> Bool {
        !name.isEmpty && !name.contains(pathSeparator) && !relativeFolderNames.contains(name)
    }

    /// Makes `folder` and then writes `text` to `fileURL` in it. When the
    /// write fails, removes `folder` again, thus a failed `add` leaves no
    /// empty folder.
    ///
    /// - Parameters:
    ///   - folder: The new skill folder.
    ///   - text: The text of the file.
    ///   - fileURL: The file in `folder`.
    /// - Throws: Whatever the file system throws when it makes the folder or
    ///   writes the file.
    private static func makeFolder(_ folder: URL, thenWrite text: String, to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    // MARK: - Validation of a skill file

    /// The severities of a diagnostic that refuse a write of a skill file. A
    /// warning or a skip changes how the skill loads; an advisory does not.
    private static let refusingSeverities: Set<SkillDiagnostic.Severity> = [.warning, .skip]

    /// The corrective message for a skill file that must not be written, or
    /// `nil` for a skill file that is valid.
    ///
    /// The check is the check of a load: the frontmatter split of Extras,
    /// the decode of `FrontmatterDecoder`, the `enabled` rule of Extras, and
    /// `SkillValidator` with `target` as the winning layer.
    ///
    /// - Parameters:
    ///   - text: The full text of the skill file.
    ///   - fileURL: The skill file that the write would change.
    ///   - target: The target of the write.
    /// - Returns: The corrective message, or `nil`.
    private static func invalidSkillFileMessage(_ text: String, at fileURL: URL, of target: Target) -> String? {
        let split = FrontmatterDocument.split(text: text)
        let outcome = FrontmatterDecoder.Outcome(
            metadata: split.frontmatter.map { FrontmatterDecoder.decode(frontmatter: $0) }, body: split.body)
        let discovered = DiscoveredSkill(
            id: target.name, skillDirectory: target.folder, skillFileURL: fileURL, rootIndex: target.layerIndex,
            root: target.layer.root)
        let validatorProblems = SkillValidator.validate(discovered: discovered, outcome: outcome).diagnostics
            .filter { refusingSeverities.contains($0.severity) }.map(\.message)
        let problems = enablementProblems(of: split.frontmatter) + validatorProblems
        guard !problems.isEmpty else { return nil }
        return "The `\(skillFileName)` of `\(target.name)` was not written: \(problems.joined(separator: "; ")). "
            + "Correct the file and write it again."
    }

    /// The problem of the `enabled` key of `frontmatter`, when its value is
    /// not a bool. Such a skill does not load.
    ///
    /// - Parameter frontmatter: The text of the frontmatter block, or `nil`
    ///   when the file has no frontmatter block.
    /// - Returns: The text of the problem, or no text.
    private static func enablementProblems(of frontmatter: String?) -> [String] {
        guard let frontmatter, case .invalid(let message) = FrontmatterEnablement(frontmatter: frontmatter) else {
            return []
        }
        return [message]
    }

    // MARK: - Corrective messages

    /// A write that needs a skill folder that the layer already holds.
    private enum FolderOperation {
        /// `edit`, which writes a file of the folder.
        case edit
        /// `remove`, which deletes the folder.
        case remove
    }

    /// The corrective message for a name that is not one path component.
    ///
    /// - Parameter name: The refused name.
    /// - Returns: The corrective message.
    private static func badNameMessage(_ name: String) -> String {
        "The skill name `\(name)` is not valid. Give one folder name: not empty, with no `/`, and not `.` or `..`."
    }

    /// The corrective message for a layer that the registry does not have.
    ///
    /// - Parameter layer: The layer that the model named.
    /// - Returns: The corrective message, which names the writable layers
    ///   that the registry has.
    private func missingLayerMessage(_ layer: SkillWriteLayer) -> String {
        let available = SkillWriteLayer.allCases.filter { candidate in
            registry.layers.contains { $0.source == candidate.source }
        }
        let advice =
            available.isEmpty
            ? "This registry has no writable layer."
            : "Use the layer \(Self.quotedList(available.map(\.rawValue)))."
        return "This registry has no \(layer.rawValue) layer. \(advice)"
    }

    /// The corrective message for `add` of a folder that the layer already
    /// holds.
    ///
    /// - Parameter target: The target of the write.
    /// - Returns: The corrective message.
    private static func existingFolderMessage(_ target: Target) -> String {
        "The skill `\(target.name)` is already in the \(target.writeLayer.rawValue) layer. "
            + "Use `edit` to change it, or `remove` and then `add`."
    }

    /// The corrective message for `edit` or `remove` of a folder that the
    /// layer does not hold.
    ///
    /// The message names the layers that hold the folder. When only
    /// read-only layers hold it, an `edit` message tells the model to use
    /// `add` with the same name in a writable layer to override it.
    ///
    /// - Parameters:
    ///   - target: The target of the write.
    ///   - operation: The write that needs the folder.
    /// - Returns: The corrective message.
    private func missingFolderMessage(_ target: Target, for operation: FolderOperation) -> String {
        let holders = DotfolderStack(layers: registry.layers).layerDirectories(target.name).map(\.source)
        let start = "The skill `\(target.name)` is not in the \(target.writeLayer.rawValue) layer."
        guard !holders.isEmpty else {
            return start + (operation == .edit ? " Use `add` to make it." : "")
        }
        let holderNames = Self.quotedList(Self.uniqueNames(of: holders))
        let writableHolders = holders.compactMap(SkillWriteLayer.init(source:))
        if let writable = writableHolders.last {
            return start + " It is in the layer \(holderNames). Give the layer `\(writable.rawValue)`."
        }
        let readOnly = start + " It is only in the read-only layer \(holderNames)."
        return operation == .edit
            ? readOnly + " To override it, use `add` with the name `\(target.name)` and the layer "
                + "\(Self.quotedList(SkillWriteLayer.allCases.map(\.rawValue)))."
            : readOnly + " A read-only skill cannot be removed."
    }

    /// The name of each source in `sources`, each name one time, in the
    /// order of `sources`.
    ///
    /// - Parameter sources: The sources of some layers.
    /// - Returns: The names.
    private static func uniqueNames(of sources: [DotfolderStack.Source]) -> [String] {
        var seen: Set<String> = []
        return sources.map(layerName(of:)).filter { seen.insert($0).inserted }
    }

    /// The name of a layer of `source` in a corrective message.
    ///
    /// - Parameter source: The source of a layer.
    /// - Returns: The name.
    private static func layerName(of source: DotfolderStack.Source) -> String {
        switch source {
        case .defaults: "defaults"
        case .user: SkillWriteLayer.user.rawValue
        case .project: SkillWriteLayer.project.rawValue
        case .marketplace: "marketplace"
        }
    }

    /// `names`, each in backquotes, joined with `or`.
    ///
    /// - Parameter names: The names to join.
    /// - Returns: The joined text, for example `` `user` or `project` ``.
    private static func quotedList(_ names: [String]) -> String {
        names.map { "`\($0)`" }.joined(separator: " or ")
    }
}
