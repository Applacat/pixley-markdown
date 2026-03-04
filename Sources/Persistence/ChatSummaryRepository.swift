import Foundation
import SwiftData
import os.log

// MARK: - Chat Summary Repository Protocol

/// Repository for persisting conversation summaries per document.
@MainActor
public protocol ChatSummaryRepository: Sendable {

    /// Gets the summary for a document path, or nil if none exists
    func getSummary(for documentPath: String) -> ChatSummary?

    /// Saves or updates a summary for a document
    func saveSummary(documentPath: String, summary: String)

    /// Deletes the summary for a document path
    func deleteSummary(for documentPath: String)
}

// MARK: - SwiftData Implementation

@MainActor
final class SwiftDataChatSummaryRepository: ChatSummaryRepository {

    private static let log = Logger(subsystem: "com.aimd.reader", category: "ChatSummaryRepo")
    private static let maxSummaries = 50

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func getSummary(for documentPath: String) -> ChatSummary? {
        let descriptor = FetchDescriptor<ChatSummary>(
            predicate: #Predicate { $0.documentPath == documentPath }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Self.log.error("Failed to fetch summary: \(error.localizedDescription)")
            return nil
        }
    }

    func saveSummary(documentPath: String, summary: String) {
        if let existing = getSummary(for: documentPath) {
            existing.summary = summary
            existing.lastUpdated = .now
        } else {
            let record = ChatSummary(
                documentPath: documentPath,
                documentName: "",
                summary: summary
            )
            modelContext.insert(record)
        }
        saveContext()
        evictIfNeeded()
    }

    func deleteSummary(for documentPath: String) {
        guard let existing = getSummary(for: documentPath) else { return }
        modelContext.delete(existing)
        saveContext()
    }

    // MARK: - Private

    private func evictIfNeeded() {
        let descriptor = FetchDescriptor<ChatSummary>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            if all.count > Self.maxSummaries {
                let toDelete = all.dropFirst(Self.maxSummaries)
                for record in toDelete {
                    modelContext.delete(record)
                }
                saveContext()
                Self.log.info("Evicted \(toDelete.count) old summaries")
            }
        } catch {
            Self.log.error("Failed to evict summaries: \(error.localizedDescription)")
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            Self.log.error("Failed to save context: \(error.localizedDescription)")
        }
    }
}
