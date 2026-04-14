import Foundation

/// Detects and resolves iCloud file conflicts using NSFileVersion.
enum ConflictResolver {

    /// A conflict version with metadata for display.
    struct ConflictVersion: Identifiable {
        let id = UUID()
        let fileVersion: NSFileVersion
        let modificationDate: Date?
        let deviceName: String?

        var summary: String {
            let date = modificationDate.map {
                Self.dateFormatter.string(from: $0)
            } ?? "Unknown date"
            let device = deviceName ?? "Unknown device"
            return "\(date) — \(device)"
        }

        private static let dateFormatter: DateFormatter = {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            return fmt
        }()
    }

    /// Checks if a file has unresolved iCloud conflicts.
    static func hasConflicts(url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey])
        return values?.ubiquitousItemHasUnresolvedConflicts ?? false
    }

    /// Returns unresolved conflict versions for a file.
    static func conflictVersions(for url: URL) -> [ConflictVersion] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else {
            return []
        }
        return versions.map { version in
            ConflictVersion(
                fileVersion: version,
                modificationDate: version.modificationDate,
                deviceName: version.localizedNameOfSavingComputer
            )
        }
    }

    /// Resolves conflict by keeping the current version and discarding all conflicts.
    static func keepCurrent(url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else { return }
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    /// Resolves conflict by replacing the current file with a chosen conflict version.
    static func keepVersion(_ version: ConflictVersion, at url: URL) throws {
        try version.fileVersion.replaceItem(at: url, options: [])
        version.fileVersion.isResolved = true

        // Mark all other conflicts as resolved
        if let remaining = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
            for conflict in remaining {
                conflict.isResolved = true
            }
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}
