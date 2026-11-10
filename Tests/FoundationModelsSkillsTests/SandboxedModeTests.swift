import Darwin
import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Operations
import Synchronization
import Testing

@testable import FoundationModelsSkills

/// Tests for the `skills` tool in the `ToolMode.sandboxed` mode.
///
/// In this mode the tool starts no process. It does not register `run script`,
/// the description and the files text of `use skill` do not name it, and the
/// shell injection of a body leaves each injection site as it is.
///
/// The fixture skill has a script, an inline `` !`command` `` and a fenced
/// ` ```! ` block. Each command writes a marker file when it runs. Thus a
/// marker file that exists after the calls shows that a command ran. Each
/// command then waits until a release file exists, thus a command that runs
/// stays alive until `ProcessRegistryWatch` sees its pid.
struct SandboxedModeTests {
    // MARK: - Constants

    /// The id of the fixture skill.
    fileprivate static let skillID = "sandbox-fixture"

    /// The id of the skill that `add skill` writes.
    fileprivate static let addedSkillID = "sandbox-added"

    /// The path of the script of the fixture skill.
    fileprivate static let scriptPath = "scripts/run.sh"

    /// The op string of `run script`.
    private static let runScriptOp = "run script"

    /// The first words of the line of the files text that names `run script`.
    private static let runInstructionPrefix = "To run a script"

    /// The name of the `op` field of the fused schema.
    private static let opFieldName = "op"

    /// Matches a `mode` parameter that has a default value.
    ///
    /// Each `\s*` also matches a line break, thus the pattern finds a default
    /// with any space around `:` and `=`, and a default on the next line.
    /// The optional `?` or `!` after the type finds a default on an optional
    /// `ToolMode` too.
    private static var defaultModePattern: Regex<Substring> {
        #/mode\s*:\s*ToolMode[?!]?\s*=/#
    }

    /// The source directory of the library, relative to the package root.
    private static let librarySourcesPath = "Sources/FoundationModelsSkills"

    // MARK: - Schema and description

    @Test func theSchemaHasNoRunScriptOp() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let tool = try fixture.makeTool()

