import Foundation

/// The skills of one marketplace after ``CatalogResolver`` applies the
/// catalog and the host selection (marketplace.md §5.2 and §6.4).
internal struct ResolvedCatalog: Sendable, Hashable {
    /// The catalog `name`, or `nil` when the resolver scanned the repository.
    var name: String?

    /// The catalog `metadata.version`, or `nil` when there is none.
    var version: String?

    /// The selected skills, in catalog order.
    var skills: [ResolvedSkill]

    /// The `renames` map of the catalog. It is empty for a scan.
    var renames: [String: String?]

    /// The findings of the resolution. Each problem is one diagnostic.
    var diagnostics: [MarketplaceDiagnostic]
}

/// One skill that a marketplace gives.
internal struct ResolvedSkill: Sendable, Hashable {
    /// The skill name: the name of the skill folder, or the frontmatter
    /// `name` of a root `SKILL.md`.
    var name: String

    /// The path of the skill folder in the tree. The empty path is the root.
    var path: String

    /// The plugin that lists the skill, or `nil` for a scan.
    var plugin: String?
}

/// Reads the catalog of a marketplace from a ``CatalogFileSource`` and
/// resolves the list of skills (marketplace.md §5.2 and §6.4).
///
/// The resolver looks for these, in order, and uses the first that it finds:
///
/// 1. `.claude-plugin/marketplace.json`.
/// 2. `.agents/plugins/marketplace.json` (Codex). The same rules apply.
/// 3. No catalog: a scan of the repository for `SKILL.md` files, to a depth
///    of ``maximumScanDepth``. The shallower `SKILL.md` wins.
///
/// The skills of a plugin are its `skills` array, else the folders of
/// `<plugin source>/skills/` that hold a `SKILL.md` file. A plugin with a
/// remote source is skipped. When two plugins give the same skill name, the
/// later plugin wins. A selected name that the catalog renamed maps to the
/// new name, and a name that the catalog removed selects nothing.
///
/// The resolver never throws. Each problem gives one ``MarketplaceDiagnostic``,
/// and the resolver continues where it can.
internal enum CatalogResolver {
    /// The catalog paths, in the order that the resolver reads them.
    static let catalogPaths = [".claude-plugin/marketplace.json", ".agents/plugins/marketplace.json"]

    /// The deepest `SKILL.md` that a scan finds, as a count of path
    /// components: `SKILL.md` is 1, and `skills/<name>/SKILL.md` is 3.
    static let maximumScanDepth = 3

    /// The folder of a plugin that holds its skill folders when the plugin
    /// has no `skills` array.
    static let pluginSkillsFolderName = "skills"

    /// The result of the read of one catalog path.
    private enum CatalogRead {
        /// The file is a catalog.
        case found(MarketplaceCatalog)

        /// No file is at the path.
        case missing

        /// The file is at the path, but it cannot be read or decoded.
        case unusable(MarketplaceDiagnostic)
    }

    /// Resolves the skills of one marketplace tree.
    ///
    /// - Parameters:
    ///   - source: The files of the tree.
    ///   - selection: The skills that the host takes from the marketplace.
    /// - Returns: The selected skills, with a diagnostic for each problem.
    static func resolve(from source: any CatalogFileSource, selection: SkillSelection) -> ResolvedCatalog {
        for path in catalogPaths {
            switch readCatalog(atPath: path, from: source) {
            case .missing:
                continue
            case .unusable(let diagnostic):
                return ResolvedCatalog(name: nil, version: nil, skills: [], renames: [:], diagnostics: [diagnostic])
            case .found(let catalog):
                return CatalogReader(source: source, marketplaceID: catalog.name).resolved(catalog, selection: selection)
            }
        }
        return CatalogReader(source: source, marketplaceID: nil).scanned(selection: selection)
    }

