import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// ChatService uses FoundationModels (@available(macOS 26, *)) which we can't import in tests.
// We mirror the state machine logic: turn counting, session lifecycle, error mapping,
// and per-turn condensation (fire-and-forget, does not block response).

// MARK: - ChatResult Mirror

private enum TestableChatResult: Equatable {
    case success(String)
    case error(String)
    case cancelled
}

// MARK: - ChatConfiguration Mirror

private enum TestableChatConfiguration {
    static let responseTimeoutSeconds: Double = 30
    static let maxDocumentChars = 2500
}

// MARK: - GenerationError Mirror

private enum TestableGenerationError: Error {
    case exceededContextWindowSize
    case guardrailViolation
    case unsupportedLanguageOrLocale
}

// MARK: - ChatService Mirror

/// Mirrors ChatService state machine logic without FoundationModels dependency.
/// The respond closure simulates LanguageModelSession.respond(to:).
/// Note: Production ChatService is @MainActor, but the test mirror omits it
/// to avoid actor-isolation complexities in setUp — we're testing logic, not concurrency.
///
/// Production ChatService uses per-turn transcript condensation (AI + heuristic)
/// instead of hard auto-reset. Condensation runs as a fire-and-forget background
/// task after each successful response. This mirror simulates the condensation
/// flag lifecycle.
private final class TestableChatService {

    private(set) var turnCount = 0
    private(set) var isCondensing = false
    private var hasSession = false
    private var currentDocumentContent: String = ""
    private var currentDocumentName: String = ""
    private var currentDocumentPath: String = ""
    private var currentSummary: String?

    /// Injectable respond closure — simulates LanguageModelSession.respond(to:)
    var respondHandler: ((String) async throws -> String)?

    /// Injectable condense closure — simulates TranscriptCondenser.condense()
    var condenseHandler: (([String], String, String?) -> String?)?

    func startSession(documentContent: String, documentName: String = "", documentPath: String = "") {
        let truncated = String(documentContent.prefix(TestableChatConfiguration.maxDocumentChars))
        currentDocumentContent = truncated
        if !documentName.isEmpty { currentDocumentName = documentName }
        if !documentPath.isEmpty { currentDocumentPath = documentPath }
        hasSession = true
        turnCount = 0
    }

    func resetSession() {
        hasSession = false
        turnCount = 0
        isCondensing = false
        currentSummary = nil
        currentDocumentContent = ""
        currentDocumentName = ""
        currentDocumentPath = ""
    }

    func switchDocument(documentContent: String, documentName: String, documentPath: String) {
        // Persist current summary would happen here in production
        hasSession = false
        turnCount = 0
        isCondensing = false
        currentSummary = nil

        let truncated = String(documentContent.prefix(TestableChatConfiguration.maxDocumentChars))
        currentDocumentContent = truncated
        currentDocumentName = documentName
        currentDocumentPath = documentPath
    }

    func ask(question: String, documentContent: String, documentName: String = "", documentPath: String = "") async -> TestableChatResult {
        // Ensure session exists (auto-create if needed)
        if !hasSession {
            startSession(documentContent: documentContent, documentName: documentName, documentPath: documentPath)
        }

        guard hasSession else {
            return .error("Session could not be created.")
        }

        guard let respondHandler else {
            return .error("No respond handler configured.")
        }

        do {
            let content = try await respondHandler(question)
            turnCount += 1

            // Simulate fire-and-forget condensation
            if let condenseHandler {
                isCondensing = true
                let condensed = condenseHandler([question, content], currentDocumentName, currentSummary)
                if let condensed {
                    currentSummary = condensed
                }
                isCondensing = false
            }

            return .success(content)
        } catch let error as TestableGenerationError {
            return handleGenerationError(error, documentContent: documentContent)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .error("Error: \(error.localizedDescription)")
        }
    }

    private func handleGenerationError(
        _ error: TestableGenerationError,
        documentContent: String
    ) -> TestableChatResult {
        switch error {
        case .exceededContextWindowSize:
            startSession(documentContent: documentContent, documentName: currentDocumentName, documentPath: currentDocumentPath)
            return .error("Context limit reached. The conversation has been reset — please ask your question again.")

        case .guardrailViolation:
            return .error("I can't respond to that question. Please try rephrasing.")

        case .unsupportedLanguageOrLocale:
            return .error("This language isn't supported by on-device AI. Please try asking in English.")
        }
    }
}

// MARK: - Tests

final class ChatServiceTests: XCTestCase {

    private var service: TestableChatService!

    override func setUp() {
        service = TestableChatService()
        service.respondHandler = { question in
            return "Response to: \(question)"
        }
    }

    override func tearDown() {
        service = nil
    }

    // MARK: - Session Lifecycle

    func testStartSession_resetsTurnCount() {
        service.startSession(documentContent: "doc")
        XCTAssertEqual(service.turnCount, 0)
    }

    func testResetSession_clearsAllState() async {
        // Given: Active session with turns
        _ = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 1)

        // When: Reset
        service.resetSession()

