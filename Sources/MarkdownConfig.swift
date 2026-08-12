import Foundation

/// Document-size limits (extracted from the retired MarkdownEditor in G4-P2).
enum MarkdownConfig {
    /// Maximum allowed text size (10MB) to prevent DoS attacks.
    /// Accessible from any context without actor isolation.
    static let maxTextSize = 10_485_760
}
