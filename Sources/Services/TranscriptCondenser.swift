import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os.log

// MARK: - Transcript Condenser

/// Compresses conversation history into a condensed summary after each Q&A turn.
///
/// Two strategies:
/// 1. **AI strategy**: Dedicated LanguageModelSession summarizes the conversation
/// 2. **Heuristic strategy**: Keep last 2 Q&A pairs verbatim, drop older ones
///
/// Retry-with-backoff: after FM summarizer failure, skip 2 turns on heuristic,
/// then retry FM.
@available(macOS 26, iOS 26, *)
@MainActor
final class TranscriptCondenser {

    private static let log = Logger(subsystem: "com.aimd.reader", category: "TranscriptCondenser")

    // MARK: - Backoff State

    /// Number of consecutive FM summarizer failures
    private var failureCount = 0

    /// Number of heuristic turns to skip before retrying FM
    private var skipsRemaining = 0

    // MARK: - Condense

    /// Condenses a conversation transcript into a compact summary.
    ///
    /// - Parameters:
    ///   - messages: The full message history (user + assistant pairs)
    ///   - existingSummary: Any previous condensed summary to include
    /// - Returns: A condensed summary string, or nil if no condensation needed
    func condense(
        messages: [ChatMessage],
        existingSummary: String?
    ) async -> String? {
        let qaPairs = extractQAPairs(from: messages)
        guard !qaPairs.isEmpty else { return existingSummary }

        let transcriptText = buildTranscriptText(
            qaPairs: qaPairs,
            existingSummary: existingSummary
        )

        // Decide strategy based on backoff state
        if skipsRemaining > 0 {
            skipsRemaining -= 1
            Self.log.info("Using heuristic (skips remaining: \(self.skipsRemaining))")
            return heuristicCondense(qaPairs: qaPairs, existingSummary: existingSummary)
        }

        // Try AI summarization
        do {
            let summary = try await aiCondense(transcriptText: transcriptText)
            failureCount = 0
            Self.log.info("AI condensation succeeded: \(summary.count) chars")
            return summary
        } catch {
            failureCount += 1
            skipsRemaining = 2
            Self.log.warning("AI condensation failed (failure #\(self.failureCount)), falling back to heuristic")
            return heuristicCondense(qaPairs: qaPairs, existingSummary: existingSummary)
        }
    }

    /// Resets backoff state (e.g., on Forget)
    func reset() {
        failureCount = 0
        skipsRemaining = 0
    }

    // MARK: - AI Strategy

    /// Timeout for the AI summarizer — keeps condensation under NFR-1 (< 3 seconds).
    private static let summarizerTimeout: Duration = .seconds(5)

    private func aiCondense(transcriptText: String) async throws -> String {
        let summarizerSession = LanguageModelSession(instructions: Prompts.condenserSystem)

        let capturedSession = summarizerSession
        let respondTask = Task<String, Error> {
            let response = try await capturedSession.respond(to: transcriptText)
            return String(response.content.prefix(400))
        }

        let watchdog = Task {
            try await Task.sleep(for: Self.summarizerTimeout)
            respondTask.cancel()
        }

        do {
            let summary = try await respondTask.value
            watchdog.cancel()
            return summary
        } catch {
            watchdog.cancel()
            throw error
        }
    }

    // MARK: - Heuristic Strategy

    private func heuristicCondense(
        qaPairs: [(question: String, answer: String)],
        existingSummary: String?
    ) -> String {
        let recentPairs = qaPairs.suffix(2)
        var parts: [String] = []

        if let existing = existingSummary, !existing.isEmpty {
            parts.append("Earlier: \(existing)")
        }

        parts.append("Recent Q&A:")
        for pair in recentPairs {
            let truncatedQ = String(pair.question.prefix(100))
            let truncatedA = String(pair.answer.prefix(150))
            parts.append("Q: \(truncatedQ)")
            parts.append("A: \(truncatedA)")
        }

        return String(parts.joined(separator: "\n").prefix(400))
    }

    // MARK: - Helpers

    private func extractQAPairs(from messages: [ChatMessage]) -> [(question: String, answer: String)] {
        var pairs: [(question: String, answer: String)] = []
        var i = 0
        while i < messages.count - 1 {
            if messages[i].role == .user && messages[i + 1].role == .assistant {
                pairs.append((question: messages[i].content, answer: messages[i + 1].content))
                i += 2
            } else {
                i += 1
            }
        }
        return pairs
    }

    private func buildTranscriptText(
        qaPairs: [(question: String, answer: String)],
        existingSummary: String?
    ) -> String {
        var text = "Conversation:\n"

        if let existing = existingSummary, !existing.isEmpty {
            text += "\nPrevious context: \(existing)\n\n"
        }

        for pair in qaPairs {
            text += "User: \(pair.question)\n"
            text += "Assistant: \(pair.answer)\n\n"
        }

        return text
    }
}