        #expect(try !Self.opNames(in: tool.parameters).contains(Self.runScriptOp))
    }

    @Test func theDescriptionDoesNotNameRunScript() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let tool = try fixture.makeTool()

        #expect(!tool.description.contains(Self.runScriptOp))
    }

    // MARK: - use skill

    @Test func useSkillLeavesTheInlineInjectionUnchanged() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let answer = try await fixture.makeTool().call(arguments: fixture.useArguments())

        #expect(answer.contains(fixture.inlineInjection))
    }

    @Test func useSkillLeavesTheFencedInjectionUnchanged() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let answer = try await fixture.makeTool().call(arguments: fixture.useArguments())

        #expect(answer.contains(fixture.fencedInjection))
    }

    @Test func theFilesTextOfUseSkillHasNoRunLine() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let answer = try await fixture.makeTool().call(arguments: fixture.useArguments())

        #expect(!answer.contains(Self.runInstructionPrefix))
    }

    // MARK: - No process

    @Test func noOpWritesAMarkerFile() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        _ = try await fixture.callEveryOp()

        #expect(fixture.existingMarkers().isEmpty)
    }

    @Test func noOpLeavesNoPidOfTheFixtureInTheProcessRegistry() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let pids = try await fixture.callEveryOp()

        #expect(pids.isEmpty)
    }

    // MARK: - run script given a sandboxed context directly

    @Test func runScriptGivenASandboxedContextDirectlyGivesACorrective() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let run = try await fixture.runScriptDirectly()

        #expect(ResourceTestSupport.correctiveMessage(of: run.output) != nil)
    }

    @Test func runScriptGivenASandboxedContextDirectlyWritesNoMarkerFile() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        _ = try await fixture.runScriptDirectly()

        #expect(fixture.existingMarkers().isEmpty)
    }

    @Test func runScriptGivenASandboxedContextDirectlyLeavesNoPidInTheProcessRegistry() async throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        let run = try await fixture.runScriptDirectly()

        #expect(run.pids.isEmpty)
    }

    // MARK: - Composition

    @Test func theOpenModeInASandboxedProcessFailsAtComposition() throws {
        let fixture = try SandboxFixture(mode: .open)
        defer { fixture.remove() }

        #expect(throws: ToolModeError.openModeInSandbox) {
            try fixture.makeContext(probe: .fixed(true))
        }
    }

    @Test func theSandboxedModeInASandboxedProcessComposes() throws {
        let fixture = try SandboxFixture()
        defer { fixture.remove() }

        #expect(throws: Never.self) {
            try fixture.makeContext(probe: .fixed(true))
        }
    }

    @Test func aContextModeThatIsNotTheRegistryModeFailsAtComposition() throws {
        let fixture = try SandboxFixture(mode: .open)
        defer { fixture.remove() }

        #expect(throws: SkillsToolContext.ModeMismatchError(registryMode: .open, contextMode: .sandboxed)) {
            try fixture.makeContext(contextMode: .sandboxed)
        }
    }

    // MARK: - No default mode

    @Test func theScanFlagsACompactDefault() {
        #expect(Self.modeDefaultLines(in: "init(mode: ToolMode=.open)") == [1])
    }

    @Test func theScanFlagsADefaultWithSpaceBeforeTheColon() {
        #expect(Self.modeDefaultLines(in: "init(mode :ToolMode = .open)") == [1])
    }

    @Test func theScanFlagsADefaultOnTheNextLine() {
        #expect(Self.modeDefaultLines(in: "init(\n    mode: ToolMode\n        = .open)") == [2])
    }

    @Test func theScanFlagsADefaultOnAnOptionalMode() {
        #expect(Self.modeDefaultLines(in: "init(mode: ToolMode? = nil)") == [1])
    }

    @Test func theScanFlagsADefaultOnAnImplicitlyUnwrappedMode() {
        #expect(Self.modeDefaultLines(in: "init(mode: ToolMode! = .open)") == [1])
    }

    @Test func theScanDoesNotFlagAnOptionalModeWithNoDefault() {
        #expect(Self.modeDefaultLines(in: "init(mode: ToolMode?, probe: SandboxProbe = .live)").isEmpty)
    }

    @Test func theScanDoesNotFlagAModeWithNoDefault() {
        #expect(Self.modeDefaultLines(in: "init(mode: ToolMode, probe: SandboxProbe = .live)").isEmpty)
    }

    @Test func noLineUnderTheLibrarySourcesGivesModeADefault() throws {
        let offenders = try SwiftSourceScan.reportedLines(
            inDirectory: Self.librarySourcesPath, matchingPattern: Self.defaultModePattern)

        #expect(
            offenders.isEmpty,
            """
            No line under \(Self.librarySourcesPath)/ may give `mode` a default value. Each host \
            states its mode; found: \(offenders.joined(separator: ", "))
            """)
    }

    // MARK: - Helpers

    /// Finds each `mode` parameter of `text` that has a default value.
    ///
    /// - Parameter text: The source text to read.
    /// - Returns: The number of the line where each such parameter starts.
    ///   The first line is 1.
    private static func modeDefaultLines(in text: String) -> [Int] {
        SwiftSourceScan.lineNumbers(in: text, ofMatchesOf: defaultModePattern)
    }

    /// Reads the values of the `op` enum of the fused schema.
    ///
    /// - Parameter schema: The fused schema of the tool.
    /// - Returns: Each op string of the schema.
    /// - Throws: An encode error, or a `#require` failure when the schema has
    ///   no `op` enum.
    private static func opNames(in schema: GenerationSchema) throws -> [String] {
        let data = try JSONEncoder().encode(schema)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let opProperty = try #require(properties[opFieldName] as? [String: Any])
        return try #require(opProperty["enum"] as? [String])
    }
}

