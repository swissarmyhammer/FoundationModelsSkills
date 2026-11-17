import Operations
import Testing

@testable import FoundationModelsSkills

/// Tests for the errors that `PlainTextOperations` expects when its matcher
/// resolves a payload.
///
/// An error that means "no operation resolved" is expected: the fused tool
/// answers the payload with a corrective, which is plain text already. Each
/// other error is not expected, and `PlainTextOperations` makes it visible.
struct PlainTextOperationsErrorTests {
    // MARK: - Fixtures

    /// The op strings that an `OperationError` case lists. The value does not
    /// change the classification.
    private static let listedOps = ["use skill"]

    /// An error that is not an `OperationError`.
    private struct UnrelatedError: Error {}

    /// Each error that means "no operation resolved".
    private static let resolutionFailures: [any Error] = [
        OperationError.unknownOperation(valid: listedOps),
        OperationError.unnamedOperation(fitting: listedOps, valid: listedOps),
        OperationError.missingRequired(listedOps),
    ]

    /// Each error that a resolved operation gives, or that is not an
    /// `OperationError`.
    private static let unexpectedErrors: [any Error] = [
        OperationError.decodingFailed,
        OperationError.encodingFailed,
        OperationError.executionFailed(cause: UnrelatedError()),
        UnrelatedError(),
        CancellationError(),
    ]

    // MARK: - Classification

    @Test(arguments: resolutionFailures.indices)
    func anErrorThatResolvesNoOperationIsAResolutionFailure(index: Int) {
        #expect(PlainTextOperations.isResolutionFailure(Self.resolutionFailures[index]))
    }

    @Test(arguments: unexpectedErrors.indices)
    func anyOtherErrorIsNotAResolutionFailure(index: Int) {
        #expect(!PlainTextOperations.isResolutionFailure(Self.unexpectedErrors[index]))
    }
}
