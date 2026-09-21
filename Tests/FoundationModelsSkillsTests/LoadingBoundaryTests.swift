import Testing

/// Guards the loading boundary of this package (plan.md §3): the raw work of
/// loading a skill lives in `FoundationModelsExtras`, and this package keeps
/// only the work of the skill schema.
///
/// The rule, in one table:
///
/// | the work | where it lives |
/// |---|---|
/// | fetch a marketplace and materialize a layer root | Extras, `Marketplace` |
/// | find a file in the combined view of the layers | Extras, `DotfolderStack` |
/// | say that a layer root changed | Extras, `DotfolderWatcher` |
/// | split the frontmatter from the body | Extras, `FrontmatterDocumentStack` |
/// | render with Stencil, with the trust of the layer | Extras, `StenciledDotfolderStack` |
/// | everything above: the skill schema | here |
///
/// This suite is the one guard of that whole boundary. It gives
/// `SwiftSourceScan` a test of a line, and that reader walks every Swift file
/// under `Sources/FoundationModelsSkills/`. The walk reads the full text of
/// each file, comments included, thus a stale doc comment fails it as well as
/// a line of code.
///
/// ``rules`` is the table, and each row states one rule: the text that no
/// line may hold, why the boundary forbids it, and the files that may hold it
/// all the same. Four suites held this table before -- `NoFrontmatterSplit`,
/// `NoResourceFileRead`, `NoFileSystemWatch` and `StencilLivesInExtras` --
/// and each one asked the same question of a line. They are one table now, so
/// a reader finds each forbidden name in one place.
///
/// Three guards stand beside this one, and none of them reads a plain name:
/// `NoGitProcessTests` reads a line that starts a process AND names `git`,
/// `NoStandardOutWriteTests` reads a call with a word boundary before its
/// name, and `NoDotfolderStackExtensionTests` reads an extension head with
/// the character after it. A name table cannot express any of the three.
///
/// `ScriptGate` is not in the table, and it stays where it is: its `fnmatch`
/// call matches the path pattern of an `allowed-tools` grant, and it opens no
/// file.
@Suite("Loading boundary")
struct LoadingBoundaryTests {
    /// The directory of this package's own source, relative to the package
    /// root.
    private static let sourcesPath = "Sources/FoundationModelsSkills"

    /// The one line writer of the console, which names `FileHandle` for the
    /// two standard streams and loads nothing.
    private static let standardStreamFile = "\(sourcesPath)/CLI/StandardStream.swift"

    /// The re-export file, whose comment tells a host which names of Extras
    /// one `import FoundationModelsSkills` gives it.
    private static let seamReexportsFile = "\(sourcesPath)/SeamReexports.swift"

    /// One rule of the loading boundary.
    struct Rule: Sendable, CustomStringConvertible {
        /// The character that stands between the path of a reported line and
        /// the number of that line.
        private static let lineNumberSeparator = ":"

        /// The text that no line of a guarded file may hold.
        let name: String

        /// Why the loading boundary forbids the name.
        let reason: String

        /// The files that may hold the name all the same, by path relative to
        /// the package root.
        let exemptFiles: [String]

        /// The name of the rule, which names the test case in a report.
        var description: String { name }

        /// Tells whether `line` breaks this rule.
        ///
        /// - Parameter line: The line to read.
        /// - Returns: `true` when the line holds ``name``.
        func isBroken(by line: String) -> Bool {
            line.contains(name)
        }

        /// Tells whether an exempt file holds `reportedLine`.
        ///
        /// - Parameter reportedLine: One reported line, in the form
        ///   `<path>:<line number>`.
        /// - Returns: `true` when ``exemptFiles`` holds the path of the line.
        func exempts(_ reportedLine: String) -> Bool {
            exemptFiles.contains { reportedLine.hasPrefix($0 + Self.lineNumberSeparator) }
        }
    }

    /// The rule of the byte reader of Foundation, which the line tests below
    /// read because it is the one rule of the table with an exemption.
    private static let fileHandleRule = Rule(
        name: "FileHandle",
        reason: "the stack of Extras reads the bytes of a file",
        exemptFiles: [standardStreamFile])

