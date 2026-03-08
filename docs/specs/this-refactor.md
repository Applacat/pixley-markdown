# BRD: Liquid Glass Line Indicators

**Feature:** Replace NSRulerView gutter with Liquid Glass line indicators on infinite canvas
**Status:** PENDING
**Created:** 2026-03-08

---

## Problem Statement

The current `LineNumberRulerView` (NSRulerView subclass) has persistent layout bugs — `NSScrollView.tile()` fails to properly offset the clip view in SwiftUI `NSViewRepresentable`, causing text to render behind the gutter. Multiple patch attempts (scroll pinning, lineFragmentPadding, custom GutteredScrollView) haven't fully resolved the architectural mismatch. The gutter model (a component pinned to the edge of a container) also conflicts with the Liquid Glass infinite canvas aesthetic. Single-line bookmarks are too granular for AI-assisted reading workflows.

## Solution

Replace the NSRulerView-based gutter with:
1. **Infinite canvas** — NSTextView with no background, no left margin. Background owned by SwiftUI parent.
2. **Floating line numbers** — SwiftUI overlay positioned via shared `@Observable` line layout state from `NSLayoutManager`.
3. **Liquid Glass bookmark bubbles** — Range bookmarks visualized as glass bubbles behind line numbers. No bookmarks = no glass.
4. **Corner badge toggle** — Line count badge in the top-left corner (ruler intersection) serves as collapse/expand toggle.
5. **AI context integration** — Bookmarked sections auto-included in AI chat context; FM tool for programmatic access.

---

## Design Decisions

### D1: Infinite Canvas
- NSTextView: `drawsBackground = false`, zero left margin, no `textContainerInset.width`
- Line numbers are a SwiftUI overlay, not part of the text view or scroll view
- Background surface owned by SwiftUI parent (theme color or material)
- Eliminates all `tile()`, clip-view, and ruler layout issues by design

### D2: Line Indicator Positioning
- Shared `@Observable` `LineLayoutState` written by `MarkdownEditor.Coordinator`
- Contains visible line range and Y position for each visible line
- Updated on scroll (`boundsDidChange`) and layout changes (`textDidChange`)
- SwiftUI overlay reads positions to align indicators with text lines

### D3: Bookmark Visualization
- No bookmarks = just floating numbers on canvas, no glass
- Each bookmark range gets a Liquid Glass bubble behind its line numbers
- Overlapping or adjacent ranges auto-merge into a single bubble
- Deletion: hover a bookmarked line number reveals clickable delete state; click to remove

### D4: Collapse / Expand
- Top-left corner badge shows total line count (e.g. "147") in a glass capsule
- Click badge = collapse everything to a single dot
- Click dot = expand back to full line numbers + bookmark bubbles
- Spring animation for the morph transition
- Replaces the "Show Line Numbers" settings toggle entirely

### D5: Coordinate Anchor
- The line indicator column defines the text origin — canvas starts where indicators end
- Fixes the persistent left-margin clipping bug by design (no tile/clip-view math)
- When collapsed to dot, canvas extends to sidebar edge (no layout shift needed — canvas was always there)

### D6: Range Bookmarks
- Store `startLine` + `endLine` integers per bookmark
- Click a line number to bookmark a single line (`startLine == endLine`)
- Click-drag vertically to bookmark a range
- Overlapping ranges auto-merge
- Migrate existing single-line `Bookmark` model: each `lineNumber` becomes `startLine == endLine`

### D7: AI Integration
- Bookmarked sections auto-included in AI chat context as "user-flagged sections"
- New FM tool `getBookmarkedSections` lets AI query bookmark ranges and their content
- Range bookmarks give AI meaningful section-level context, not individual lines

---

## Scope

### In Scope
- Remove `LineNumberRulerView`, `GutteredScrollView`, all ruler setup in `MarkdownEditor`
- Transparent NSTextView (infinite canvas)
- SwiftUI floating line number overlay with `@Observable` bridge
- Liquid Glass bookmark bubbles (range visualization)
- Range bookmark data model (`startLine` + `endLine`), SwiftData migration from single-line model
- Click-drag range bookmark creation with auto-merge
- Hover-to-reveal delete interaction
- Corner line-count badge as collapse/expand toggle
- Animated spring morph between expanded and collapsed (dot) states
- AI chat auto-includes bookmarked sections
- FM tool `getBookmarkedSections`
- Remove "Show Line Numbers" setting (replaced by direct manipulation)

### Out of Scope
- Content-anchored bookmarks (fuzzy matching after external edits)
- Horizontal ruler
- Bookmark export/sharing
- Bookmark annotations/notes (existing `note` field stays but no UI for it)

