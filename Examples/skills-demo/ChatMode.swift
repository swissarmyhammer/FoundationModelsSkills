import Foundation
import FoundationModels
import FoundationModelsSkills
import Operations

/// Drives `skills-demo --chat`'s scripted, manual-run live-model validation:
/// a root session over the fused `skills` tool, its `search skill` -> `use
/// skill` round trip (plan.md §10, §11).
///
/// Manual-run only, never part of `swift test` for its live-model path --
/// `SkillsDemoTests` instead exercises the deterministic
/// `SKILLS_DEMO_FORCE_UNAVAILABLE` seam, which short-circuits before ever
/// touching `SystemLanguageModel`.
enum ChatMode {
    /// The environment variable key that forces the unavailable-degradation
    /// branch.
    ///
    /// Set to force that branch deterministically, regardless of this
    /// device's real Foundation Models availability -- the seam
    /// `SkillsDemoTests` exercises in CI.
    private static let forceUnavailableEnvKey = "SKILLS_DEMO_FORCE_UNAVAILABLE"

    /// The reason text for an availability shape this package doesn't
    /// recognize.
    ///
    /// Shared by `reasonText(for:)`'s own fallback and the outer
    /// `availability` switch's `@unknown default` in `run(environment:)`, so
    /// the two can never drift on its wording.
    private static let unknownReasonText = "unknown reason"

    /// One scripted prompt and the op the skills tool is expected to
    /// dispatch in response.
    private struct ScriptedPrompt: Sendable {
        /// The natural-language prompt sent to the model.
        let prompt: String

        /// The `"verb noun"` op string the model is expected to dispatch.
        let expectedOpString: String
    }

    /// The scripted prompt set: a `search skill` -> `use skill` round trip
    /// (plan.md §11).
    private static let scriptedPrompts: [ScriptedPrompt] = [
        ScriptedPrompt(
            prompt: "Search the skills library for something that helps commit my changes.",
            expectedOpString: "search skill"),
        ScriptedPrompt(prompt: "Use the commit skill with argument 'fix parser'.", expectedOpString: "use skill"),
    ]

    /// The instructions the harness's root `LanguageModelSession` runs
    /// under, alongside `registry.preloadedBodies()`.
    private static let sessionInstructions =
        "You use the skills tool to search and run skills from the local library."

    /// Runs the scripted validation, or prints a clean, deterministic
    /// unavailable message and returns without touching
    /// `SystemLanguageModel` at all.
    ///
    /// - Parameter environment: Consulted for `forceUnavailableEnvKey`.
    ///   Defaults to the real process environment.
    static func run(environment: [String: String] = ProcessInfo.processInfo.environment) async {
        guard environment[forceUnavailableEnvKey] == nil else {
            Self.printUnavailable(reasonText: "forced unavailable for testing")
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            await runValidation()
        case .unavailable(let reason):
            Self.printUnavailable(reasonText: Self.reasonText(for: reason))
        @unknown default:
            Self.printUnavailable(reasonText: Self.unknownReasonText)
        }
    }

    /// Every recognized `SystemLanguageModel.Availability.UnavailableReason`'s
    /// human-readable text.
    ///
    /// Data, not a switch: `reasonText(for:)` is a plain lookup over this
    /// table, so a future case only ever needs a new entry here, never a new
    /// control-flow branch.
    private static let reasonTexts: [SystemLanguageModel.Availability.UnavailableReason: String] = [
        .deviceNotEligible: "device not eligible",
        .appleIntelligenceNotEnabled: "Apple Intelligence not enabled",
        .modelNotReady: "model not ready",
    ]

    /// The human-readable text for `reason`.
    ///
    /// - Parameter reason: The reason to look up text for.
    /// - Returns: `reasonTexts[reason]`, or `unknownReasonText` for a case
    ///   this package doesn't yet recognize.
    private static func reasonText(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        reasonTexts[reason] ?? Self.unknownReasonText
    }

    /// Prints the clean, deterministic degradation message every unavailable
    /// path (real or forced) shares.
    ///
    /// - Parameter reasonText: The human-readable reason the model is
    ///   unavailable.
    private static func printUnavailable(reasonText: String) {
        print("Foundation Models unavailable on this device (\(reasonText)); skipping live validation.")
    }

    /// Builds the fused tool and root session over `SkillsDemoAssembly`, then
    /// evaluates every scripted prompt in turn.
    private static func runValidation() async {
        do {
            let registry = SkillsDemoAssembly.makeRegistry(watch: false)
            let tool = try await SkillsDemoAssembly.makeTool(registry: registry)
            let session = LanguageModelSession(
                tools: [tool],
                instructions: Instructions {
                    sessionInstructions
                    registry.preloadedBodies()
                })
            for scripted in scriptedPrompts {
                await Self.evaluate(scripted, session: session, toolName: tool.name)
            }
        } catch {
            print("Live validation failed: \(error)")
        }
    }

    /// Sends one scripted prompt to `session` and prints whether the
    /// resulting tool call matched its expected op.
    ///
    /// - Parameters:
    ///   - scripted: The prompt and its expected op string.
    ///   - session: The session to send the prompt to.
    ///   - toolName: The fused tool's name, to find its call in the
    ///     transcript.
    private static func evaluate(_ scripted: ScriptedPrompt, session: LanguageModelSession, toolName: String) async {
        do {
            _ = try await session.respond(to: scripted.prompt)
            let actual = Self.lastToolCallOpString(in: session.transcript, toolName: toolName)
            let status = actual == scripted.expectedOpString ? "OK" : "MISS"
            print("[\(status)] \"\(scripted.prompt)\" -> expected '\(scripted.expectedOpString)', got '\(actual ?? "none")'")
        } catch {
            print("[ERROR] \"\(scripted.prompt)\" -> \(error)")
        }
    }

    /// The `op` argument of the most recent call to the tool named
    /// `toolName` in `transcript`, or `nil` if it contains none.
    ///
    /// - Parameters:
    ///   - transcript: The session transcript to search.
    ///   - toolName: The tool name to match `Transcript.ToolCall.toolName`
    ///     against.
    /// - Returns: The most recent matching call's `op` argument, or `nil` if
    ///   `transcript` contains no call to `toolName`.
    private static func lastToolCallOpString(in transcript: Transcript, toolName: String) -> String? {
        var lastMatch: String?
        for entry in transcript {
            guard case .toolCalls(let calls) = entry else { continue }
            for call in calls where call.toolName == toolName {
                lastMatch = try? call.arguments.value(String.self, forProperty: OperationKeys.opFieldName)
            }
        }
        return lastMatch
    }
}
