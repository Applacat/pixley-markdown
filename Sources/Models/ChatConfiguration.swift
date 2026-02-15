import Foundation

// MARK: - Chat Configuration

/// Centralized configuration constants for chat functionality.
/// Tuned for Apple Foundation Models' 4096-token context window.
enum ChatConfiguration {

    // MARK: - Message Limits

    /// Maximum number of messages to keep in chat history display
    static let maxMessageHistory = 50

    /// Maximum allowed input length (characters) for user questions
    static let maxInputLength = 2000

    // MARK: - Foundation Models Limits

    /// Maximum document characters to include in instructions (~800 tokens).
    /// Leaves headroom for conversation within the 4096-token context window.
    static let maxDocumentChars = 2500

    /// Auto-reset session after this many Q&A round-trips.
    /// Prevents context window exhaustion on long conversations.
    static let maxTurnsBeforeReset = 3

    /// Timeout for each Foundation Models respond() call.
    /// Prevents app freeze if the model hangs.
    static let responseTimeout: Duration = .seconds(30)
}