---

## Technical Design

### Data Model Changes

**Current `Bookmark` model:**
```swift
@Model public final class Bookmark {
    public var id: UUID
    public var filePath: String
    public var lineNumber: Int
    public var note: String?
    public var createdAt: Date
}
```

**New `RangeBookmark` model:**
```swift
@Model public final class RangeBookmark {
    public var id: UUID
    public var filePath: String
    public var startLine: Int
    public var endLine: Int
    public var note: String?
    public var createdAt: Date
}
```

**Migration:** SwiftData `VersionedSchema` + `SchemaMigrationPlan`. Each existing `Bookmark(lineNumber: N)` becomes `RangeBookmark(startLine: N, endLine: N)`.

### New Types

**`LineLayoutState`** (`@Observable`):
```
- visibleLineRange: Range<Int>
- linePositions: [(lineNumber: Int, yOffset: CGFloat, height: CGFloat)]
- totalLineCount: Int
```
Written by `MarkdownEditor.Coordinator` on scroll/layout changes. Read by SwiftUI overlay.

**`LineIndicatorOverlay`** (SwiftUI View):
- Reads `LineLayoutState` to position indicators
- Renders line numbers at correct Y positions
- Renders Liquid Glass bubbles behind bookmarked ranges
- Renders corner badge (line count / dot)
- Handles click (bookmark toggle), click-drag (range creation), hover (delete reveal)

**`GetBookmarkedSectionsTool`** (FM Tool):
- Returns bookmarked line ranges and their text content for the current document
- Conforms to Foundation Models tool protocol (like existing `EditInteractiveElementsTool`)

### Files Changed

**Deleted:**
- `Sources/Views/Components/LineNumberRulerView.swift`

**Modified:**
- `Sources/MarkdownEditor.swift` — Remove `GutteredScrollView`, ruler setup, ruler-related code in `makeNSView`/`updateNSView`. NSTextView gets `drawsBackground = false`. Coordinator writes to `LineLayoutState`.
- `Sources/Persistence/Bookmark.swift` — Replace with `RangeBookmark` model
- `Sources/Persistence/FileMetadataRepository.swift` — Update protocol for range bookmarks (add, get, delete, merge)
- `Sources/Persistence/SwiftDataMetadataRepository.swift` — Update implementation + migration plan
- `Sources/Coordinator/AppCoordinator.swift` — Update bookmark methods for ranges, add merge logic
- `Sources/Views/Screens/MarkdownView.swift` — Replace `bookmarkedLines: Set<Int>` with range bookmark state, wire up `LineIndicatorOverlay`
- `Sources/Services/ChatService.swift` — Include bookmarked sections in AI context, add `GetBookmarkedSectionsTool`
- `Sources/Settings/SettingsRepository.swift` — Remove `showLineNumbers` setting (replaced by direct manipulation)

**New:**
- `Sources/Views/Components/LineIndicatorOverlay.swift` — SwiftUI overlay for line numbers + bookmark bubbles + corner badge
- `Sources/Models/LineLayoutState.swift` — Observable bridge between NSLayoutManager and SwiftUI

### Integration Points

- **MarkdownEditor.Coordinator** → writes `LineLayoutState` on every scroll/layout event
- **LineIndicatorOverlay** → reads `LineLayoutState`, reads bookmarks from coordinator
- **AppCoordinator** → owns range bookmark CRUD with auto-merge logic
- **ChatService** → reads bookmarks via coordinator, includes in AI session instructions
- **GetBookmarkedSectionsTool** → FM tool that reads bookmarks + extracts text content

### Detailed Implementation Guidance

#### US-1: What to remove from MarkdownEditor.swift

Delete the `GutteredScrollView` class (lines ~19-37 currently). In `makeNSView`:
- Replace `GutteredScrollView()` with plain `NSScrollView()`
- Delete `scrollView.hasVerticalRuler = true`
- Delete `LineNumberRulerView(...)` creation and all ruler property assignments
- Delete `scrollView.verticalRulerView = lineNumberView` and `scrollView.rulersVisible = ...`
- Set `textView.drawsBackground = false` (remove `textView.backgroundColor = ...`)
- Remove `configureInsets` static method — keep `lineFragmentPadding` for horizontal text padding but remove vertical `textContainerInset` reliance on ruler

In `updateNSView`:
- Remove ruler visibility toggle block (`scrollView.rulersVisible`, `scrollView.tile()`)
- Remove ruler bookmark updates (`ruler.bookmarkedLines`, `ruler.onToggleBookmark`)
- Remove `ruler.backgroundColor` updates
- Keep all text view, theme, and highlighting logic intact