    /// Reads and decodes the catalog at one path.
    ///
    /// - Parameters:
    ///   - path: The catalog path in the tree.
    ///   - source: The files of the tree.
    /// - Returns: The catalog, the fact that no file is at the path, or an
    ///   error diagnostic.
    private static func readCatalog(atPath path: String, from source: any CatalogFileSource) -> CatalogRead {
        do {
            guard let data = try source.contents(atPath: path) else {
                return .missing
            }
            return try .found(JSONDecoder().decode(MarketplaceCatalog.self, from: data))
        } catch {
            return .unusable(
                MarketplaceDiagnostic(
                    severity: .error, marketplaceID: nil, message: #"The catalog "\#(path)" is not usable: \#(error)"#))
        }
    }
}

/// A value, with the diagnostics of the step that made it.
private struct Diagnosed<Value> {
    /// The value of the step.
    var value: Value

    /// The findings of the step.
    var diagnostics: [MarketplaceDiagnostic] = []

    /// Changes the value and keeps the diagnostics.
    ///
    /// - Parameter transform: The change of the value.
    /// - Returns: The changed value, with the same diagnostics.
    func map<NewValue>(_ transform: (Value) -> NewValue) -> Diagnosed<NewValue> {
        Diagnosed<NewValue>(value: transform(value), diagnostics: diagnostics)
    }
}

/// The steps of one resolution over one tree.
private struct CatalogReader {
    /// What a selected name names, for the text of a diagnostic.
    enum SelectionNoun: String {
        /// A plugin name.
        case plugin

        /// A skill name.
        case skill
    }

    /// Which skill wins when two skills have the same name.
    enum DuplicateWinner {
        /// The first skill wins: the shallower `SKILL.md` of a scan.
        case first

        /// The last skill wins: the later plugin of a catalog.
        case last
    }

    /// The files of the tree.
    let source: any CatalogFileSource

    /// The marketplace id that each diagnostic carries: the catalog name, or
    /// `nil` for a scan.
    let marketplaceID: String?

    // MARK: - Catalog

    /// Resolves the skills of a catalog.
    ///
    /// - Parameters:
    ///   - catalog: The decoded catalog.
    ///   - selection: The host selection.
    /// - Returns: The selected skills, with a diagnostic for each problem.
    func resolved(_ catalog: MarketplaceCatalog, selection: SkillSelection) -> ResolvedCatalog {
        let renamed = renamedSelection(selection, renames: catalog.renames)
        let plugins = selectedPlugins(catalog.plugins, selection: renamed.value)
        let listed = plugins.value.map { skills(of: $0) }
        let unique = deduplicated(listed.flatMap(\.value), winner: .last)
        let selected = selectedSkills(unique.value, selection: renamed.value)
        return ResolvedCatalog(
            name: catalog.name, version: catalog.metadata?.version, skills: selected.value, renames: catalog.renames,
            diagnostics: renamed.diagnostics + plugins.diagnostics + listed.flatMap(\.diagnostics)
                + unique.diagnostics + selected.diagnostics)
    }

    /// Finds the skills of one plugin.
    ///
    /// - Parameter plugin: The plugin entry.
    /// - Returns: The skills of the plugin. A remote plugin gives no skill and
    ///   one warning.
    func skills(of plugin: MarketplaceCatalog.Plugin) -> Diagnosed<[ResolvedSkill]> {
        switch plugin.source {
        case .remote(let remote):
            Diagnosed(value: [], diagnostics: [remoteSourceDiagnostic(plugin: plugin.name, source: remote)])
        case .relative(let path):
            skills(of: plugin, inFolder: path)
        }
    }

    /// Finds the skills of one plugin with a relative source.
    ///
    /// - Parameters:
    ///   - plugin: The plugin entry.
    ///   - path: The source path of the plugin, as the catalog writes it.
    /// - Returns: The skills of the `skills` array, else of the
    ///   `<source>/skills/` folder.
    func skills(of plugin: MarketplaceCatalog.Plugin, inFolder path: String) -> Diagnosed<[ResolvedSkill]> {
        guard let root = CatalogPath.normalized(path) else {
            let message =
                #"The plugin "\#(plugin.name)" has the source path "\#(path)", which is not a relative path in the repository. The resolver skips this plugin."#
            return Diagnosed(value: [], diagnostics: [diagnostic(.warning, saying: message)])
        }
        guard let entries = plugin.skills else {
            return folderSkills(ofPlugin: plugin.name, root: root)
        }
        let found = entries.map { listedSkill($0, ofPlugin: plugin.name, root: root) }
        return Diagnosed(value: found.compactMap(\.value), diagnostics: found.flatMap(\.diagnostics))
    }

    /// Finds one skill of a `skills` array.
    ///
    /// - Parameters:
    ///   - entry: The entry of the array, relative to the plugin source.
    ///   - plugin: The name of the plugin.
    ///   - root: The normalized source path of the plugin.
    /// - Returns: The skill, or `nil` and one diagnostic when the entry is not
    ///   a skill folder.
    func listedSkill(_ entry: String, ofPlugin plugin: String, root: String) -> Diagnosed<ResolvedSkill?> {
        guard let path = CatalogPath.resolved(entry, inFolder: root), let name = CatalogPath.lastComponent(of: path)
        else {
            let message =
                #"The plugin "\#(plugin)" lists the skill path "\#(entry)", which is not a folder in the repository. The resolver skips it."#
            return Diagnosed(value: nil, diagnostics: [diagnostic(.warning, saying: message)])
        }
        do {
            guard try hasSkillFile(inFolder: path) else {
                let message =
                    #"The plugin "\#(plugin)" lists the skill folder "\#(path)", which has no SKILL.md file. The resolver skips it."#
                return Diagnosed(value: nil, diagnostics: [diagnostic(.warning, saying: message)])
            }
            return Diagnosed(value: ResolvedSkill(name: name, path: path, plugin: plugin))
        } catch {
            return Diagnosed(value: nil, diagnostics: [readFailure(atPath: path, error: error)])
        }
    }

    /// Finds the skills of a plugin that has no `skills` array: the folders
    /// of `<root>/skills/` that hold a `SKILL.md` file.
    ///
    /// A folder with no `SKILL.md` file is not a skill, and it gives no
    /// diagnostic. Discovery skips such a folder in the same way.
    ///
    /// - Parameters:
    ///   - plugin: The name of the plugin.
    ///   - root: The normalized source path of the plugin.
    /// - Returns: The skills, in name order. A plugin with no skills folder
    ///   gives no skill.
    func folderSkills(ofPlugin plugin: String, root: String) -> Diagnosed<[ResolvedSkill]> {
        let folder = CatalogPath.child(CatalogResolver.pluginSkillsFolderName, of: root)
        do {
            let skills = try source.entries(inDirectory: folder)
                .filter(Self.isSubfolder)
                .map { ResolvedSkill(name: $0.name, path: CatalogPath.child($0.name, of: folder), plugin: plugin) }
                .filter { try hasSkillFile(inFolder: $0.path) }
            return Diagnosed(value: skills)
        } catch {
            return Diagnosed(value: [], diagnostics: [readFailure(atPath: folder, error: error)])
        }
    }

    // MARK: - Scan

    /// Resolves the skills of a tree that has no catalog.
    ///
    /// - Parameter selection: The host selection.
    /// - Returns: The selected skills of the scan. A scan has no plugin, so a
    ///   ``SkillSelection/plugins(_:)`` selection gives no skill and one
    ///   warning for each name.
    func scanned(selection: SkillSelection) -> ResolvedCatalog {
        guard case .plugins = selection else {
            let found = scannedSkills()
            let selected = selectedSkills(found.value, selection: selection)
            return ResolvedCatalog(
                name: nil, version: nil, skills: selected.value, renames: [:],
                diagnostics: found.diagnostics + selected.diagnostics)
        }
        return ResolvedCatalog(
            name: nil, version: nil, skills: [], renames: [:],
            diagnostics: selectedPlugins([], selection: selection).diagnostics)
    }

    /// Scans the tree for skills, to a depth of
    /// ``CatalogResolver/maximumScanDepth``.
    ///
    /// - Returns: One skill for each name. The shallower `SKILL.md` wins, and
    ///   each deeper skill with the same name gives one warning.
    func scannedSkills() -> Diagnosed<[ResolvedSkill]> {
        let folders = skillFolders(in: [""], depth: 1)
        let named = folders.value.map { scannedSkill(atFolder: $0) }
        let unique = deduplicated(named.compactMap(\.value), winner: .first)
        return Diagnosed(
            value: unique.value,
            diagnostics: folders.diagnostics + named.flatMap(\.diagnostics) + unique.diagnostics)
    }

    /// Finds the folders that hold a `SKILL.md` file, one level at a time.
    ///
    /// - Parameters:
    ///   - folders: The folders of one level, in walk order.
    ///   - depth: The depth of a `SKILL.md` file in these folders.
    /// - Returns: The skill folders of this level and of the deeper levels,
    ///   shallower first.
    func skillFolders(in folders: [String], depth: Int) -> Diagnosed<[String]> {
        guard depth <= CatalogResolver.maximumScanDepth, !folders.isEmpty else {
            return Diagnosed(value: [])
        }
        let listings = folders.map { (folder: $0, listing: listing(ofFolder: $0)) }
        let found = listings.filter { $0.listing.value.contains(where: Self.isSkillFile) }.map(\.folder)
        let children = listings.flatMap { level in
            level.listing.value.filter(Self.isSubfolder).map { CatalogPath.child($0.name, of: level.folder) }
        }
        let deeper = skillFolders(in: children, depth: depth + 1)
        return Diagnosed(
            value: found + deeper.value, diagnostics: listings.flatMap(\.listing.diagnostics) + deeper.diagnostics)
    }

    /// Names the skill of one scanned folder.
    ///
    /// - Parameter folder: The skill folder. The empty path is the root.
    /// - Returns: The skill. A folder skill takes the folder name. The root
    ///   skill takes the frontmatter `name` of its `SKILL.md`.
    func scannedSkill(atFolder folder: String) -> Diagnosed<ResolvedSkill?> {
        guard folder.isEmpty else {
            return Diagnosed(
                value: CatalogPath.lastComponent(of: folder).map { ResolvedSkill(name: $0, path: folder, plugin: nil) })
        }
        do {
            guard let name = try rootSkillName() else {
                let message = "The root SKILL.md has no frontmatter name that is one folder name. The resolver skips it."
                return Diagnosed(value: nil, diagnostics: [diagnostic(.warning, saying: message)])
            }
            return Diagnosed(value: ResolvedSkill(name: name, path: "", plugin: nil))
        } catch {
            return Diagnosed(value: nil, diagnostics: [readFailure(atPath: SkillDiscovery.skillFileName, error: error)])
        }
    }

    /// Reads the frontmatter `name` of the root `SKILL.md`.
    ///
    /// - Returns: The name, or `nil` when the file has no name that is one
    ///   folder name.
    /// - Throws: The error of the file read.
    func rootSkillName() throws -> String? {
        guard let data = try source.contents(atPath: SkillDiscovery.skillFileName),
            case .decoded(let skill) = FrontmatterDecoder.decode(text: String(decoding: data, as: UTF8.self)),
            let name = skill.frontmatter.name, CatalogPath.isSingleComponent(name)
        else {
            return nil
        }
        return name
    }

    // MARK: - Selection

    /// Applies the `renames` map of the catalog to the names of a selection.
    ///
    /// - Parameters:
    ///   - selection: The host selection.
    ///   - renames: The `renames` map of the catalog.
    /// - Returns: The selection with the new names. Each renamed name gives
    ///   one advisory, and each removed name gives one warning.
    func renamedSelection(_ selection: SkillSelection, renames: [String: String?]) -> Diagnosed<SkillSelection> {
        switch selection {
        case .all:
            Diagnosed(value: .all)
        case .plugins(let names):
            renamedNames(names, renames: renames).map(SkillSelection.plugins)
        case .skills(let names):
            renamedNames(names, renames: renames).map(SkillSelection.skills)
        }
    }

    /// Applies the `renames` map of the catalog to a list of selected names.
    ///
    /// - Parameters:
    ///   - names: The selected names.
    ///   - renames: The `renames` map of the catalog.
    /// - Returns: The names after the map, with no removed name.
    func renamedNames(_ names: [String], renames: [String: String?]) -> Diagnosed<[String]> {
        let renamed = names.map { renamedName($0, renames: renames) }
        return Diagnosed(value: renamed.compactMap(\.value), diagnostics: renamed.flatMap(\.diagnostics))
    }

    /// Applies the `renames` map of the catalog to one selected name.
    ///
    /// - Parameters:
    ///   - name: The selected name.
    ///   - renames: The `renames` map of the catalog.
    /// - Returns: The same name when the map does not have it, the new name
    ///   with one advisory, or `nil` with one warning when the catalog
    ///   removed the name.
    func renamedName(_ name: String, renames: [String: String?]) -> Diagnosed<String?> {
        guard let entry = renames[name] else {
            return Diagnosed(value: name)
        }
        guard let newName = entry else {
            let message = #"The selected name "\#(name)" is removed from the catalog. It selects nothing."#
            return Diagnosed(value: nil, diagnostics: [diagnostic(.warning, saying: message)])
        }
        let message = #"The selected name "\#(name)" is renamed to "\#(newName)" in the catalog. The resolver uses "\#(newName)"."#
        return Diagnosed(value: newName, diagnostics: [diagnostic(.advisory, saying: message)])
    }

    /// Keeps the plugins that a ``SkillSelection/plugins(_:)`` selection
    /// names.
    ///
    /// - Parameters:
    ///   - plugins: The plugins of the catalog, in catalog order.
    ///   - selection: The selection, after the renames.
    /// - Returns: The selected plugins in catalog order. The other selections
    ///   keep every plugin.
    func selectedPlugins(
        _ plugins: [MarketplaceCatalog.Plugin], selection: SkillSelection
    ) -> Diagnosed<[MarketplaceCatalog.Plugin]> {
        guard case .plugins(let names) = selection else {
            return Diagnosed(value: plugins)
        }
        return filtered(plugins, keepingNames: names, noun: .plugin, nameOf: \.name)
    }

    /// Keeps the skills that a ``SkillSelection/skills(_:)`` selection names.
    ///
    /// - Parameters:
    ///   - skills: The skills, in catalog order.
    ///   - selection: The selection, after the renames.
    /// - Returns: The selected skills in catalog order. The other selections
    ///   keep every skill.
    func selectedSkills(_ skills: [ResolvedSkill], selection: SkillSelection) -> Diagnosed<[ResolvedSkill]> {
        guard case .skills(let names) = selection else {
            return Diagnosed(value: skills)
        }
        return filtered(skills, keepingNames: names, noun: .skill, nameOf: \.name)
    }

    /// Keeps the items that a list of names names.
    ///
    /// - Parameters:
    ///   - items: The items, in order.
    ///   - names: The selected names.
    ///   - noun: What a name names, for the text of a diagnostic.
    ///   - nameOf: The name of an item.
    /// - Returns: The named items, in order. Each name that no item has gives
    ///   one warning.
    func filtered<Item>(
        _ items: [Item], keepingNames names: [String], noun: SelectionNoun, nameOf: (Item) -> String
    ) -> Diagnosed<[Item]> {
        let wanted = Set(names)
        let known = Set(items.map(nameOf))
        return Diagnosed(
            value: items.filter { wanted.contains(nameOf($0)) },
            diagnostics: names.filter { !known.contains($0) }.map { name in
                diagnostic(.warning, saying: #"The selected \#(noun.rawValue) "\#(name)" is not in the marketplace."#)
            })
    }

    // MARK: - Shared steps

    /// Keeps one skill for each name.
    ///
    /// - Parameters:
    ///   - skills: The skills, in order.
    ///   - winner: Which skill wins when two skills have the same name.
    /// - Returns: The winning skills, in order. Each losing skill gives one
    ///   warning.
    func deduplicated(_ skills: [ResolvedSkill], winner: DuplicateWinner) -> Diagnosed<[ResolvedSkill]> {
        let winners = Dictionary(skills.indices.map { (skills[$0].name, $0) }) { first, later in
            winner == .first ? first : later
        }
        return Diagnosed(
            value: skills.indices.filter { winners[skills[$0].name] == $0 }.map { skills[$0] },
            diagnostics: skills.indices.compactMap { index in
                guard let kept = winners[skills[index].name], kept != index else {
                    return nil
                }
                return duplicateDiagnostic(loser: skills[index], winner: skills[kept])
            })
    }

    /// Lists one folder of the tree.
    ///
    /// - Parameter folder: The folder path.
    /// - Returns: The items, or no item and one error when the list fails.
    func listing(ofFolder folder: String) -> Diagnosed<[CatalogTreeEntry]> {
        do {
            return try Diagnosed(value: source.entries(inDirectory: folder))
        } catch {
            return Diagnosed(value: [], diagnostics: [readFailure(atPath: folder, error: error)])
        }
    }

    /// Tells whether a folder holds a `SKILL.md` file.
    ///
    /// - Parameter path: The folder path.
    /// - Returns: `true` when the folder has a regular file named `SKILL.md`.
    /// - Throws: The error of the folder list.
    func hasSkillFile(inFolder path: String) throws -> Bool {
        try source.entries(inDirectory: path).contains(where: Self.isSkillFile)
    }

    /// Tells whether an item is the `SKILL.md` file of its folder.
    ///
    /// - Parameter entry: The item.
    /// - Returns: `true` for a regular file named `SKILL.md`. A symbolic link
    ///   with that name is not a skill file.
    static func isSkillFile(_ entry: CatalogTreeEntry) -> Bool {
        guard entry.name == SkillDiscovery.skillFileName, case .file = entry.kind else {
            return false
        }
        return true
    }

    /// Tells whether the resolver reads into an item as a folder.
    ///
    /// - Parameter entry: The item.
    /// - Returns: `true` for a real folder whose name discovery does not
    ///   skip. A symbolic link and a submodule are never read.
    static func isSubfolder(_ entry: CatalogTreeEntry) -> Bool {
        guard !SkillDiscovery.excludedDirectoryNames.contains(entry.name) else {
            return false
        }
        switch entry.kind {
        case .directory:
            return true
        case .file, .symlink, .submodule:
            return false
        }
    }

    // MARK: - Diagnostics

    /// Makes a diagnostic about this marketplace.
    ///
    /// - Parameters:
    ///   - severity: How serious the diagnostic is.
    ///   - message: The text of the diagnostic.
    /// - Returns: The diagnostic, with ``marketplaceID``.
    func diagnostic(_ severity: MarketplaceDiagnostic.Severity, saying message: String) -> MarketplaceDiagnostic {
        MarketplaceDiagnostic(severity: severity, marketplaceID: marketplaceID, message: message)
    }

    /// Makes the error for a path that the source cannot read.
    ///
    /// - Parameters:
    ///   - path: The path in the tree.
    ///   - error: The error of the source.
    /// - Returns: An error diagnostic.
    func readFailure(atPath path: String, error: any Error) -> MarketplaceDiagnostic {
        diagnostic(.error, saying: #"The resolver cannot read "\#(CatalogPath.display(path))": \#(error)"#)
    }

    /// Makes the warning for a plugin with a remote source.
    ///
    /// - Parameters:
    ///   - plugin: The name of the plugin.
    ///   - remote: The source object of the plugin.
    /// - Returns: A warning that names the plugin and its source.
    func remoteSourceDiagnostic(plugin: String, source remote: MarketplaceCatalog.RemotePluginSource) -> MarketplaceDiagnostic {
        let location = (remote.url ?? remote.repo).map { " \($0)" } ?? ""
        let message =
            #"The plugin "\#(plugin)" has a remote source (\#(remote.kind)\#(location)). The resolver reads only relative plugin sources, so it skips this plugin."#
        return diagnostic(.warning, saying: message)
    }

    /// Makes the warning for a skill that loses to a skill with the same
    /// name.
    ///
    /// - Parameters:
    ///   - loser: The skill that the resolver does not use.
    ///   - winner: The skill that the resolver uses.
    /// - Returns: A warning that names the two skill folders.
    func duplicateDiagnostic(loser: ResolvedSkill, winner: ResolvedSkill) -> MarketplaceDiagnostic {
        let message =
            #"Two skills have the name "\#(winner.name)": \#(Self.described(loser)) and \#(Self.described(winner)). The resolver uses "\#(CatalogPath.display(winner.path))"."#
        return diagnostic(.warning, saying: message)
    }

    /// Describes a skill for the text of a diagnostic.
    ///
    /// - Parameter skill: The skill.
    /// - Returns: The quoted folder path, and the plugin when there is one.
    static func described(_ skill: ResolvedSkill) -> String {
        let folder = #""\#(CatalogPath.display(skill.path))""#
        return skill.plugin.map { #"\#(folder) (plugin "\#($0)")"# } ?? folder
    }
}

/// The path rules of a ``CatalogFileSource`` tree: relative, separated by `/`,
/// and the empty path is the root.
internal enum CatalogPath {
    /// The separator of path components.
    static let separator: Character = "/"

    /// The component that names the current folder.
    private static let currentFolder = "."

    /// The text that shows the root folder in a diagnostic.
    private static let rootDisplay = "."

    /// Normalizes a relative path from a catalog.
    ///
    /// ``PathConfinement`` decides which paths are relative, so the rule is
    /// the same rule as for the resource operations.
    ///
    /// - Parameter path: The path, for example `./skills/tdd`.
    /// - Returns: The path with no `.` component and no empty component, or
    ///   `nil` when the path is empty, absolute, starts with `~`, or has a
    ///   `..` component. The path `./` gives the empty path: the root.
    static func normalized(_ path: String) -> String? {
        guard PathConfinement.isWellFormedRelativePath(path) else {
            return nil
        }
        return path.split(separator: separator).filter { $0 != currentFolder }.joined(separator: String(separator))
    }

    /// Resolves a relative path from a catalog against a folder of the tree.
    ///
    /// - Parameters:
    ///   - relativePath: The path, as the catalog writes it.
    ///   - folder: The normalized folder that the path is relative to.
    /// - Returns: The normalized path in the tree, or `nil` when
    ///   ``normalized(_:)`` refuses `relativePath`.
    static func resolved(_ relativePath: String, inFolder folder: String) -> String? {
        normalized(relativePath).map { $0.isEmpty ? folder : child($0, of: folder) }
    }

    /// Adds one or more components to a folder path.
    ///
    /// - Parameters:
    ///   - name: The normalized components to add.
    ///   - folder: The normalized folder path. The empty path is the root.
    /// - Returns: The path of the child.
    static func child(_ name: String, of folder: String) -> String {
        folder.isEmpty ? name : folder + String(separator) + name
    }

    /// Gives the last component of a path.
    ///
    /// - Parameter path: The normalized path.
    /// - Returns: The last component, or `nil` for the root.
    static func lastComponent(of path: String) -> String? {
        path.split(separator: separator).last.map(String.init)
    }

    /// Tells whether a name is one folder name.
    ///
    /// - Parameter name: The name.
    /// - Returns: `true` when the name is a normalized path with one
    ///   component.
    static func isSingleComponent(_ name: String) -> Bool {
        normalized(name) == name && !name.contains(separator)
    }

    /// Shows a path in the text of a diagnostic.
    ///
    /// - Parameter path: The normalized path.
    /// - Returns: The path, or `.` for the root.
    static func display(_ path: String) -> String {
        path.isEmpty ? rootDisplay : path
    }
}
