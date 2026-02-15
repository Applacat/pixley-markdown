import Foundation

// MARK: - Welcome Manager

/// Manages the Welcome tutorial folder lifecycle.
/// Ensures the bundled Welcome folder exists in Application Support
/// and provides its URL for first-launch and help menu flows.
enum WelcomeManager {

    /// Welcome folder in Application Support (persists reliably, backed up)
    static var welcomeFolderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("Welcome")
    }

    /// Ensures Welcome folder exists in Application Support, copying from bundle if needed.
    /// Returns the folder URL if available, nil if bundle resource is missing.
    static func ensureWelcomeFolder() -> URL? {
        guard let targetURL = welcomeFolderURL else { return nil }

        // Already exists - use it
        if FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        // Copy from bundle
        guard let bundleURL = Bundle.main.url(forResource: "Welcome", withExtension: nil) else {
            return nil
        }

        do {
            let parentDir = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bundleURL, to: targetURL)
            return targetURL
        } catch {
            return nil  // Silent fallback
        }
    }
}
