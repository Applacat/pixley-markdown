import Foundation
import SwiftData

// MARK: - Chat Summary Model

/// Persisted conversation summary for a document.
///
/// One record per document path. Updated after each condensation.
/// LRU eviction at 50 records by lastUpdated.
@Model
public final class ChatSummary {

    // MARK: - Properties

    /// Document file path (unique key)
    @Attribute(.unique)
    public var documentPath: String

    /// Display name of the document
    public var documentName: String

    /// Condensed conversation summary (~200-400 chars)
    public var summary: String

    /// Last time this summary was updated
    public var lastUpdated: Date

    // MARK: - Initialization

    public init(
        documentPath: String,
        documentName: String,
        summary: String,
        lastUpdated: Date = .now
    ) {
        self.documentPath = documentPath
        self.documentName = documentName
        self.summary = summary
        self.lastUpdated = lastUpdated
    }
}