/// A user layer and a project layer in one temporary folder, the fixture skill
/// in the project layer, and a folder for the marker files.
private struct SandboxFixture {
    /// The source of each layer, lowest precedence first.
    private static let sources: [DotfolderStack.Source] = [.user, .project]

    /// The name of each marker file: one for each command of the fixture.
    private static let markerNames = ["inline", "fenced", "script", "added", "edited"]

    /// The folder that holds the layers and the markers, as a real path with
    /// no symbolic link, the same path that a process reads as its working
    /// directory.
    let root: URL

    /// The file whose existence lets each command of the fixture end.
    var releaseFile: URL {
        root.appendingPathComponent("release")
    }

    /// The registry over the layers.
    let registry: SkillsRegistry

    /// The inline injection of the body, as the body holds it.
    let inlineInjection: String

    /// The fenced injection of the body, as the body holds it.
    let fencedInjection: String

    /// Makes the folders, writes the fixture skill, and builds the registry.
    ///
    /// - Parameter mode: The mode of the registry. Defaults to `.sandboxed`.
    /// - Throws: Whatever a file write throws.
    init(mode: ToolMode = .sandboxed) throws {
        let root = try Self.realPath(of: HotReloadTestSupport.makeTempDirectory())
        self.root = root
        let layerRoots = Self.sources.indices.map { root.appendingPathComponent("layer-\($0)", isDirectory: true) }
        inlineInjection = "!`\(Self.command(marker: "inline", in: root))`"
        fencedInjection = "```!\n\(Self.command(marker: "fenced", in: root))\n```"
        try Self.writeFixtureSkill(
            in: layerRoots[1], body: "Inline: \(inlineInjection)\n\n\(fencedInjection)\n",
            script: "#!/bin/sh\n\(Self.command(marker: "script", in: root))\n")
        registry = SkillsRegistry(
            layers: zip(Self.sources, layerRoots).map { DotfolderStack.Layer(source: $0, root: $1) }, mode: mode)
    }

    /// Removes the fixture folder.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Builds the context over the registry.
    ///
    /// - Parameters:
    ///   - contextMode: The mode of the context, or `nil` for the mode of the
    ///     registry.
    ///   - probe: The sandbox probe. Defaults to a process that is not
    ///     sandboxed.
    /// - Returns: The context.
    /// - Throws: Whatever `SkillsToolContext.init` throws.
    @discardableResult
    func makeContext(contextMode: ToolMode? = nil, probe: SandboxProbe = .fixed(false)) throws -> SkillsToolContext {
        let searcher = MetadataSearcher(items: registry.metadata().filter(\.isModelVisible))
        return try SkillsToolContext(
            registry: registry, searchAgent: SkillSearchAgent(searcher: searcher),
            mode: contextMode ?? registry.mode, sandboxProbe: probe)
    }

    /// Builds the `skills` tool over the registry.
    ///
    /// - Returns: The tool.
    /// - Throws: Whatever `makeContext()` or `SkillsTool.make(context:)`
    ///   throws.
    func makeTool() throws -> SkillsCatalogTool {
        try SkillsTool.make(context: makeContext())
    }

    /// Calls each op of the tool one time, and the `run script` op too,
    /// under a `ProcessRegistryWatch`.
    ///
    /// The `add skill` and `edit skill` calls write a body with an injection,
    /// thus a write that renders the body would start the command. The watch
    /// lets each command that starts end, thus a call never waits for a
    /// command.
    ///
    /// - Returns: Each pid of the fixture that the watch saw.
    /// - Throws: Whatever `SkillsCatalogTool.call(arguments:)` throws.
    func callEveryOp() async throws -> Set<pid_t> {
        let tool = try makeTool()
        return try await makeWatch().pidsSeen {
            for arguments in everyOpArguments() {
                _ = try await tool.call(arguments: arguments)
            }
        }
    }

