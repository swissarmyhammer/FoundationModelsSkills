/// What one run of the `marketplace` command group gave
/// (marketplace.md §9.2).
///
/// The run gives the text back instead of printing it, in the same shape as
/// `OperationsCLI.CLIResult`, which a host cannot make itself. Thus a test
/// reads the text of each command, and the host decides where each line goes.
public struct MarketplaceCLIResult: Sendable, Equatable {
    /// The text to write: the output of the subcommand, or the help, the
    /// usage, or the error text of ArgumentParser.
    ///
    /// A host writes this text to standard error when ``exitCode`` is not
    /// zero, and to standard output when it is zero.
    public let output: String

    /// The exit code that a real executable gives back. It is zero for a run
    /// that worked.
    public let exitCode: Int32

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - output: The text to write.
    ///   - exitCode: The exit code of the run.
    public init(output: String, exitCode: Int32) {
        self.output = output
        self.exitCode = exitCode
    }
}