Delete file: `Sources/Views/Components/LineNumberRulerView.swift`

#### US-1: SwiftUI background surface

In `MarkdownView.swift`, the existing `.background(.ultraThinMaterial)` on the ZStack serves as the infinite canvas surface. The NSTextView becomes transparent, so the material shows through. For theme-colored backgrounds, apply the theme's background color to the SwiftUI parent instead of the NSTextView:

```swift
// In markdownContent or enhancedContent:
.background(Color(nsColor: themeBackgroundColor))
```

#### US-2: LineLayoutState bridge details

The `LineLayoutState` Y offsets must be in the **scroll view's coordinate space** (not the text view's). Calculation in Coordinator:

```swift
func updateLinePositions(textView: NSTextView, scrollView: NSScrollView) {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else { return }

    let visibleRect = scrollView.contentView.bounds
    let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
    let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    let text = textView.string as NSString
    let inset = textView.textContainerInset

    var positions: [(lineNumber: Int, yOffset: CGFloat, height: CGFloat)] = []
    var lineNumber = 1

    // Count lines before visible range
    text.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                              options: [.byLines, .substringNotRequired]) { _, _, _, _ in
        lineNumber += 1
    }

    // Collect visible line positions
    text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
        let gi = layoutManager.glyphIndexForCharacter(at: lineRange.location)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
        // Convert from text container coords to scroll view visible coords
        let y = rect.origin.y + inset.height - visibleRect.origin.y
        positions.append((lineNumber: lineNumber, yOffset: y, height: rect.height))
        lineNumber += 1
    }

    lineLayoutState.linePositions = positions
    lineLayoutState.totalLineCount = /* count total lines in document */
}
```

Call this from `scrollViewDidScroll(_:)` and after `applyHighlighting`.

#### US-2: Debouncing strategy

Use a coalescing flag (like the existing `isUpdating` pattern) rather than time-based debouncing. Scroll events are already on the main thread. Avoid `DispatchQueue.main.async` delays — they cause visible lag between text and numbers.

#### US-3: Overlay placement in view hierarchy

`LineIndicatorOverlay` is an `overlay(alignment: .topLeading)` on the `MarkdownEditor` in `MarkdownView.enhancedContent`. It reads `LineLayoutState` from Environment or a binding:

```swift
MarkdownEditor(...)
    .overlay(alignment: .topLeading) {
        LineIndicatorOverlay(
            lineLayout: lineLayoutState,
            bookmarks: rangeBookmarks,
            isExpanded: $gutterExpanded,
            onBookmarkToggle: { startLine, endLine in ... },
            onBookmarkDelete: { bookmarkID in ... }
        )
    }
```

#### US-3: Indicator column width

Dynamic based on digit count: `max(28, CGFloat(String(totalLineCount).count) * 8 + 12)`. Minimum 28pt (1-digit), grows for 3+ digit line counts. The column width defines the canvas left edge (coordinate anchor from D5).

#### US-4: Corner badge position

The badge sits at `(0, 0)` of the overlay — top-left corner. When expanded, it shows the line count. When collapsed, it morphs to a small dot. Use `.matchedGeometryEffect` or `.animation(.spring)` for the morph.

#### US-5: SwiftData migration

Add `SchemaV3` to `SwiftDataMetadataRepository.swift`:

```swift
public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [FileMetadata.self, RangeBookmark.self, ChatSummary.self]
    }
}
```

Add migration stage V2→V3 (custom, not lightweight — transforms `Bookmark.lineNumber` to `RangeBookmark.startLine/endLine`). Update `MetadataMigrationPlan.schemas` and `.stages`.

#### US-5: Auto-merge algorithm

```
func mergeBookmarks(for filePath: String) {
    let all = getBookmarks(for: filePath).sorted(by: { $0.startLine < $1.startLine })
    var merged: [RangeBookmark] = []
    for bookmark in all {
        if let last = merged.last, bookmark.startLine <= last.endLine + 1 {
            // Overlapping or adjacent — extend the existing range
            last.endLine = max(last.endLine, bookmark.endLine)
            // Delete the absorbed bookmark
            delete(bookmark)
        } else {
            merged.append(bookmark)
        }
    }
}
```

Run merge after every add operation.

#### US-5: Repository protocol changes

```swift
protocol FileMetadataRepository {
    // ... existing ...
    func getRangeBookmarks(for url: URL) -> [RangeBookmark]
    func addRangeBookmark(for url: URL, startLine: Int, endLine: Int, note: String?) -> RangeBookmark
    func deleteRangeBookmark(_ id: UUID)
    func deleteAllRangeBookmarks(for url: URL)
}
```

