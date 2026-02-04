import Foundation
import FoundationModels

// MARK: - Context Mode

enum ContextMode: Sendable {
    case fullDocument    // First question, full doc fits
    case truncated       // First question, doc was truncated
    case conversation    // Follow-up, using chat history
}

// MARK: - Context Estimate

struct ContextEstimate: Sendable {
    let usedChars: Int
    let maxChars: Int
    let mode: ContextMode

    var percentage: Double {
        min(1.0, Double(usedChars) / Double(maxChars))
    }

    var usedTokensApprox: Int {
        usedChars / 4
    }

    var maxTokensApprox: Int {
        maxChars / 4
    }

    var modeLabel: String {
        switch mode {
        case .fullDocument: return "Full doc"
        case .truncated: return "Truncated"
        case .conversation: return "Chat"
        }
    }

    var modeIcon: String {
        switch mode {
        case .fullDocument: return "doc.text"
        case .truncated: return "doc.badge.ellipsis"
        case .conversation: return "bubble.left.and.bubble.right"
        }
    }

    var isHighUsage: Bool {
        percentage > 0.9
    }

    var isMediumUsage: Bool {
        percentage > 0.7 && percentage <= 0.9
    }
}

// MARK: - Chat Service

/// Service for AI chat functionality - extracts business logic from ChatView for testability.
@MainActor
final class ChatService {

    // MARK: - Constants

    static let maxTokens = 4096
    static let charsPerToken = 4
    static let maxContextChars = maxTokens * charsPerToken  // ~16K chars
    static let maxContextLength = 8000

    // MARK: - Context Estimation

    /// Calculate context estimate for the memory meter
    func estimateContext(
        documentLength: Int,
        messages: [ChatMessage]
    ) -> ContextEstimate {
        let hasHistory = !messages.isEmpty

        if hasHistory {
            // Conversation mode: brief doc (2K) + chat history
            let historyChars = messages.suffix(6).reduce(0) { $0 + $1.content.count }
            let docChars = min(2000, documentLength)
            let totalChars = docChars + historyChars + 200 // 200 for prompt overhead
            return ContextEstimate(
                usedChars: totalChars,
                maxChars: Self.maxContextChars,
                mode: .conversation
            )
        } else {
            // Full document mode
            let docChars = min(Self.maxContextLength, documentLength)
            let totalChars = docChars + 200
            return ContextEstimate(
                usedChars: totalChars,
                maxChars: Self.maxContextChars,
                mode: documentLength > Self.maxContextLength ? .truncated : .fullDocument
            )
        }
    }

    // MARK: - Document Truncation

    /// Truncate document if it exceeds max context length
    func truncateDocument(_ content: String) -> (text: String, wasTruncated: Bool) {
        let wasTruncated = content.count > Self.maxContextLength

        if wasTruncated {
            let truncated = String(content.prefix(Self.maxContextLength))
            return (truncated + "\n\n[... document truncated for length ...]", true)
        } else {
            return (content, false)
        }
    }

    // MARK: - Prompt Building

    /// Build the prompt for the AI request
    func buildPrompt(
        question: String,
        documentContent: String,
        priorMessages: [ChatMessage]
    ) -> String {
        let hasConversationHistory = !priorMessages.isEmpty
        let (context, _) = truncateDocument(documentContent)

        if hasConversationHistory {
            // Include recent chat history for follow-up questions
            let recentHistory = priorMessages.suffix(6) // Last 3 exchanges
            let historyText = recentHistory.map { msg in
                let role = msg.role == .user ? "User" : "Assistant"
                return "\(role): \(msg.content)"
            }.joined(separator: "\n\n")

            return """
            Document context (for reference):
            ---
            \(context.prefix(2000))...
            ---

            Previous conversation:
            \(historyText)

            User's new question: \(question)
            """
        } else {
            // First question - include full document context
            return """
            Document content:
            ---
            \(context)
            ---

            Question: \(question)
            """
        }
    }

    // MARK: - System Prompt

    var systemPrompt: String {
        """
        You are a helpful assistant analyzing a markdown document.
        Answer questions about the document concisely and accurately.
        If the answer is not in the document, say so.
        When the user asks follow-up questions about your previous responses,
        refer to the conversation history rather than re-analyzing the document.
        """
    }

    // MARK: - AI Request

    /// Send a question to the AI and get a response
    func askAI(
        question: String,
        documentContent: String,
        priorMessages: [ChatMessage]
    ) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let prompt = buildPrompt(
            question: question,
            documentContent: documentContent,
            priorMessages: priorMessages
        )

        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Availability Check

    /// Check if Apple Intelligence is available
    func checkAvailability() -> Bool {
        SystemLanguageModel.default.availability == .available
    }
}
