import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os.log
import aimdRenderer

// MARK: - Chat Service

/// Service for AI chat functionality using Apple Foundation Models.
///
/// Foundation Models is stateful — LanguageModelSession maintains its own
/// transcript internally. Document context goes in `instructions` once,
/// and questions are sent via `respond(to:)`.
///
/// Context management strategy:
/// 1. Per-turn transcript condensation (replaces 3-turn hard reset)
/// 2. AI summarizer with heuristic fallback + retry-with-backoff
/// 3. Summaries persisted via SwiftData (one per document, LRU cap 50)
/// 4. Document truncation — cap at ~2500 chars to leave headroom
/// 5. Conversation resets on document switch
///
/// Crash prevention:
/// 1. Catch ALL GenerationError types (context exceeded, guardrail, language)
/// 2. Timeout — races respond() against a sleep; if sleep wins, cancelled + reset
/// 3. Fresh session per conversation — never reuse across "Forget" resets
@available(macOS 26, *)
@MainActor
final class ChatService {

    private static let log = Logger(subsystem: "com.aimd.reader", category: "ChatService")

    // MARK: - Properties

    private var session: LanguageModelSession?

    /// Number of completed Q&A round-trips in this session
    private(set) var turnCount = 0

    /// Whether condensation is currently running (for UI indicator)
    private(set) var isCondensing = false

    /// The document content used to initialize the current session
    private var currentDocumentContent: String = ""

    /// The current document path (for persistence key)
    private var currentDocumentPath: String = ""

    /// Live condensed summary for the current session
    private var currentSummary: String?

    /// Transcript condenser (AI + heuristic strategies)
    private let condenser = TranscriptCondenser()

    /// Summary persistence repository (injected)
    private var summaryRepository: ChatSummaryRepository?

    /// FM tool for editing interactive elements via voice commands
    private let editTool = EditInteractiveElementsTool()

    // MARK: - Configuration

    /// Injects the summary repository for persistence.
    /// Call once after SwiftData container is ready.
    func configure(summaryRepository: ChatSummaryRepository) {
        self.summaryRepository = summaryRepository
    }

    /// Sets up the edit tool with file URL and edit handler.
    /// Call when the document changes or on first load.
    func configureEditTool(fileURL: URL?, onEdit: (@Sendable @MainActor (InteractiveEdit, URL) async throws -> String)?) {
        editTool.fileURL = fileURL
        editTool.onEdit = onEdit
    }

    // MARK: - Session Management

    /// Creates a fresh session with document context and condensed summary.
    func startSession(documentContent: String, documentPath: String = "") {
        let truncated = String(documentContent.prefix(ChatConfiguration.maxDocumentChars))
        currentDocumentContent = truncated
        if !documentPath.isEmpty { currentDocumentPath = documentPath }

        // Update edit tool with current document content
        editTool.documentContent = documentContent

        // Load persisted summary if available for this document
        if !currentDocumentPath.isEmpty, currentSummary == nil {
            currentSummary = summaryRepository?.getSummary(for: currentDocumentPath)?.summary
        }

        let instructions = buildInstructions(
            documentContent: truncated,
            summary: currentSummary
        )

        // Create session with edit tool for interactive documents
        let hasInteractiveElements = !InteractiveElementDetector.detect(in: documentContent).isEmpty
        if hasInteractiveElements {
            session = LanguageModelSession(tools: [editTool], instructions: instructions)
        } else {
            session = LanguageModelSession(instructions: instructions)
        }
        turnCount = 0
        Self.log.info("Session started with \(truncated.count) chars, tools: \(hasInteractiveElements), summary: \(self.currentSummary?.count ?? 0) chars")
    }

    /// Resets the session completely (user pressed "Forget").
    /// Clears both live session AND persisted summary for current document.
    func resetSession() {
        if turnCount > 0 {
            Self.log.info("Session reset after \(self.turnCount) turns")
        }

        // Cancel any in-flight condensation
        condensationTask?.cancel()
        condensationTask = nil

        // Delete persisted summary for current document
        if !currentDocumentPath.isEmpty {
            summaryRepository?.deleteSummary(for: currentDocumentPath)
        }

        session = nil
        turnCount = 0
        isCondensing = false
        currentSummary = nil
        currentDocumentContent = ""
        currentDocumentPath = ""
        condenser.reset()
    }

    /// Resets conversation for a new document.
    /// Persists current summary, then clears all live state.
    func switchDocument(documentContent: String, documentPath: String) {
        // Persist summary for the document we're leaving
        if !currentDocumentPath.isEmpty, let summary = currentSummary {
            summaryRepository?.saveSummary(
                documentPath: currentDocumentPath,
                summary: summary
            )
        }

        // Cancel any in-flight condensation
        condensationTask?.cancel()
        condensationTask = nil

        // Full reset for new document
        session = nil
        turnCount = 0
        isCondensing = false
        currentSummary = nil
        condenser.reset()

        // Store new document info (session created lazily on first ask)
        let truncated = String(documentContent.prefix(ChatConfiguration.maxDocumentChars))
        currentDocumentContent = truncated
        currentDocumentPath = documentPath

        // Pre-load persisted summary for the new document
        if !documentPath.isEmpty {
            currentSummary = summaryRepository?.getSummary(for: documentPath)?.summary
        }

        Self.log.info("Switched to document, existing summary: \(self.currentSummary != nil)")
    }

