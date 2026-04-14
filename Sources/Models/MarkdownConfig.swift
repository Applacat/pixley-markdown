/// Shared configuration constants for markdown handling.
enum MarkdownConfig {
    /// Maximum allowed text size (10MB) to prevent DoS attacks
    static let maxTextSize = 10_485_760

    /// Maximum text size for syntax highlighting (1MB)
    /// Files larger than this show plain text
    static let maxHighlightSize = 1_048_576
}
