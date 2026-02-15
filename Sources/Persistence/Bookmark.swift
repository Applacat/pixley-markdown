import Foundation
import SwiftData

// MARK: - Bookmark Model

/// A line bookmark within a file.
///
/// Bookmarks allow users to mark specific lines in a document for quick access.
/// Each bookmark is associated with a file path and line number.
@Model
public final class Bookmark {

    // MARK: - Properties

    /// Unique identifier for this bookmark
    public var id: UUID

    /// File path this bookmark belongs to
    public var filePath: String

    /// Line number (1-based, matching editor display)
    public var lineNumber: Int

    /// Optional user note for this bookmark
    public var note: String?

    /// When this bookmark was created
    public var createdAt: Date

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        filePath: String,
        lineNumber: Int,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.note = note
        self.createdAt = createdAt
    }

    // MARK: - Convenience

    /// Creates a bookmark from a file URL
    public convenience init(url: URL, lineNumber: Int, note: String? = nil) {
        self.init(filePath: url.path, lineNumber: lineNumber, note: note)
    }

    /// Returns the file URL for this bookmark
    public var url: URL {
        URL(fileURLWithPath: filePath)
    }
}
