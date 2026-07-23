import Foundation
import aimdRenderer
import os.log

private let log = Logger(subsystem: "com.aimd.reader", category: "SaveCoordinator")

/// The single disk-write path for document content (editor epic G1).
///
/// Absorbs InteractionHandler's per-URL serialized chain: every mutation
/// enqueues behind in-flight work on the same document, computes against the
/// MODEL's current source (never a disk read — US-1.2), commits to the model,
/// then writes atomically with FileWatcher self-write settlement.
@MainActor
final class SaveCoordinator {

    static let shared = SaveCoordinator()
    private init() {}

    enum SaveError: LocalizedError {
        case rangeMismatch
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .rangeMismatch:
                return "Document changed externally. Please try again."
            case .writeFailed(let url, let error):
                return "Failed to write \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Tail of the in-flight chain per document path (moved verbatim from
    /// InteractionHandler — one write path, per BRD guardrail 3).
    private var chains: [String: Task<Void, Never>] = [:]

    /// Serialized model mutation + save. `compute` receives the model's
    /// current source and returns the new source (throwing to refuse).
    func perform(
        on document: MarkdownDocument,
        fileWatcher: FileWatcher?,
        compute: @escaping @Sendable (String) throws -> String
    ) async throws {
        let key = document.url.path
        let previous = chains[key]

        let work = Task { () throws -> Void in
            await previous?.value

            fileWatcher?.suppressChanges(for: 1.0)
            var settled = false
            defer { if !settled { fileWatcher?.selfWriteFailed() } }

            // US-1.2: the interaction path computes against the model, not disk.
            let current = document.source
            log.debug("model-write (no disk read) for \(document.url.lastPathComponent, privacy: .public)")

            let newContent = try await Task.detached(priority: .userInitiated) {
                try compute(current)
            }.value

            document.update(source: newContent)
            do {
                try await Self.atomicWrite(newContent, to: document.url)
            } catch {
                throw SaveError.writeFailed(document.url, error)
            }
            document.syncToDisk(content: newContent)
            fileWatcher?.selfWriteCompleted()
            settled = true
        }

        let chain = Task { _ = try? await work.value }
        chains[key] = chain
        defer {
            if chains[key] == chain {
                chains[key] = nil
            }
        }
        try await work.value
    }

    /// Atomic write with security-scoped access on the parent directory
    /// (moved from InteractionHandler.secureWrite).
    private static func atomicWrite(_ content: String, to url: URL) async throws {
        let parentDir = url.deletingLastPathComponent()
        let hasAccess = parentDir.startAccessingSecurityScopedResource()
        defer { if hasAccess { parentDir.stopAccessingSecurityScopedResource() } }

        try await Task.detached(priority: .userInitiated) {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}
