import AppKit
import SwiftUI

/// A checkbox interactive element embedded in the TextKit 2 storage as an
/// atomic attachment. The attachment knows its checked state and reports
/// toggles upward; the projection layer maps it back to `- [ ]` / `- [x]`
/// in the model source.
// @unchecked Sendable: state is only touched on the main thread (AppKit text
// system + SwiftUI toggle callbacks). Spike-grade; G4 formalizes this.
final class CheckboxAttachment: NSTextAttachment, @unchecked Sendable {
    var isChecked: Bool
    var label: String
    var onToggle: ((CheckboxAttachment) -> Void)?

    init(isChecked: Bool, label: String) {
        self.isChecked = isChecked
        self.label = label
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewProvider(
        for parentView: NSView?,
        location: NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = CheckboxAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

// @unchecked Sendable: the text system drives this on the main thread only.
final class CheckboxAttachmentViewProvider: NSTextAttachmentViewProvider, @unchecked Sendable {
    override func loadView() {
        // Invoked by the text system on the main thread; the provider API is
        // not actor-annotated. Spike target runs Swift 5 mode — the Swift 6
        // isolation pattern for providers is a recorded G0 finding for G4.
        guard let attachment = textAttachment as? CheckboxAttachment else {
            view = NSView()
            return
        }
        let hosting = NSHostingView(rootView: CheckboxAttachmentView(attachment: attachment))
        hosting.sizingOptions = .intrinsicContentSize
        view = hosting
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let size = view?.intrinsicContentSize ?? CGSize(width: 120, height: 18)
        // Sit the control on the line's baseline rather than floating above it
        return CGRect(x: 0, y: -4, width: size.width, height: size.height)
    }
}

private struct CheckboxAttachmentView: View {
    let attachment: CheckboxAttachment
    @State private var isChecked: Bool

    init(attachment: CheckboxAttachment) {
        self.attachment = attachment
        self._isChecked = State(initialValue: attachment.isChecked)
    }

    var body: some View {
        Toggle(isOn: $isChecked) {
            Text(attachment.label)
        }
        .toggleStyle(.checkbox)
        .onChange(of: isChecked) { _, newValue in
            attachment.isChecked = newValue
            attachment.onToggle?(attachment)
        }
        .fixedSize()
    }
}
