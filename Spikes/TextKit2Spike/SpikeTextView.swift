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
    }
}