        // Then: All state cleared
        XCTAssertEqual(service.turnCount, 0)
        XCTAssertFalse(service.isCondensing)
    }

    // MARK: - Auto-create Session

    func testAsk_withNoSession_autoCreates() async {
        // Given: No explicit startSession call
        service.resetSession()

        // When: Ask creates session automatically
        let result = await service.ask(question: "Q1", documentContent: "doc content")

        // Then: Succeeds (session was auto-created)
        if case .success(let response) = result {
            XCTAssertTrue(response.contains("Q1"))
        } else {
            XCTFail("Expected .success, got \(result)")
        }
    }

    // MARK: - Turn Counting

    func testAsk_incrementsTurnCount() async {
        service.startSession(documentContent: "doc")
        XCTAssertEqual(service.turnCount, 0)

        _ = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 1)

        _ = await service.ask(question: "Q2", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 2)

        _ = await service.ask(question: "Q3", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 3)
    }

    func testAsk_beyondThreeTurns_continuesWithoutReset() async {
        // With per-turn condensation, there is no hard turn limit.
        // Sessions continue indefinitely as condensation manages context.
        service.startSession(documentContent: "doc")

        for i in 1...5 {
            let result = await service.ask(question: "Q\(i)", documentContent: "doc")
            if case .success = result {
                // Expected — no reset
            } else {
                XCTFail("Expected .success at turn \(i), got \(result)")
            }
        }
        XCTAssertEqual(service.turnCount, 5)
    }

    func testNormalResponse_returnsSuccess() async {
        service.startSession(documentContent: "doc")
        let result = await service.ask(question: "Q1", documentContent: "doc")
        if case .success(let response) = result {
            XCTAssertTrue(response.contains("Q1"))
        } else {
            XCTFail("Expected .success, got \(result)")
        }
    }

    // MARK: - Condensation

    func testCondensation_runsAfterSuccessfulResponse() async {
        var condensationCalled = false
        service.condenseHandler = { _, _, _ in
            condensationCalled = true
            return "Summary of conversation"
        }

        service.startSession(documentContent: "doc", documentName: "test.md")
        _ = await service.ask(question: "Q1", documentContent: "doc", documentName: "test.md")

        XCTAssertTrue(condensationCalled)
        XCTAssertFalse(service.isCondensing, "isCondensing should be false after condensation completes")
    }

    func testCondensation_doesNotRunOnError() async {
        var condensationCalled = false
        service.condenseHandler = { _, _, _ in
            condensationCalled = true
            return "Summary"
        }
        service.respondHandler = { _ in
            throw TestableGenerationError.guardrailViolation
        }

        service.startSession(documentContent: "doc")
        _ = await service.ask(question: "bad", documentContent: "doc")

        XCTAssertFalse(condensationCalled)
    }

    // MARK: - Document Switching

    func testSwitchDocument_clearsState() async {
        service.startSession(documentContent: "doc1", documentName: "file1.md", documentPath: "/file1.md")
        _ = await service.ask(question: "Q1", documentContent: "doc1")
        XCTAssertEqual(service.turnCount, 1)

        service.switchDocument(documentContent: "doc2", documentName: "file2.md", documentPath: "/file2.md")

        XCTAssertEqual(service.turnCount, 0)
        XCTAssertFalse(service.isCondensing)
    }

    func testSwitchDocument_allowsNewConversation() async {
        service.startSession(documentContent: "doc1", documentName: "file1.md", documentPath: "/file1.md")
        _ = await service.ask(question: "Q1", documentContent: "doc1")

        service.switchDocument(documentContent: "doc2", documentName: "file2.md", documentPath: "/file2.md")

        let result = await service.ask(question: "Q about doc2", documentContent: "doc2", documentName: "file2.md", documentPath: "/file2.md")
        if case .success(let response) = result {
            XCTAssertTrue(response.contains("Q about doc2"))
        } else {
            XCTFail("Expected .success, got \(result)")
        }
        XCTAssertEqual(service.turnCount, 1)
    }

    // MARK: - Error Handling

    func testError_contextExceeded_resetsSession() async {
        service.startSession(documentContent: "doc")
        service.respondHandler = { _ in
            throw TestableGenerationError.exceededContextWindowSize
        }

        let result = await service.ask(question: "Q1", documentContent: "doc")
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("Context limit"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
        // Session was reset (turnCount back to 0)
        XCTAssertEqual(service.turnCount, 0)
    }

    func testError_guardrailViolation_doesNotResetSession() async {
        service.startSession(documentContent: "doc")
        _ = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(service.turnCount, 1)

        // Reconfigure to throw guardrail
        service.respondHandler = { _ in
            throw TestableGenerationError.guardrailViolation
        }

        let result = await service.ask(question: "bad question", documentContent: "doc")
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("can't respond"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
        // Session NOT reset — turnCount still 1
        XCTAssertEqual(service.turnCount, 1)
    }

    func testError_unsupportedLanguage_returnsError() async {
        service.startSession(documentContent: "doc")
        service.respondHandler = { _ in
            throw TestableGenerationError.unsupportedLanguageOrLocale
        }

        let result = await service.ask(question: "Q1", documentContent: "doc")
        if case .error(let message) = result {
            XCTAssertTrue(message.contains("language isn't supported"))
        } else {
            XCTFail("Expected .error, got \(result)")
        }
    }

    // MARK: - Cancellation

    func testCancellation_returnsCancelled() async {
        service.startSession(documentContent: "doc")
        service.respondHandler = { _ in
            throw CancellationError()
        }

        let result = await service.ask(question: "Q1", documentContent: "doc")
        XCTAssertEqual(result, .cancelled)
    }
}
