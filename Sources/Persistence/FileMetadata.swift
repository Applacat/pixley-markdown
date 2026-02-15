import Foundation
import SwiftData

// MARK: - File Metadata Model

/// Persisted metadata for a file, including reading progress and favorites.
///
/// Uses file path as unique identifier since URLs can change between sessions
/// but paths within a folder remain stable.
@Model
public final class FileMetadata {

    // MARK: - Properties

    /// File path (unique identifier)
    /// Stored as path string since URLs aren't directly persistable
    @Attribute(.unique)
    public var filePath: String

    /// Scroll position as percentage (0.0 to 1.0)
    public var scrollPosition: Double

    /// Whether this file is marked as favorite
    public var isFavorite: Bool

    /// Last time this file was opened
    public var lastOpened: Date

    // MARK: - Initialization

    public init(
        filePath: String,
        scrollPosition: Double = 0.0,
        isFavorite: Bool = false,
        lastOpened: Date = .now
    ) {
        self.filePath = filePath
        self.scrollPosition = scrollPosition
        self.isFavorite = isFavorite
        self.lastOpened = lastOpened
    }

    // MARK: - Convenience

    /// Creates metadata from a file URL
    public convenience init(url: URL) {
        self.init(filePath: url.path)
    }

    /// Returns the file URL for this metadata
    public var url: URL {
        URL(fileURLWithPath: filePath)
    }
}
