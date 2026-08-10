import Foundation

// MARK: - External Change Arbiter

/// Decides what happens when the watched file changes under a live document
/// (editor epic G3): clean documents silently reload, dirty documents 3-way
/// merge against the disk baseline, and same-region clashes surface to the
/// user — external content never silently overwrites unsaved typing, and
/// unsaved typing never silently overwrites external content.
@MainActor
public enum ExternalChangeArbiter {

    public enum Outcome: Equatable {
        /// Disk now matches the model (e.g. our own write settled) — rebaselined.
        case noChange
        /// Document was clean; the model now mirrors disk.
        case reloaded
        /// Document was dirty; disjoint edits auto-merged into the model
        /// (D7). The model is dirty against disk — the caller must save.
        case merged
        /// Same-region clash: the model is untouched, `theirs` is what's on
        /// disk. The caller must offer keep-mine / take-theirs.
        case clash(theirs: String)
    }

    public static func arbitrate(document: MarkdownDocument, diskContent: String) -> Outcome {
        if diskContent == document.source {
            document.rebaseline(to: diskContent)
            return .noChange
        }
        guard document.isDirty else {
            document.syncToDisk(content: diskContent)
            return .reloaded
        }
        switch ThreeWayMerge.merge(base: document.baselineContent,
                                   mine: document.source,
                                   theirs: diskContent) {
        case .merged(let merged):
            document.applyMerge(merged: merged, diskBaseline: diskContent)
            return .merged
        case .clash:
            // Hold every save until the user picks a side — an autosave or
            // ⌘S landing now would silently destroy theirs on disk.
            document.flagClash(theirs: diskContent)
            return .clash(theirs: diskContent)
        }
    }

    /// Clash resolution: keep the user's text. The external content becomes
    /// the baseline so the next save deliberately overwrites it.
    public static func keepMine(document: MarkdownDocument, theirs: String) {
        document.applyMerge(merged: document.source, diskBaseline: theirs)
    }

    /// Clash resolution: adopt the external content, dropping local edits.
    public static func takeTheirs(document: MarkdownDocument, theirs: String) {
        document.syncToDisk(content: theirs)
    }
}