#### US-6: Liquid Glass bubble rendering

Use `.glassEffect` modifier (macOS 26) on a `RoundedRectangle` behind each bookmark range. The bubble spans from the first bookmarked line's Y to the last bookmarked line's Y + height. Fall back to `.ultraThinMaterial` with rounded corners if `.glassEffect` is unavailable.

#### US-8: AI context format

In `ChatService.startSession`, append bookmarked sections to the instructions string:

```
## User-Flagged Sections

The user has bookmarked the following sections of this document:

### Lines 5-12:
[extracted text content of lines 5-12]

### Lines 28-35:
[extracted text content of lines 28-35]
```

#### US-8: GetBookmarkedSectionsTool

Follow the pattern of `EditInteractiveElementsTool`. The tool returns bookmarked ranges with their text content as a `String` (conforms to `PromptRepresentable`). Register alongside `editTool` in `ChatService`:

```swift
session = LanguageModelSession(tools: [editTool, bookmarkTool], instructions: instructions)
```

### Existing Code Touch Points (grep reference)

`showLineNumbers` appears in:
- `SettingsRepository.swift:57` (property), `:265` (load), `:307` (save), `:354` (observe)
- `SettingsView.swift:149` (Toggle UI)
- `MarkdownEditor.swift:727, 850, 851` (ruler visibility)

`bookmarkedLines` appears in:
- `MarkdownEditor.swift:647` (property), `:724, :855` (ruler assignment)
- `MarkdownView.swift:26` (state), `:140, :142, :222, :227` (usage)
- `LineNumberRulerView.swift:16, :133` (drawing)

`Bookmark` model references:
- `AppCoordinator.swift:277-291` (add, get, delete methods)
- `FileMetadataRepository.swift:40-59` (protocol)
- `SwiftDataMetadataRepository.swift:98-136` (implementation)

### Accessibility

- Line numbers: `accessibilityLabel("Line \(number)")`, `accessibilityRole(.staticText)`
- Corner badge: `accessibilityLabel("Line count: \(total). Click to collapse line numbers")` / `accessibilityLabel("Line numbers collapsed. Click to expand")`
- Bookmark bubbles: `accessibilityLabel("Bookmark: lines \(start) to \(end)")`, `accessibilityRole(.button)` for delete interaction
- Announce state changes: `.accessibilityAnnouncement` on collapse/expand

### Working Tree Note

The current working tree has uncommitted changes from an earlier gutter fix session that added `GutteredScrollView` and `backgroundColor` to `LineNumberRulerView`. These changes are **superseded** by this spec — both additions will be deleted in US-1. Discard those changes before starting implementation.

---

## User Stories

### US-1: Infinite Canvas Foundation
**Description:** Remove NSRulerView and make the text view a transparent infinite canvas.

**Acceptance Criteria:**
- [ ] `LineNumberRulerView.swift` deleted
- [ ] `GutteredScrollView` class removed from `MarkdownEditor.swift`
- [ ] All ruler setup removed from `makeNSView` and `updateNSView`
- [ ] NSTextView has `drawsBackground = false`
- [ ] Background color comes from SwiftUI parent view
- [ ] Text renders without left-margin clipping on initial load and file switch
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### US-2: Line Layout Bridge
**Description:** Create shared `@Observable` `LineLayoutState` that bridges NSLayoutManager line positions to SwiftUI.

**Acceptance Criteria:**
- [ ] `LineLayoutState` model created with `visibleLineRange`, `linePositions`, `totalLineCount`
- [ ] `MarkdownEditor.Coordinator` writes to `LineLayoutState` on scroll and layout changes
- [ ] Line positions are accurate (Y offset matches actual text line positions in scroll view)
- [ ] Updates are debounced/coalesced to avoid excessive SwiftUI redraws during fast scrolling
- [ ] Build succeeds

### US-3: Floating Line Numbers
**Description:** SwiftUI overlay that renders line numbers positioned via `LineLayoutState`.

**Acceptance Criteria:**
- [ ] `LineIndicatorOverlay` view reads `LineLayoutState` and renders line numbers
- [ ] Numbers align vertically with their corresponding text lines (within 1pt)
- [ ] Numbers scroll in sync with text content (no visible lag)
- [ ] Line numbers use monospaced digit font, secondary label color (matching current style)
- [ ] No line numbers visible when document is empty or no file selected
- [ ] Build succeeds

### US-4: Corner Badge Toggle
**Description:** Line count badge in top-left corner that serves as collapse/expand toggle.

