import AppKit

/// TextKit 2 line-number gutter for the engine's NSTextView (G4-P4, US-P4.1/2).
///
/// A floating overlay (via `NSScrollView.addFloatingSubview`), NOT an
/// `NSRulerView`: the ruler's space reservation is unreliable inside the app's
/// nested split view (it worked in a plain window but not in the browser). The
/// editor reserves the strip via `MarkdownEditorConfiguration.leftContentInset`
/// and this view floats in it, redrawing line numbers as the content scrolls.
///
/// Line Y positions come from `textLayoutManager` fragments (one per source
/// line); the old ruler used TextKit 1 `layoutManager`, which the engine lacks.
final class PixleyGutterView: NSView {

    /// Width of the gutter strip; the editor reserves this much on the left via
    /// `leftContentInset` so text never overlaps the numbers.
    static let width: CGFloat = 44

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?

    var bookmarkedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var commentedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var onToggleBookmark: ((Int) -> Void)?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: scrollView.contentView.bounds.height))
        setAccessibilityElement(false) // decorative
        wantsLayer = false

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refresh),
                           name: NSText.didChangeNotification, object: textView)
        center.addObserver(self, selector: #selector(refresh),
                           name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        center.addObserver(self, selector: #selector(refresh),
                           name: NSView.frameDidChangeNotification, object: scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var isFlipped: Bool { true }

    @objc private func refresh() {
        if let clipHeight = scrollView?.contentView.bounds.height, abs(frame.height - clipHeight) > 0.5 {
            setFrameSize(NSSize(width: Self.width, height: clipHeight))
        }
        needsDisplay = true
    }

    // MARK: - Fragment → line-number geometry (TextKit 2)

    /// Calls `body` with (line number, top-Y in THIS view's coords, height) for
    /// each source line whose fragment is in the visible band.
    private func enumerateVisibleLines(_ body: (Int, CGFloat, CGFloat) -> Void) {
        guard let textView, let tlm = textView.textLayoutManager,
              let tcs = tlm.textContentManager else { return }
        let full = textView.string as NSString
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin

        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let topInView = frame.minY + origin.y
            let bottomInView = frame.maxY + origin.y
            if bottomInView < visible.minY { return true }
            if topInView > visible.maxY { return false }

            let startOffset = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
            var line = 1
            if startOffset > 0 {
                full.enumerateSubstrings(in: NSRange(location: 0, length: startOffset),
                                         options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
            }
            // Fragment top in text-view coords → this floating view's coords.
            let pTop = self.convert(NSPoint(x: 0, y: topInView), from: textView)
            body(line, pTop.y, frame.height)
            return true
        }
    }

    /// Line numbers currently visible (for smoke tests).
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
        if let hitLine { onToggleBookmark?(hitLine) }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
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
            str.draw(at: NSPoint(x: Self.width - size.width - 8, y: y + (height - size.height) / 2),
                     withAttributes: attrs)
        }
    }
}

/// Owns a gutter overlay for one editor and keeps its data current. Held by the
/// SwiftUI layer across updates; the view floats on the scroll view.
@MainActor
final class GutterController {
    private var gutter: PixleyGutterView?
    private weak var installedScrollView: NSScrollView?
    private var progressObserver: (any NSObjectProtocol)?
    /// Reading progress (0…1) as the reader scrolls (US-P4.2).
    var onProgress: ((Double) -> Void)?
    // Retained so a re-parent onto a new scroll view keeps the indicators.
    private var bookmarked: Set<Int> = []
    private var commented: Set<Int> = []

    /// SwiftUI can build the editor's NSView more than once (a throwaway pass at
    /// 0×0, then the live one), so `onScrollViewReady` fires per scroll view.
    /// Re-parent the gutter onto whichever scroll view is current instead of
    /// pinning to the first — that first one is often 0-sized and discarded.
    func install(on scrollView: NSScrollView, textView: NSTextView,
                 onToggleBookmark: @escaping (Int) -> Void) {
        if installedScrollView === scrollView, gutter != nil {
            forceRefreshSoon(); return
        }
        // Tear down any prior gutter (stale scroll view).
        gutter?.removeFromSuperview()
        if let progressObserver { NotificationCenter.default.removeObserver(progressObserver) }

        let view = PixleyGutterView(scrollView: scrollView, textView: textView)
        view.onToggleBookmark = onToggleBookmark
        view.bookmarkedLines = bookmarked
        view.commentedLines = commented
        view.frame = NSRect(x: 0, y: 0, width: PixleyGutterView.width,
                            height: max(1, scrollView.contentView.bounds.height))
        // Floating for the vertical axis: pinned to the viewport's left edge
        // while the document scrolls beneath it.
        scrollView.addFloatingSubview(view, for: .vertical)
        gutter = view
        installedScrollView = scrollView

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
        // The scroll view is usually 0×0 at makeNSView time; catch up once
        // SwiftUI has laid it out.
        forceRefreshSoon()
    }

    /// Resize + redraw the gutter after the scroll view lays out. Retries a few
    /// runloop turns because the split-view sizing can lag makeNSView.
    private func forceRefreshSoon(_ attempt: Int = 0) {
        guard attempt < 6 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let g = self.gutter, let sv = self.installedScrollView else { return }
            let h = sv.contentView.bounds.height
            if h > 1 { g.setFrameSize(NSSize(width: PixleyGutterView.width, height: h)) }
            g.needsDisplay = true
            if h <= 1 || g.visibleLineNumbers().isEmpty { self.forceRefreshSoon(attempt + 1) }
        }
    }

    func update(bookmarked: Set<Int>, commented: Set<Int>) {
        self.bookmarked = bookmarked
        self.commented = commented
        gutter?.bookmarkedLines = bookmarked
        gutter?.commentedLines = commented
    }

    /// Smoke-test hook: the line numbers the gutter currently lays out.
    func visibleLineNumbers() -> [Int] { gutter?.visibleLineNumbers() ?? [] }
}
