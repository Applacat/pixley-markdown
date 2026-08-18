import AppKit
import aimdRenderer
import MarkdownEngine

/// Maps Pixley's detected interactive elements onto the engine's generic
/// interactivity seam (G4-P3). Runs as the engine's `onInteractiveOverlay`
/// after every live-mode restyle: it re-detects elements in the current text
/// and re-asserts the `.interactiveGlyph` / `.interactiveZone` attributes the
/// engine's restyle just cleared.
///
/// The identifiers are opaque to the engine and parsed back by
/// ``PixleyElementRouter`` on click. Each anchors on the element's UTF-16
/// offset in the current text, which the overlay and the click share (both
/// read the same storage), so no relocation is needed at click time — the
/// InteractionHandler write path relocates against the model separately.
///
/// The core four are handled here. Checkbox stays engine-native (the engine
/// renders and toggles `- [ ]` list items itself). Review / feedback /
/// CriticMarkup stay inert until G5 (US-P3.4).
enum PixleyElementStyler {

    /// Choice radio glyphs: an empty ring, a filled ring when selected.
    static let unselectedSymbol = "circle"
    static let selectedSymbol = "circle.inset.filled"

    /// Applies interactive attributes for every element intersecting `range`.
    /// `storage.string` is the source (storage == source in this editor).
    ///
    /// Detection is windowed to the blank-line block enclosing `range` and the
    /// results offset back — a keystroke re-detects one block, not the whole
    /// document (the incremental restyle only rewrote that block's attributes,
    /// so elements outside it keep their overlay from the prior pass). The full
    /// rebuild passes the whole document as `range`, so the window is the doc.
    static func overlay(storage: NSTextStorage, range: NSRange) {
        let full = storage.string as NSString
        guard full.length > 0 else { return }
        let window = enclosingBlockRange(for: range, in: full)
        let slice = full.substring(with: window)
        let elements = InteractiveElementDetector.detect(in: slice)
        let base = window.location

        for element in elements {
            switch element {
            case .choice(let choice):
                styleChoice(choice, in: slice, storage: storage, base: base)
            case .status(let status):
                styleStatus(status, in: slice, storage: storage, base: base)
            case .fillIn(let fillIn):
                styleFillIn(fillIn, in: slice, storage: storage, base: base)
            default:
                break // checkbox = engine-native; others inert until G5
            }
        }
    }

    /// Expands `range` to the surrounding blank-line-delimited block, so a
    /// windowed detect still sees multi-line elements (e.g. a status label and
    /// its `<!-- states -->` comment on the line above). A `range` that already
    /// spans the document returns the document.
    private static func enclosingBlockRange(for range: NSRange, in text: NSString) -> NSRange {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        let seed = clamped.length > 0 ? clamped : NSRange(location: min(range.location, text.length), length: 0)
        var start = text.lineRange(for: NSRange(location: seed.location, length: 0)).location
        var end = NSMaxRange(text.lineRange(for: NSRange(location: min(NSMaxRange(seed), text.length), length: 0)))
        // Walk backward over non-blank lines.
        while start > 0 {
            let prev = text.lineRange(for: NSRange(location: start - 1, length: 0))
            if text.substring(with: prev).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            start = prev.location
        }
        // Walk forward over non-blank lines.
        while end < text.length {
            let next = text.lineRange(for: NSRange(location: end, length: 0))
            if text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: end - start)
    }

    // MARK: - Choice (radio)

    private static func styleChoice(_ choice: ChoiceElement, in slice: String,
                                    storage: NSTextStorage, base: Int) {
        let storageLength = storage.length
        for (index, option) in choice.options.enumerated() {
            let checkNS = NSRange(option.checkRange, in: slice)
            guard checkNS.location != NSNotFound, base + checkNS.location >= 1 else { continue }
            // The full `[ ]` span in document coordinates: one char before the
            // inner char through one after.
            let bracketNS = NSRange(location: base + checkNS.location - 1, length: checkNS.length + 2)
            guard NSMaxRange(bracketNS) <= storageLength else { continue }

            // Identifier anchors on the blockquote's DOCUMENT offset.
            let blockLoc = base + NSRange(choice.blockquoteRange, in: slice).location
            let glyph = InteractiveGlyph(
                symbolName: option.isSelected ? selectedSymbol : unselectedSymbol,
                filled: option.isSelected,
                identifier: "choice:\(blockLoc):\(index)")
            storage.addAttribute(.interactiveGlyph, value: glyph, range: bracketNS)
            // Hide the `[ ]` source glyphs so only the ring shows.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: bracketNS)
        }
    }

