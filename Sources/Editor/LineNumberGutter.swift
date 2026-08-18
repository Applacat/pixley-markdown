import AppKit

/// TextKit 2 line-number gutter for the engine's NSTextView (G4-P4, US-P4.1/2).
/// The old ruler used TextKit 1 (`layoutManager`); this enumerates
/// `textLayoutManager` fragments — one fragment per source line — for Y
/// positions. Draws line numbers, a bookmark dot on bookmarked lines, and a
/// comment glyph on commented lines; a click toggles the line's bookmark.
final class PixleyGutterRulerView: NSRulerView {

    /// Width of the gutter strip; the editor reserves this much on the left
    /// via `MarkdownEditorConfiguration.leftContentInset` so text never
    /// overlaps the numbers.
    static let width: CGFloat = 44

    private weak var markdownTextView: NSTextView?

    var bookmarkedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var commentedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var onToggleBookmark: ((Int) -> Void)?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.markdownTextView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.width
        // Decorative — VoiceOver skips it (line numbers are visual context).
        setAccessibilityElement(false)
        setAccessibilityRole(.unknown)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refresh),
                           name: NSText.didChangeNotification, object: textView)
        center.addObserver(self, selector: #selector(refresh),
                           name: NSView.boundsDidChangeNotification,
                           object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() { needsDisplay = true }

    // MARK: - Fragment → line-number geometry (TextKit 2)

    /// Walks the visible fragments, calling `body` with (line number, the
    /// fragment's Y in this ruler's coordinates, its height).
    private func enumerateVisibleLines(_ body: (Int, CGFloat, CGFloat) -> Void) {
        guard let textView = markdownTextView,
              let tlm = textView.textLayoutManager,
              let tcs = tlm.textContentManager else { return }
        let full = textView.string as NSString
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin

        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame // text-container coords
            // Skip until the visible band; stop once past its bottom.
            let bottomInView = frame.maxY + origin.y
            let topInView = frame.minY + origin.y
            if bottomInView < visible.minY { return true }
            if topInView > visible.maxY { return false }

            // Line number = newlines before this fragment's start + 1.
            let startOffset = tcs.offset(from: tcs.documentRange.location,
                                         to: fragment.rangeInElement.location)
            var line = 1
            if startOffset > 0 {
                full.enumerateSubstrings(in: NSRange(location: 0, length: startOffset),
                                         options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
            }
            let pointInView = NSPoint(x: 0, y: frame.minY + origin.y)
            let yInRuler = self.convert(pointInView, from: textView).y
            body(line, yInRuler, frame.height)
            return true
        }
    }

    /// Line numbers currently visible in the gutter (for smoke tests).
    func visibleLineNumbers() -> [Int] {
        var lines: [Int] = []
        enumerateVisibleLines { line, _, _ in lines.append(line) }
        return lines
    }

    // MARK: - Click to toggle bookmark

    override func mouseDown(with event: NSEvent) {
        let clickY = convert(event.locationInWindow, from: nil).y
        var hitLine: Int?
        enumerateVisibleLines { line, y, height in
            if clickY >= y && clickY < y + height { hitLine = line }
        }
        if let hitLine { onToggleBookmark?(hitLine) } else { super.mouseDown(with: event) }
    }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        enumerateVisibleLines { line, y, height in
            let bookmarked = self.bookmarkedLines.contains(line)
            let commented = self.commentedLines.contains(line)

            if bookmarked {
                let dot = NSRect(x: 4, y: y + (height - 6) / 2, width: 6, height: 6)
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            if commented {
                let glyphRect = NSRect(x: 3, y: y + (height - 12) / 2, width: 12, height: 12)
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
                    .applying(.init(hierarchicalColor: .systemBlue))
                NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)?
                    .withSymbolConfiguration(cfg)?.draw(in: glyphRect)
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: bookmarked ? NSColor.systemOrange : NSColor.secondaryLabelColor,
            ]
            let str = "\(line)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: self.ruleThickness - size.width - 6,
                                 y: y + (height - size.height) / 2),
                     withAttributes: attrs)
        }
    }
}

/// Owns a gutter ruler for one editor and keeps its data current. Held by the
/// SwiftUI layer across updates; the ruler itself lives on the scroll view.
@MainActor
final class GutterController {
    private var ruler: PixleyGutterRulerView?
    private var progressObserver: (any NSObjectProtocol)?
    /// Reading progress (0…1) as the reader scrolls (US-P4.2).
    var onProgress: ((Double) -> Void)?

    func install(on scrollView: NSScrollView, textView: NSTextView,
                 onToggleBookmark: @escaping (Int) -> Void) {
        guard ruler == nil else { return }
        let ruler = PixleyGutterRulerView(scrollView: scrollView, textView: textView)
        ruler.onToggleBookmark = onToggleBookmark
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        // Enabling rulers after the initial tile doesn't re-reserve space on
        // its own — re-tile so the content view insets left of the gutter.
        scrollView.tile()
        self.ruler = ruler

        scrollView.contentView.postsBoundsChangedNotifications = true
        progressObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main
        ) { [weak scrollView, weak self] _ in
            guard let scrollView, let doc = scrollView.documentView else { return }
            let clip = scrollView.contentView.bounds
            let scrollable = max(1, doc.frame.height - clip.height)
            let fraction = max(0, min(1, clip.origin.y / scrollable))
            MainActor.assumeIsolated { self?.onProgress?(fraction) }
        }
    }

    func update(bookmarked: Set<Int>, commented: Set<Int>) {
        ruler?.bookmarkedLines = bookmarked
        ruler?.commentedLines = commented
    }

    /// Smoke-test hook: the line numbers the ruler currently lays out.
    func visibleLineNumbers() -> [Int] { ruler?.visibleLineNumbers() ?? [] }
}
