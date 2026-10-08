import FoundationModels
import Synchronization

// MARK: - Selection-tier model double
//
// The selection tests never use a real model. A selection tier gets a
// `ScriptedLanguageModel`: a FoundationModels `LanguageModel` that loads
// nothing and answers from a script. The tier makes real
// `LanguageModelSession`s on it. No GPU and no download.

/// One generation call that a ``ScriptedLanguageModel`` answered.
struct ScriptedModelCall: Sendable, Equatable {
    /// The text of the instructions entry of the transcript of the call, or
    /// `nil` when the session has no instructions.
    let instructions: String?

    /// The text of the prompt entries of the transcript of the call, with a
    /// blank line between two entries.
    let prompt: String
}

/// One answer in the script of a ``ScriptedLanguageModel``.
enum ScriptedAnswer: Sendable {
    /// Gives this text, for example a `Selection` as JSON.
    case text(String)

    /// Throws `ScriptedLanguageModel.ScriptedFailure`.
    case failure

    /// Throws this error.
    case error(any Error)
}

/// The script that each copy of one ``ScriptedLanguageModel`` plays, and the
/// log of the calls that it answered.
///
/// A class, because the identity of the script is the cache key of the
/// executor, and because all copies of one model share one log. A `Mutex`
/// holds the log, thus the class is `Sendable` with no unchecked claim.
final class ScriptedLanguageModelScript: Sendable {
    /// The answers, in call order.
    private let answers: [ScriptedAnswer]

    /// The calls that the model answered, in order.
    private let recordedCalls = Mutex<[ScriptedModelCall]>([])

    /// Makes a script.
    ///
    /// - Parameter answers: The answers, in call order. After the last
    ///   answer, the model gives the last answer again for each call. Thus a
    ///   script of one answer gives that answer for every call.
    init(answers: [ScriptedAnswer]) {
        precondition(!answers.isEmpty, "a script needs at least one answer")
        self.answers = answers
    }

    /// The calls that the model answered, in order.
    var calls: [ScriptedModelCall] { recordedCalls.withLock { $0 } }

    /// Adds `call` to the log and gives the answer for it.
    ///
    /// - Parameter call: The call that the model answers.
    /// - Returns: The text of the answer for this call.
    /// - Throws: `ScriptedLanguageModel.ScriptedFailure` for a `.failure`
    ///   answer, or the error of an `.error` answer.
    fileprivate func answer(_ call: ScriptedModelCall) throws -> String {
        let index = recordedCalls.withLock { calls -> Int in
            calls.append(call)
            return calls.count - 1
        }
        switch answers[min(index, answers.count - 1)] {
        case .text(let text):
            return text
        case .failure:
            throw ScriptedLanguageModel.ScriptedFailure()
        case .error(let error):
            throw error
        }
    }
}

/// A FoundationModels `LanguageModel` that loads nothing and answers each
/// generation call from a script, in order. It writes each call to the log
/// of the script first.
///
/// All copies of one model share one script, thus a test keeps the model it
/// gave to the tier and reads ``calls`` from it.
struct ScriptedLanguageModel: LanguageModel {
    /// The executor that plays the script.
    typealias Executor = ScriptedLanguageModelExecutor

    /// The error of a `.failure` answer, as a model throws when its
    /// transport fails.
    struct ScriptedFailure: Error {}

    /// The script that the model plays.
    let script: ScriptedLanguageModelScript

    /// Makes a model that plays `answers`, in call order.
    ///
    /// - Parameter answers: The answers, in call order. The last answer
    ///   repeats for each later call.
    init(answers: [ScriptedAnswer]) {
        script = ScriptedLanguageModelScript(answers: answers)
    }

    /// Makes a model that gives `texts`, in call order.
    ///
    /// - Parameter texts: The text of each answer, in call order. The last
    ///   text repeats for each later call.
    init(_ texts: String...) {
        self.init(answers: texts.map(ScriptedAnswer.text))
    }

    /// Makes a model whose every call throws.
    static var failing: ScriptedLanguageModel {
        ScriptedLanguageModel(answers: [.failure])
    }

    /// Guided generation, thus a session can ask for a `Generable` type.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    /// The cache key of the executor: the identity of the script.
    var executorConfiguration: ScriptedLanguageModelExecutor.Configuration {
        ScriptedLanguageModelExecutor.Configuration(script: ObjectIdentifier(script))
    }

    /// The calls that the model answered, in order.
    var calls: [ScriptedModelCall] { script.calls }
}

/// The executor of ``ScriptedLanguageModel``.
struct ScriptedLanguageModelExecutor: LanguageModelExecutor {
    /// The cache key that the SDK makes and uses again for the executor.
    struct Configuration: Sendable, Hashable {
        /// The identity of the script that the model plays.
        let script: ObjectIdentifier
    }

    /// The model that this executor runs for.
    typealias Model = ScriptedLanguageModel

    /// The token count of the one emitted fragment. The double counts no
    /// tokens.
    private static let emittedTokenCount = 1

    /// The text between the texts of two prompt entries in
    /// `ScriptedModelCall.prompt`.
    private static let promptSeparator = "\n\n"

    /// Makes an executor. The executor reads nothing from the configuration:
    /// the script comes with the model on each call.
    ///
    /// - Parameter configuration: The cache key.
    /// - Throws: Never. `throws` comes from the `LanguageModelExecutor`
    ///   requirement.
    init(configuration: Configuration) throws {}

    /// Writes the call to the log of the script, and emits the answer of the
    /// script.
    ///
    /// - Parameters:
    ///   - request: The generation request with the full transcript.
    ///   - model: The model with the script.
    ///   - channel: The channel that the answer goes into.
    /// - Throws: The error of the script for this call.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let call = ScriptedModelCall(
            instructions: Self.instructionsText(in: request.transcript),
            prompt: Self.promptTexts(in: request.transcript).joined(separator: Self.promptSeparator))
        let text = try model.script.answer(call)
        await channel.send(.response(action: .appendText(text, tokenCount: Self.emittedTokenCount)))
    }

    /// The text of the first instructions entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript of a generation call.
    /// - Returns: The text of the entry, or `nil` when there is none.
    private static func instructionsText(in transcript: Transcript) -> String? {
        transcript.lazy.compactMap { entry -> String? in
            guard case .instructions(let instructions) = entry else { return nil }
            return text(of: instructions.segments)
        }.first
    }

    /// The text of each prompt entry of `transcript`, in order.
    ///
    /// - Parameter transcript: The transcript of a generation call.
    /// - Returns: The text of each prompt entry.
    private static func promptTexts(in transcript: Transcript) -> [String] {
        transcript.compactMap { entry in
            guard case .prompt(let prompt) = entry else { return nil }
            return text(of: prompt.segments)
        }
    }

    /// The text of the text segments of `segments`, joined.
    ///
    /// - Parameter segments: The segments of a transcript entry.
    /// - Returns: The joined text.
    private static func text(of segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            guard case .text(let text) = segment else { return nil }
            return text.content
        }.joined()
    }
}
