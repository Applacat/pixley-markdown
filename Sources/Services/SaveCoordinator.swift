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

    // MARK: - Autosave (G2, US-2.3)

    private var pendingSaves: [String: Task<Void, Never>] = [:]

    /// Debounced autosave: coalesces keystrokes; the write lands ~1.5 s after
    /// typing pauses. Save timing is also "when the AI sees the edit" (D6).
    func scheduleSave(for document: MarkdownDocument, fileWatcher: FileWatcher?, after seconds: Double = 1.5) {
        let key = document.url.path
        pendingSaves[key]?.cancel()
        pendingSaves[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            try? await self?.saveNow(document, fileWatcher: fileWatcher)
        }
    }

    /// Immediate save (⌘S, or the tail of a debounce). No-op when clean.
    func saveNow(_ document: MarkdownDocument, fileWatcher: FileWatcher?) async throws {
        pendingSaves[document.url.path]?.cancel()
        pendingSaves[document.url.path] = nil
        guard document.isDirty else { return }
        try await perform(on: document, fileWatcher: fileWatcher) { $0 }
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