    // MARK: - Ask Question

    /// Sends a question to Foundation Models and returns the full response.
    ///
    /// After a successful response, fires per-turn condensation as a background task.
    /// The caller should observe `isCondensing` to show "Organizing thoughts..." indicator.
    ///
    /// Includes a built-in timeout: if `respond(to:)` doesn't return within
    /// `ChatConfiguration.responseTimeout`, the call is cancelled, the session
    /// is reset, and an error result is returned.
    func ask(
        question: String,
        documentContent: String,
        documentPath: String = "",
        messages: [ChatMessage]
    ) async -> ChatResult {
        // Ensure session exists (auto-create if needed)
        if session == nil {
            startSession(documentContent: documentContent, documentPath: documentPath)
        }

        guard let session else {
            return .error("Session could not be created.")
        }

        Self.log.info("Asking question: turn=\(self.turnCount + 1), question=\(question.prefix(80), privacy: .private)")

        // Capture session reference before crossing Task boundary
        let capturedSession = session

        // Race respond() vs timeout
        let respondTask = Task<String, Error> {
            let response = try await capturedSession.respond(to: question)
            return response.content
        }

        let watchdog = Task {
            try await Task.sleep(for: ChatConfiguration.responseTimeout)
            respondTask.cancel()
        }

        do {
            let content = try await respondTask.value
            watchdog.cancel()

            turnCount += 1
            Self.log.info("Response received: \(content.count) chars, turn=\(self.turnCount)")

            // Fire condensation as a background task — does NOT block the response
            let allMessages = messages + [ChatMessage(role: .assistant, content: content)]
            condensationTask?.cancel()
            condensationTask = Task { await runCondensation(messages: allMessages) }

            return .success(content)
        } catch let error as LanguageModelSession.GenerationError {
            watchdog.cancel()
            return handleGenerationError(error, documentContent: documentContent)
        } catch is CancellationError {
            watchdog.cancel()
            if respondTask.isCancelled {
                Self.log.error("Response timed out after \(ChatConfiguration.responseTimeout)")
                startSession(documentContent: documentContent, documentPath: currentDocumentPath)
                return .error("The AI took too long to respond. The conversation has been reset — please try again.")
            }
            return .cancelled
        } catch {
            watchdog.cancel()
            Self.log.error("Unexpected error: \(error.localizedDescription)")
            return .error("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Condensation

    /// Background condensation task — cancelled on new ask or reset
    private var condensationTask: Task<Void, Never>?

    /// Runs per-turn condensation after a successful response.
    /// Updates isCondensing for UI, persists summary, and refreshes session.
    private func runCondensation(messages: [ChatMessage]) async {
        isCondensing = true
        defer { isCondensing = false }

        let condensed = await condenser.condense(
            messages: messages,
            existingSummary: currentSummary
        )

        guard !Task.isCancelled, let condensed else { return }

        currentSummary = condensed

        // Persist to SwiftData
        if !currentDocumentPath.isEmpty {
            summaryRepository?.saveSummary(
                documentPath: currentDocumentPath,
                summary: condensed
            )
        }

        // Create fresh session with updated summary
        let instructions = buildInstructions(
            documentContent: currentDocumentContent,
            summary: condensed
        )

        let hasInteractiveElements = !InteractiveElementDetector.detect(in: editTool.documentContent).isEmpty
        if hasInteractiveElements {
            session = LanguageModelSession(tools: [editTool], instructions: instructions)
        } else {
            session = LanguageModelSession(instructions: instructions)
        }
        Self.log.info("Session refreshed with condensed summary (\(condensed.count) chars)")
    }

    // MARK: - Instructions Builder

    private func buildInstructions(documentContent: String, summary: String?) -> String {
        var parts: [String] = [
            "You help users understand and interact with markdown documents. Be direct and specific. Don't repeat what the user already knows."
        ]

        // Build structured context if document has interactive elements
        let structure = MarkdownStructureParser.parse(text: documentContent)
        if !structure.elements.isEmpty {
            // Use structured summary (compact, element-aware)
            let structuredContext = buildStructuredContext(structure: structure, content: documentContent)
            parts.append("Document (interactive):\n---\n\(structuredContext)\n---")
        } else {
            // Plain document — use truncated raw text
            parts.append("Document:\n---\n\(documentContent)\n---")
        }

        if let summary, !summary.isEmpty {
            parts.append("Earlier conversation:\n\(summary)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Builds a structured context string for FM instructions.
    /// Uses outline + element state, falling back to deeper outlines within budget.
    private func buildStructuredContext(structure: DocumentStructure, content: String) -> String {
        let budget = ChatConfiguration.maxDocumentChars

        // Try full summary first (most informative)
        let fullSummary = structure.summary()
        let elementIndex = buildElementIndex(structure: structure)

        let full = "Outline with elements:\n\(fullSummary)\n\nElement state:\n\(elementIndex)"
        if full.count <= budget {
            return full
        }

        // If too large, use outline depth 2 + element index
        let outline2 = structure.outline(maxDepth: 2)
        let medium = "Outline:\n\(outline2)\n\nElement state:\n\(elementIndex)"
        if medium.count <= budget {
            return medium
        }

        // Tight budget: outline depth 1 + truncated element index
        let outline1 = structure.outline(maxDepth: 1)
        let truncatedIndex = String(elementIndex.prefix(budget / 2))
        return "Outline:\n\(outline1)\n\nElements:\n\(truncatedIndex)"
    }

    /// Builds a section-grouped element index showing only incomplete/actionable items.
    /// Completed items are summarized as a count per section.
    private func buildElementIndex(structure: DocumentStructure) -> String {
        var sections: [(title: String, remaining: [(index: Int, description: String)], completed: Int, total: Int)] = []
        collectSectionElements(structure.sections, allElements: structure.elements, content: structure.content, into: &sections)

        let totalCompleted = sections.reduce(0) { $0 + $1.completed }
        let totalAll = sections.reduce(0) { $0 + $1.total }

        var result = "Completion: \(totalCompleted)/\(totalAll)"
        if totalCompleted == totalAll && totalAll > 0 {
            result += " — all done!"
            return result
        }

        for section in sections where !section.remaining.isEmpty || section.total > 0 {
            let prefix = section.completed == section.total ? "✓" : " "
            result += "\n\n\(prefix) \(section.title) (\(section.completed)/\(section.total))"
            for item in section.remaining {
                result += "\n  \(item.index): \(item.description)"
            }
        }

        return result
    }

    /// Recursively collects element state grouped by section headings.
    private func collectSectionElements(_ sections: [Section], allElements: [InteractiveElement], content: String, into result: inout [(title: String, remaining: [(index: Int, description: String)], completed: Int, total: Int)]) {
        for section in sections {
            var remaining: [(index: Int, description: String)] = []
            var completed = 0
            var total = 0

            // Only count elements directly in this section (not children)
            for element in section.elements {
                guard let i = allElements.firstIndex(where: { $0.id == element.id }) else { continue }
                switch element {
                case .checkbox(let cb):
                    total += 1
                    if cb.isChecked { completed += 1 }
                    else { remaining.append((i, "checkbox [ ] \(cb.label)")) }
                case .choice(let ch):
                    total += 1
                    if ch.selectedIndex != nil { completed += 1 }
                    else {
                        let options = ch.options.map(\.label).joined(separator: ", ")
                        remaining.append((i, "choice (no selection) options: \(options)"))
                    }
                case .review(let rv):
                    total += 1
                    if rv.selectedStatus != nil { completed += 1 }
                    else { remaining.append((i, "review (pending)")) }
                case .fillIn(let fi):
                    total += 1
                    if fi.value != nil { completed += 1 }
                    else { remaining.append((i, "fill-in [\(fi.hint)]")) }
                case .feedback(let fb):
                    total += 1
                    if fb.existingText != nil { completed += 1 }
                    else { remaining.append((i, "feedback (empty)")) }
                case .status(let st):
                    remaining.append((i, "status (\(st.currentState))"))
                case .confidence(let c):
                    remaining.append((i, "confidence (\(c.level.rawValue))"))
                case .suggestion(let s):
                    remaining.append((i, "suggestion (\(s.type))"))
                default:
                    break
                }
            }

            if total > 0 || !remaining.isEmpty {
                let heading = String(repeating: "#", count: section.level)
                result.append((title: "\(heading) \(section.title)", remaining: remaining, completed: completed, total: total))
            }

            // Recurse into children
            collectSectionElements(section.children, allElements: allElements, content: content, into: &result)
        }
    }

    // MARK: - Error Handling

    private func handleGenerationError(
        _ error: LanguageModelSession.GenerationError,
        documentContent: String
    ) -> ChatResult {
        switch error {
        case .exceededContextWindowSize:
            Self.log.warning("Context window exceeded at turn \(self.turnCount)")
            startSession(documentContent: documentContent, documentPath: currentDocumentPath)
            return .error("Context limit reached. The conversation has been reset — please ask your question again.")

        case .guardrailViolation:
            Self.log.warning("Guardrail violation")
            return .error("I can't respond to that question. Please try rephrasing.")

        case .unsupportedLanguageOrLocale:
            Self.log.warning("Unsupported language/locale")
            return .error("This language isn't supported by on-device AI. Please try asking in English.")

        default:
            Self.log.error("Unknown GenerationError: \(String(describing: error))")
            startSession(documentContent: documentContent, documentPath: currentDocumentPath)
            return .error("An unexpected AI error occurred. The conversation has been reset.")
        }
    }
}

// MARK: - Chat Result

/// Result of a chat request, covering all outcomes.
@available(macOS 26, *)
enum ChatResult {
    /// Successful response
    case success(String)
    /// Error message to display to user
    case error(String)
    /// Request was cancelled
    case cancelled
}