    // MARK: - Status (chip)

    private static func styleStatus(_ status: StatusElement, in slice: String,
                                    storage: NSTextStorage, base: Int) {
        let sliceLabel = NSRange(status.labelRange, in: slice)
        guard sliceLabel.location != NSNotFound else { return }
        let labelNS = NSRange(location: base + sliceLabel.location, length: sliceLabel.length)
        guard NSMaxRange(labelNS) <= storage.length else { return }
        storage.addAttribute(.interactiveZone, value: "status:\(labelNS.location)", range: labelNS)
        // A subtle chip: tinted background + accent ink signals "clickable".
        storage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.16), range: labelNS)
        storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: labelNS)
        // A trailing chevron so it reads as a native dropdown (D-F: styled
        // text, no attachment). Anchored on the label's last character.
        if labelNS.length > 0 {
            let lastChar = NSRange(location: NSMaxRange(labelNS) - 1, length: 1)
            storage.addAttribute(.interactiveAccessory, value: "chevron.down", range: lastChar)
        }
    }

    // MARK: - Fill-in (field)

    /// Storage-only prefixes the display must never show (`[[text: Jose]]`
    /// reads as "Jose", `[[date: 2026-07-09]]` as "2026-07-09").
    private static let typePrefixes = ["text:", "date:", "file:", "folder:"]
    /// Near-zero, clear-inked font that collapses hidden syntax to ~no advance.
    private static var hiddenFont: NSFont { NSFont.systemFont(ofSize: 0.01) }

    private static func styleFillIn(_ fillIn: FillInElement, in slice: String,
                                    storage: NSTextStorage, base: Int) {
        let sliceNS = NSRange(fillIn.range, in: slice)
        guard sliceNS.location != NSNotFound else { return }
        let ns = NSRange(location: base + sliceNS.location, length: sliceNS.length)
        let full = storage.string as NSString
        guard NSMaxRange(ns) <= full.length, ns.length > 4 else { return }

        // Interior between `[[` and `]]`.
        let openLen = 2, closeLen = 2
        let interiorStart = ns.location + openLen
        let interiorLen = ns.length - openLen - closeLen
        guard interiorLen > 0 else { return }
        let interior = full.substring(with: NSRange(location: interiorStart, length: interiorLen))

        // Skip the storage-only type prefix (ASCII, so char count == UTF-16 units).
        var valueOffset = 0
        let lower = interior.lowercased()
        for kw in typePrefixes where lower.hasPrefix(kw) {
            valueOffset = kw.count
            let chars = Array(interior)
            while valueOffset < chars.count, chars[valueOffset] == " " { valueOffset += 1 }
            break
        }

        // Hide `[[` + prefix and the trailing `]]` — display shows only the value.
        hide(NSRange(location: ns.location, length: openLen + valueOffset), in: storage)
        hide(NSRange(location: NSMaxRange(ns) - closeLen, length: closeLen), in: storage)

        // The visible value becomes the clickable field.
        let valueRange = NSRange(location: interiorStart + valueOffset,
                                 length: interiorLen - valueOffset)
        guard valueRange.length > 0 else { return }
        storage.addAttribute(.interactiveZone, value: "fillin:\(ns.location)", range: valueRange)
        storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.18), range: valueRange)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: valueRange)
        storage.addAttribute(.underlineColor, value: NSColor.systemOrange, range: valueRange)
    }

    /// Collapses a syntax range to ~zero advance with clear ink.
    private static func hide(_ range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.addAttribute(.font, value: hiddenFont, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
    }
}