**Acceptance Criteria:**
- [ ] Corner badge shows total line count (e.g. "147") in a glass capsule
- [ ] Clicking badge collapses all line numbers to a single dot in the same position
- [ ] Clicking dot expands back to full line numbers
- [ ] Spring animation for expand/collapse transition
- [ ] Collapsed state persists per-window (not per-file)
- [ ] "Show Line Numbers" removed from Settings
- [ ] Build succeeds

### US-5: Range Bookmark Data Model
**Description:** Migrate from single-line `Bookmark` to range-based `RangeBookmark` with auto-merge.

**Acceptance Criteria:**
- [ ] `RangeBookmark` SwiftData model with `startLine`, `endLine`, `filePath`, `id`, `note`, `createdAt`
- [ ] SwiftData migration converts existing bookmarks (`lineNumber` → `startLine == endLine`)
- [ ] `FileMetadataRepository` protocol updated for range operations
- [ ] `AppCoordinator` bookmark methods updated (add range, get ranges, delete range)
- [ ] Auto-merge: adding a range that overlaps/adjoins an existing range merges them
- [ ] Package tests pass: `cd Packages/aimdRenderer && swift test`
- [ ] Build succeeds

### US-6: Bookmark Bubble Visualization
**Description:** Render Liquid Glass bubbles behind bookmarked line ranges.

**Acceptance Criteria:**
- [ ] Bookmarked ranges show a Liquid Glass bubble behind their line numbers
- [ ] No bookmarks = no glass (just floating numbers)
- [ ] Multiple non-adjacent bookmarks render as separate bubbles
- [ ] Merged/adjacent bookmarks render as a single bubble
- [ ] Bubble scrolls in sync with line numbers and text
- [ ] Build succeeds

### US-7: Bookmark Interaction (Create + Delete)
**Description:** Click-drag to create range bookmarks, hover-to-reveal delete.

**Acceptance Criteria:**
- [ ] Click a line number → creates single-line bookmark (startLine == endLine)
- [ ] Click-drag vertically across line numbers → creates range bookmark
- [ ] Overlapping new bookmark auto-merges with existing
- [ ] Hovering a bookmarked line number reveals delete affordance (visual state change)
- [ ] Clicking the revealed delete removes the bookmark (or the line from the range)
- [ ] Build succeeds

### US-8: AI Bookmark Context
**Description:** Auto-include bookmarked sections in AI chat context and add FM tool.

**Acceptance Criteria:**
- [ ] AI chat session instructions include bookmarked section text, marked as "user-flagged sections"
- [ ] `GetBookmarkedSectionsTool` FM tool returns bookmark ranges and their content
- [ ] Tool registered in `ChatService` session alongside existing `EditInteractiveElementsTool`
- [ ] AI can reference bookmarked sections in its responses
- [ ] Build succeeds

---

## Implementation Phases

### Phase 1: Foundation (US-1, US-2)
Remove NSRulerView, transparent canvas, line layout bridge.
- **Verification:** App builds. Text renders without clipping. No line numbers visible yet (overlay not built).

### Phase 2: Line Numbers + Toggle (US-3, US-4)
Floating line number overlay, corner badge collapse/expand.
- **Verification:** Line numbers visible and aligned. Corner badge toggles collapse/expand with animation.

### Phase 3: Range Bookmarks (US-5, US-6, US-7)
Data model migration, glass bubbles, interaction gestures.
- **Verification:** Range bookmarks persist. Glass bubbles render. Click-drag creates ranges. Auto-merge works.

### Phase 4: AI Integration (US-8)
Bookmark context in chat, FM tool.
- **Verification:** AI references bookmarked sections. FM tool returns correct content.

---

## Definition of Done

- [ ] All acceptance criteria in US-1 through US-8 pass
- [ ] All implementation phases verified
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- [ ] Package tests pass: `cd Packages/aimdRenderer && swift test`
- [ ] No regression in interactive element handling (checkboxes, choices, etc.)
- [ ] Text renders without left-margin clipping on initial load, file switch, and font change

---

## Ralph Loop Command

```bash
/ralph-loop "Implement Liquid Glass Line Indicators per spec at docs/specs/this-refactor.md

PHASES:
1. Foundation (US-1, US-2): Remove NSRulerView, transparent canvas, LineLayoutState bridge
2. Line Numbers + Toggle (US-3, US-4): SwiftUI overlay, corner badge, spring animation
3. Range Bookmarks (US-5, US-6, US-7): Data model migration, glass bubbles, click-drag interaction
4. AI Integration (US-8): Chat context, GetBookmarkedSectionsTool

VERIFICATION (run after each phase):
- xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build
- cd Packages/aimdRenderer && swift test

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```
