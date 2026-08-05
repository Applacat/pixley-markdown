import Foundation
import Observation

// MARK: - Markdown Document

/// The in-memory source of truth for an open markdown file (editor epic G1;
/// grown from the G0 spike's SpikeDocument).
///
/// Interactions and AI edits mutate this model; disk writes flow out through
/// the app's SaveCoordinator; external changes flow in through reload sync.
/// The G2+ editor makes views render from this model directly — in G1 it
/// shadows the displayed content so the interaction path never reads disk.
@MainActor
@Observable
public final class MarkdownDocument {

    public let url: URL
    public private(set) var source: String
    /// Bumped on every mutation; consumers detect external changes cheaply.
    public private(set) var revision: Int = 0
    /// Hash of the last content known to be on disk (saved or loaded) —
    /// the baseline for conflict detection (G3).
    public private(set) var baselineHash: Int
    /// The last content known to be on disk — the 3-way merge base (G3).
    public private(set) var baselineContent: String

    public init(url: URL, source: String) {
        self.url = url
        self.source = source
        self.baselineHash = source.hashValue
        self.baselineContent = source
    }

    /// A local mutation (interaction, keystroke, AI edit).
    public func update(source newSource: String) {
        guard newSource != source else { return }
        source = newSource
        revision += 1
    }

    /// Content confirmed on disk (after save, or after loading fresh disk
    /// state) — resets the conflict baseline.
    public func syncToDisk(content: String) {
        if content != source {
            source = content
            revision += 1
        }
        baselineHash = content.hashValue
        baselineContent = content
    }

    /// A clean 3-way merge landed (G3): `merged` becomes the model text and
    /// `diskBaseline` (what's actually on disk right now) becomes the merge
    /// base, leaving the document dirty until the merged text is saved.
    public func applyMerge(merged: String, diskBaseline: String) {
        if merged != source {
            source = merged
            revision += 1
        }
        baselineHash = diskBaseline.hashValue
        baselineContent = diskBaseline
    }

    /// Disk caught up with the model without a content change (e.g. our own
    /// write settled) — just move the merge base forward.
    public func rebaseline(to content: String) {
        baselineHash = content.hashValue
        baselineContent = content
    }

    public var isDirty: Bool {
        source.hashValue != baselineHash
    }
}

// MARK: - Registry

/// Per-URL registry of live documents. Interactions obtain the model here so
/// every writer (UI controls, AI chat, future editor) mutates the same
/// instance. Documents are created on first touch and synced by the view
/// layer's load/reload path.
@MainActor
public enum MarkdownDocumentRegistry {

    private static var documents: [String: MarkdownDocument] = [:]

    /// The live document for a URL, created from `initialSource` on first touch.
    public static func obtain(url: URL, initialSource: String) -> MarkdownDocument {
        if let existing = documents[url.path] {
            return existing
        }
        let document = MarkdownDocument(url: url, source: initialSource)
        documents[url.path] = document
        return document
    }

    /// The view layer's load/reload path confirmed fresh disk content —
    /// sync the model (creating it if needed) so interactions see it.
    public static func syncFromDisk(url: URL, content: String) {
        if let existing = documents[url.path] {
            existing.syncToDisk(content: content)
        } else {
            documents[url.path] = MarkdownDocument(url: url, source: content)
        }
    }

    /// The live document for a URL if one exists — no creation. AI edit
    /// snapshots read this so they detect against current text (G3, US-3.2).
    public static func current(url: URL) -> MarkdownDocument? {
        documents[url.path]
    }

    /// Drop a document (file closed/deselected); a later touch recreates it.
    public static func release(url: URL) {
        documents[url.path] = nil
    }

    /// Test support.
    public static func _resetForTesting() {
        documents.removeAll()
    }
}
