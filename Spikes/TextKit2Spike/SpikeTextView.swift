import AppKit
import SwiftUI

/// TextKit 2 NSTextView wrapped for SwiftUI. Storage is the projection of
/// `document.source`; typing serializes back to the model on every change;
/// external model changes (reload) rebuild the projection.
struct SpikeTextView: NSViewRepresentable {
    let document: SpikeDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        precondition(textView.textLayoutManager != nil, "Spike requires TextKit 2")

        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = SpikeProjection.bodyFont
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true

        context.coordinator.textView = textView
        context.coordinator.applyProjection()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.syncFromModelIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let document: SpikeDocument
        weak var textView: NSTextView?
        /// Model revision the storage currently reflects; used to detect
        /// external changes (reload) vs our own serialize-backs.
        private var appliedRevision: Int = -1
        private var isApplyingProjection = false

        init(document: SpikeDocument) {
            self.document = document
        }

        /// Rebuild storage from the model (initial load + external changes).
        func applyProjection() {
            guard let textView, let storage = textView.textStorage else { return }
            isApplyingProjection = true
            let projected = SpikeProjection.buildStorage(source: document.source) { [weak self] _ in
                self?.checkboxToggled()
            }
            storage.setAttributedString(projected)
            appliedRevision = document.revision
            isApplyingProjection = false
        }

        func syncFromModelIfNeeded() {
            guard document.revision != appliedRevision else { return }
            applyProjection()
        }

        /// Typing path: serialize the projection back into the model.
        func textDidChange(_ notification: Notification) {
            guard !isApplyingProjection, let storage = textView?.textStorage else { return }
            let serialized = SpikeProjection.serialize(storage: storage)
            document.update(source: serialized)
            appliedRevision = document.revision
        }

        private func checkboxToggled() {
            guard let storage = textView?.textStorage else { return }
            let serialized = SpikeProjection.serialize(storage: storage)
            document.update(source: serialized)
            appliedRevision = document.revision
            try? document.save()
        }

        // MARK: - Typora Reveal (US-0.2)

        /// Content range (marker-free coordinates) of the currently revealed
        /// bold run; markers occupy [location-2, 2] and [location+length, 2].
        private var revealedContentRange: NSRange?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProjection, let textView, let storage = textView.textStorage else { return }
            let caret = textView.selectedRange().location

            if let revealed = revealedContentRange {
                let full = NSRange(location: revealed.location - 2, length: revealed.length + 4)
                if caret >= full.location && caret <= full.location + full.length {
                    return // still inside the revealed region
                }
                unreveal(storage: storage, textView: textView)
            }

            // Find a hidden-marker bold run at (or immediately left of) the caret
            var runRange = NSRange(location: NSNotFound, length: 0)
            var hit = false
            if caret < storage.length,
               storage.attribute(SpikeProjection.spikeBold, at: caret, longestEffectiveRange: &runRange, in: NSRange(location: 0, length: storage.length)) != nil {
                hit = true
            } else if caret > 0,
                      storage.attribute(SpikeProjection.spikeBold, at: caret - 1, longestEffectiveRange: &runRange, in: NSRange(location: 0, length: storage.length)) != nil {
                hit = true
            }
            if hit {
                reveal(runRange, storage: storage, textView: textView)
            }
        }

        private func reveal(_ runRange: NSRange, storage: NSTextStorage, textView: NSTextView) {
            isApplyingProjection = true
            defer { isApplyingProjection = false }

            let caret = textView.selectedRange().location
            let markerAttrs: [NSAttributedString.Key: Any] = [
                .font: SpikeProjection.bodyFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                SpikeProjection.spikeMarker: true,
            ]

            storage.beginEditing()
            // Content loses the mapping attribute while revealed (markers are literal)
            storage.removeAttribute(SpikeProjection.spikeBold, range: runRange)
            storage.insert(NSAttributedString(string: "**", attributes: markerAttrs), at: runRange.location + runRange.length)
            storage.insert(NSAttributedString(string: "**", attributes: markerAttrs), at: runRange.location)
            storage.endEditing()

            revealedContentRange = NSRange(location: runRange.location + 2, length: runRange.length)
            let newCaret = caret >= runRange.location ? caret + 2 : caret
            textView.setSelectedRange(NSRange(location: min(newCaret, storage.length), length: 0))
        }

        private func unreveal(storage: NSTextStorage, textView: NSTextView) {
            guard let revealed = revealedContentRange else { return }
            revealedContentRange = nil
            isApplyingProjection = true
            defer { isApplyingProjection = false }

            let full = NSRange(location: revealed.location - 2, length: revealed.length + 4)
            guard full.location >= 0, full.location + full.length <= storage.length else { return }
            let literal = (storage.string as NSString).substring(with: full)

            // Re-project the literal region: if it still parses as **bold**,
            // restore the hidden-marker styled run; otherwise leave the text
            // as the user made it (serialize passes it verbatim).
            let caret = textView.selectedRange().location
            storage.beginEditing()
            storage.replaceCharacters(in: full, with: SpikeProjection.styledLine(literal))
            storage.endEditing()

            let delta = storage.length // recompute caret conservatively
            _ = delta
            let adjusted = caret > full.location + 2 ? max(full.location, caret - 4) : caret
            textView.setSelectedRange(NSRange(location: min(adjusted, storage.length), length: 0))
        }

        /// Track edits inside the revealed region so its bounds stay valid.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if var revealed = revealedContentRange {
                let delta = (replacementString?.utf16.count ?? 0) - affectedCharRange.length
                let full = NSRange(location: revealed.location - 2, length: revealed.length + 4)
                if affectedCharRange.location >= full.location,
                   affectedCharRange.location + affectedCharRange.length <= full.location + full.length {
                    revealed.length += delta
                    revealedContentRange = revealed.length >= 0 ? revealed : nil
                } else if affectedCharRange.location + affectedCharRange.length <= full.location {
                    revealed.location += delta
                    revealedContentRange = revealed
                } else {
                    // Edit overlaps the region boundary — drop reveal tracking;
                    // serialize stays correct because markers are literal text.
                    revealedContentRange = nil
                }
            }
            return true
        }
    }
}