    /// Runs `RunScript` of the fixture script against the context directly,
    /// with no tool, under a `ProcessRegistryWatch`.
    ///
    /// A host can dispatch `RunScript` with no `skills` tool, thus the
    /// operation itself must start no process in the sandboxed mode.
    ///
    /// - Returns: The outcome of the operation, and each pid of the fixture
    ///   that the watch saw.
    /// - Throws: Whatever `makeContext()` or `RunScript.execute(in:)` throws.
    func runScriptDirectly() async throws -> (output: RunScriptOutput, pids: Set<pid_t>) {
        let context = try makeContext()
        let operation = RunScript(id: SandboxedModeTests.skillID, path: SandboxedModeTests.scriptPath)
        var output: RunScriptOutput?
        let pids = try await makeWatch().pidsSeen {
            output = try await operation.execute(in: context)
        }
        return (try #require(output), pids)
    }

    /// Builds a watch over the fixture folder.
    ///
    /// - Returns: The watch.
    private func makeWatch() -> ProcessRegistryWatch {
        ProcessRegistryWatch(directory: root, releaseFile: releaseFile)
    }

    /// The marker files that exist.
    ///
    /// - Returns: The name of each marker file that exists.
    func existingMarkers() -> [String] {
        Self.markerNames.filter { FileManager.default.fileExists(atPath: Self.markerPath(named: $0, in: root)) }
    }

    /// The payload of a `use skill` call of the fixture skill.
    func useArguments() -> GeneratedContent {
        GeneratedContent(properties: ["op": "use skill", "id": SandboxedModeTests.skillID])
    }

    /// The payload of a `run script` call of the script of the fixture skill.
    func runScriptArguments() -> GeneratedContent {
        GeneratedContent(properties: [
            "op": "run script", "id": SandboxedModeTests.skillID, "path": SandboxedModeTests.scriptPath,
        ])
    }

    /// The payload of each op of the tool, in the order of the schema, with
    /// the `run script` payload after `read resource`.
    ///
    /// - Returns: The payloads.
    private func everyOpArguments() -> [GeneratedContent] {
        let id = SandboxedModeTests.skillID
        let addedID = SandboxedModeTests.addedSkillID
        return [
            GeneratedContent(properties: ["op": "search skill", "query": id]),
            GeneratedContent(properties: ["op": "list skill"]),
            useArguments(),
            GeneratedContent(properties: ["op": "list resource", "id": id]),
            GeneratedContent(properties: ["op": "read resource", "id": id, "path": SandboxedModeTests.scriptPath]),
            runScriptArguments(),
            GeneratedContent(properties: [
                "op": "add skill", "id": addedID, "content": skillMarkdown(id: addedID, marker: "added"),
            ]),
            GeneratedContent(properties: [
                "op": "edit skill", "id": addedID, "content": skillMarkdown(id: addedID, marker: "edited"),
            ]),
            GeneratedContent(properties: ["op": "use skill", "id": addedID]),
            GeneratedContent(properties: ["op": "remove skill", "id": addedID]),
        ]
    }

    /// The text of a skill file whose body runs a command that writes a
    /// marker file.
    ///
    /// - Parameters:
    ///   - id: The skill id.
    ///   - marker: The name of the marker file.
    /// - Returns: The text of the skill file.
    private func skillMarkdown(id: String, marker: String) -> String {
        "---\nname: \(id)\ndescription: A skill that writes a marker.\n---\n"
            + "Run: !`\(Self.command(marker: marker, in: root))`\n"
    }

    /// The shell command of one site: it writes the marker file, then waits
    /// until the release file exists.
    ///
    /// - Parameters:
    ///   - marker: The name of the marker file.
    ///   - root: The fixture folder.
    /// - Returns: The command.
    private static func command(marker: String, in root: URL) -> String {
        let releasePath = root.appendingPathComponent("release").path
        return "touch \(markerPath(named: marker, in: root)); while [ ! -e \(releasePath) ]; do :; done"
    }

    /// Resolves `url` to its real path with `realpath(3)`.
    ///
    /// `URL.resolvingSymlinksInPath()` keeps the `/var` link of the temporary
    /// folder of macOS, and a process reads `/private/var` as its working
    /// directory. Thus the fixture holds the real path.
    ///
    /// - Parameter url: A folder that exists.
    /// - Returns: The real path of the folder.
    /// - Throws: `POSIXError` when `realpath` fails.
    private static func realPath(of url: URL) throws -> URL {
        guard let resolved = realpath(url.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// The path of one marker file.
    ///
    /// - Parameters:
    ///   - name: The name of the marker file.
    ///   - root: The fixture folder.
    /// - Returns: The path.
    private static func markerPath(named name: String, in root: URL) -> String {
        root.appendingPathComponent("marker-\(name)").path
    }

    /// Writes the fixture skill: the skill file, which grants each script, and
    /// the executable script.
    ///
    /// - Parameters:
    ///   - layerRoot: The root of the project layer.
    ///   - body: The body of the skill file.
    ///   - script: The text of the script.
    /// - Throws: Whatever a file write throws.
    private static func writeFixtureSkill(in layerRoot: URL, body: String, script: String) throws {
        let id = SandboxedModeTests.skillID
        try LayerFixtureSupport.writeTextFile(
            "---\nname: \(id)\ndescription: A skill with a script and shell injection.\n"
                + "allowed-tools: \"\(ResourceTestSupport.everyScriptGrant)\"\n---\n\(body)",
            at: "\(id)/SKILL.md", in: layerRoot)
        let scriptURL = try LayerFixtureSupport.writeTextFile(
            script, at: "\(id)/\(SandboxedModeTests.scriptPath)", in: layerRoot)
        try LayerFixtureSupport.makeExecutable(scriptURL)
    }
}

/// Records each pid of `ProcessRegistry.global` whose working directory is in
/// one folder, while a body runs.
///
/// Other tests run at the same time and start processes, thus the watch keeps
/// only a pid whose working directory is in `directory`. `ShellInjection` and
/// `RunScript` start each command in the folder of the skill, thus a command of
/// the fixture has its working directory in the fixture folder.
///
/// Each command of the fixture waits for `releaseFile`. When the watch sees a
/// pid of the fixture, it makes that file, thus the command ends and the body
/// goes on.
private struct ProcessRegistryWatch {
    /// The folder that a working directory must be in.
    let directory: URL

    /// The file that lets each command of the fixture end.
    let releaseFile: URL

    /// Runs `body`, and reads the registry again and again until `body` ends.
    ///
    /// - Parameter body: The calls to watch.
    /// - Returns: Each pid in the registry with its working directory in
    ///   `directory`.
    /// - Throws: Whatever `body` throws.
    func pidsSeen(during body: () async throws -> Void) async throws -> Set<pid_t> {
        let isDone = Atomic<Bool>(false)
        let prefix = directory.path
        let releasePath = releaseFile.path
        let sampler = Task.detached { () -> Set<pid_t> in
            var seen = Set<pid_t>()
            while !isDone.load(ordering: .acquiring) {
                for pid in ProcessRegistry.global.registeredPids
                where Self.workingDirectory(of: pid)?.hasPrefix(prefix) == true {
                    seen.insert(pid)
                    FileManager.default.createFile(atPath: releasePath, contents: nil)
                }
                await Task.yield()
            }
            return seen
        }
        do {
            try await body()
        } catch {
            isDone.store(true, ordering: .releasing)
            _ = await sampler.value
            throw error
        }
        isDone.store(true, ordering: .releasing)
        return await sampler.value
    }

    /// Reads the working directory of a live process.
    ///
    /// - Parameter pid: The process.
    /// - Returns: The path of the working directory, or `nil` when the process
    ///   ended or cannot be read.
    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }
}