    /// Every rule of the loading boundary, with the reason of each one.
    static let rules: [Rule] = [
        Rule(
            name: "FileManager",
            reason: "the stack of Extras opens each directory and each file of a skill",
            exemptFiles: []),
        fileHandleRule,
        Rule(
            name: "String(contentsOf",
            reason: "FrontmatterDocumentStack reads the text of each SKILL.md",
            exemptFiles: []),
        Rule(
            name: "Data(contentsOf",
            reason: "the overlay asks the stack for a byte range, thus it loads no whole file",
            exemptFiles: []),
        Rule(
            name: "resourceValues",
            reason: "the stack of Extras reads the size and the execute bit of a file",
            exemptFiles: []),
        Rule(
            name: "contentsOfDirectory",
            reason: "the stack of Extras gives the union of the paths of the layers",
            exemptFiles: []),
        Rule(
            name: "DispatchSource",
            reason: "DotfolderWatcher of Extras holds the watch of each layer root",
            exemptFiles: []),
        Rule(
            name: "O_EVTONLY",
            reason: "DotfolderWatcher of Extras opens the descriptor of a watch",
            exemptFiles: []),
        Rule(
            name: "SkillWatcher",
            reason: "the local watcher is retired; DotfolderWatcher of Extras replaced it",
            exemptFiles: []),
        Rule(
            name: "resolvingSymlinksInPath",
            reason: "the stack of Extras confines each path and resolves each link",
            exemptFiles: []),
        Rule(
            name: "FrontmatterDocument.split",
            reason: "FrontmatterDocumentStack of Extras splits the frontmatter from the body",
            exemptFiles: []),
        Rule(
            name: "TemplateEngine",
            reason: "StenciledDotfolderStack of Extras runs each render",
            exemptFiles: [seamReexportsFile]),
        Rule(
            name: "TemplateContext",
            reason: "the stenciled stack of Extras builds the context of a render",
            exemptFiles: []),
        Rule(
            name: "TemplateValue",
            reason: "the stenciled stack of Extras carries each quarantined span as a value",
            exemptFiles: []),
        Rule(
            name: "WellKnownValues",
            reason: "the stenciled stack of Extras holds the lowest step of the variable ladder",
            exemptFiles: []),
        Rule(
            name: "import Stencil",
            reason: "Extras holds the one dependency on Stencil",
            exemptFiles: []),
        Rule(
            name: "import libgit2",
            reason: "the Marketplace module of Extras holds the one dependency on libgit2",
            exemptFiles: []),
    ]

    @Test(arguments: LoadingBoundaryTests.rules)
    func noFileOfThisPackageBreaksTheRule(rule: Rule) throws {
        let offenders = try Self.reportedLines(of: rule).filter { !rule.exempts($0) }

        #expect(
            offenders.isEmpty,
            """
            No file under \(Self.sourcesPath)/ may name \(rule.name): \(rule.reason). \
            Found: \(offenders.joined(separator: ", "))
            """)
    }

    @Test(arguments: LoadingBoundaryTests.rules)
    func eachExemptFileOfTheRuleNamesIt(rule: Rule) throws {
        let reported = try Self.reportedLines(of: rule)

        for exemptFile in rule.exemptFiles {
            #expect(
                reported.contains { rule.exempts($0) && $0.hasPrefix(exemptFile) },
                """
                \(exemptFile) is exempt from \(rule.name), and it names \(rule.name) nowhere. \
                An exemption that exempts nothing is dead; take the row out of the table.
                """)
        }
    }

    @Test func aLineOfAnExemptFileIsNotReported() {
        #expect(Self.fileHandleRule.exempts("\(Self.standardStreamFile):32"))
    }

    @Test func aLineOfAnotherFileIsReported() {
        #expect(!Self.fileHandleRule.exempts("\(Self.sourcesPath)/Resources/ReadResource.swift:32"))
    }

    @Test func aLineOfAFileWhoseNameOnlyOpensAnExemptNameIsReported() {
        #expect(!Self.fileHandleRule.exempts("\(Self.standardStreamFile)Extra.swift:32"))
    }

    @Test func aLineThatNamesTheRuleIsBrokenByIt() {
        #expect(Self.fileHandleRule.isBroken(by: "case .output: FileHandle.standardOutput"))
    }

    @Test func aLineThatNamesNoRuleIsNotBrokenByIt() {
        #expect(!Self.fileHandleRule.isBroken(by: "StandardStream.output.write(line: text)"))
    }

    /// Finds each line of this package's source that breaks `rule`, the
    /// exempt files included.
    ///
    /// - Parameter rule: The rule to read each line against.
    /// - Returns: One text for each reported line, in the form
    ///   `<path>:<line number>`.
    /// - Throws: The error of the walk, when a file is unreadable or when the
    ///   directory holds no Swift file.
    private static func reportedLines(of rule: Rule) throws -> [String] {
        try SwiftSourceScan.reportedLines(inDirectory: sourcesPath, matching: rule.isBroken)
    }
}
