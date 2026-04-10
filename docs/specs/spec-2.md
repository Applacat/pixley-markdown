# Spec 2 — Gutter, Line Numbers, Bookmarks & Scroll for NativeDocumentView

**Version:** 1.0
**Date:** 2026-04-09
**Status:** Spec
**Milestone:** v4: Native Renderer
**Depends on:** renderer-foundation.md (Spec 1)

---

## Overview

Add a gutter column with source-file line numbers, bookmark toggles, Cmd+G scroll-to-line, Cmd+B bookmark shortcut, reading progress tracking, and per-file bookmark persistence to the NativeDocumentView (Enhanced mode).

## Problem Statement

The NativeDocumentView (Phase 4 of renderer-foundation) ships with stub APIs for gutter, bookmarks, and scroll position. Enhanced mode currently shows no line numbers, no bookmarks, and 0% reading progress. Plain mode has all of these via GutterOverlayView. This spec brings Enhanced mode to parity and adds SwiftData persistence.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Gutter architecture | **SwiftUI overlay column** | `HStack { GutterView \| ScrollView }`. OOD: gutter is a separate concern, independently testable. |
| Line numbering | **Source-file line numbers** | Match .md file lines, not block indices. Users cross-reference with editors. |
| Line tracking | **Add startLine/endLine to MarkdownBlock** | Parser calculates during parsing. Self-contained, no parallel data structures. |
| Code block line numbers | **Self-contained inside code block view** | Code block renders its own leading line-number column. External gutter shows block's starting line. |
| Height estimation | **Hybrid: estimate then correct** | Start with per-line estimates, measure actual via onGeometryChange, cache. |
| Bookmark interaction | **Click gutter → toggle** | No popover, no context menu. Same as Plain mode. |
| Bookmark persistence | **SwiftData per-file** | Stored in FileMetadata. Best-effort line shift on external edits. |
| Gutter visibility | **Always visible in Enhanced** | Plain mode respects settings.rendering.showLineNumbers. Enhanced always shows gutter. |
| Gutter style | **Same palette style as Plain** | palette.lineNumber for numbers, palette.background for bg. Bookmark uses palette.keyword. |
| Gutter width | **Fixed 44pt** | Same as Plain mode. Works for files up to ~9999 lines. |
| Scroll-to-line | **Cmd+G dialog** | Standard "Go to Line" dialog. User types line number, view scrolls. |
| Bookmark shortcut | **Cmd+B** | Toggles bookmark at current scroll position (nearest block's start line). |
| Reading progress | **Feed existing badge** | Wire scroll offset into ReadingProgressBadge. No UI redesign. |
| Stale bookmarks | **Best-effort shift** | On content change, adjust bookmark line numbers by counting inserted/deleted lines above each bookmark. |

---

## Scope

### In Scope

- Gutter column (SwiftUI) in NativeDocumentView with source-file line numbers
- `startLine` and `endLine` properties on MarkdownBlock, calculated by parser
- Code block self-contained line numbers (leading column inside code block view)
- Hybrid height estimation (estimate → measure → cache) for gutter alignment
- Bookmark toggle via gutter click
- Bookmark persistence in SwiftData FileMetadata
- Best-effort bookmark line shift on external file edits
- Cmd+G "Go to Line" dialog with scroll-to-line
- Cmd+B bookmark toggle at current scroll position
- Reading progress (0–1.0) from ScrollView offset → ReadingProgressBadge
- Scroll position save/restore via coordinator

### Out of Scope

- Gutter annotations (comments, line indicators) — Spec 4
- "Add Comment" from gutter — Spec 4
- Bookmark context menu (jump, remove, notes) — future
- Keyboard navigation between bookmarks (Cmd+Shift+B next/prev) — future
- Gutter in Plain mode changes — no changes to existing GutterOverlayView

---

## User Stories

### US-1: Add startLine/endLine to MarkdownBlock and Parser

**Description:** As a developer, I want each MarkdownBlock to know its source line range so the gutter can display accurate line numbers.

**Acceptance Criteria:**
- [ ] `MarkdownBlock` has `startLine: Int` and `endLine: Int` properties
- [ ] `MarkdownBlockParser.parseFlat()` populates startLine/endLine by tracking line offsets during parsing
- [ ] Headings, paragraphs, code blocks, lists, tables, blockquotes, images, horizontal rules all have correct line ranges
- [ ] Interactive elements inherit the line range of their source markdown
- [ ] Unit test: parse a known document → verify startLine/endLine match expected values
- [ ] `swift build` succeeds

### US-2: Gutter Column View

**Description:** As a user in Enhanced mode, I want to see source-file line numbers next to the document content.

**Acceptance Criteria:**
- [ ] NativeDocumentView layout is `HStack { GutterView(width: 44) | ScrollView { content } }`
- [ ] GutterView shows the starting source line number for each block, aligned to the block's vertical position
- [ ] Line numbers use `palette.lineNumber` color, monospaced digit font
- [ ] Gutter background uses `palette.background` (consistent with content)
- [ ] Gutter is always visible in Enhanced mode (ignores `showLineNumbers` setting)
- [ ] GutterView scroll syncs with content scroll (same scroll offset)
- [ ] Empty documents show no line numbers

### US-3: Hybrid Height Estimation

**Description:** As a user scrolling through a long document, I want gutter line numbers to accurately align with their blocks.

**Acceptance Criteria:**
- [ ] Initial render uses estimated heights: `fontSize * 1.3 * sourceLineCount` per block
- [ ] As blocks become visible, `onGeometryChange` measures actual rendered height
- [ ] Measured heights cached in `[blockID: CGFloat]` dictionary
- [ ] Gutter re-renders when cached heights update
- [ ] For a 500-line document, gutter alignment is within 2px of content after scrolling through once
- [ ] No visible jitter/jump when cached heights replace estimates

### US-4: Code Block Internal Line Numbers

**Description:** As a user viewing code blocks, I want to see line numbers for every source line inside the code block.

**Acceptance Criteria:**
- [ ] Code block view (in ContentBlockView) renders a leading line-number column
- [ ] Line numbers start from the code block's `startLine` (offset by the ``` fence line)
- [ ] Line numbers use `palette.lineNumber` color, smaller font (caption size)
- [ ] Line numbers column is 28pt wide inside the code block
- [ ] External gutter shows the block's starting line as usual

### US-5: Bookmark Toggle

**Description:** As a user, I want to click a line number in the gutter to toggle a bookmark.

**Acceptance Criteria:**
- [ ] Clicking a gutter line number toggles a bookmark at that line
- [ ] Bookmarked lines show a colored indicator (circle/dot) using `palette.keyword` color
- [ ] Bookmark state stored as `Set<Int>` of line numbers
- [ ] Toggling a bookmark is instant (no animation delay)
- [ ] Bookmark indicator is visible at all zoom levels

### US-6: Cmd+B Bookmark Shortcut

**Description:** As a user, I want to press Cmd+B to toggle a bookmark at my current scroll position.

**Acceptance Criteria:**
- [ ] Cmd+B toggles a bookmark at the nearest visible block's start line
- [ ] "Nearest visible" = the block whose top edge is closest to the viewport's top
- [ ] Bookmark indicator updates immediately in the gutter
- [ ] Works when focus is on the NativeDocumentView (not chat or sidebar)

### US-7: Bookmark Persistence in SwiftData

**Description:** As a user, I want my bookmarks to survive app restart.

**Acceptance Criteria:**
- [ ] FileMetadata model has a `bookmarkedLines: [Int]` property (or new Bookmark model)
- [ ] Bookmarks saved to SwiftData when toggled
- [ ] Bookmarks restored from SwiftData when file is opened
- [ ] When file content changes externally, best-effort line shift applied:
  - Count lines inserted/deleted above each bookmark
  - Adjust bookmark line numbers accordingly
  - If a bookmarked line is deleted, remove that bookmark
- [ ] Schema migration handles the new property without data loss

### US-8: Cmd+G Go to Line

**Description:** As a user, I want to press Cmd+G to jump to a specific line number.

**Acceptance Criteria:**
- [ ] Cmd+G shows a small text field overlay (like Xcode's "Go to Line")
- [ ] User types a line number and presses Enter → ScrollView scrolls to that line's block
- [ ] Escape or clicking outside dismisses the dialog
- [ ] Invalid input (non-numeric, out of range) shows inline error or does nothing
- [ ] Scroll animation is smooth (withAnimation spring)
- [ ] After jump, the target block is positioned near the top of the viewport

### US-9: Reading Progress from Scroll Position

**Description:** As a user, I want the reading progress badge to show my actual scroll position in Enhanced mode.

**Acceptance Criteria:**
- [ ] NativeDocumentView reports scroll offset as 0.0–1.0 progress value
- [ ] Progress = scrollOffset / (totalContentHeight - viewportHeight), clamped to 0–1
- [ ] ReadingProgressBadge displays the live progress (no longer hardcoded 0%)
- [ ] Progress updates on scroll, not on timer
- [ ] Coordinator saves scroll position per-file (for restore on re-open)

### US-10: Scroll Position Save/Restore

**Description:** As a user switching between files, I want to return to my previous scroll position.

**Acceptance Criteria:**
- [ ] When switching away from a file, current scroll offset saved in coordinator
- [ ] When switching back, scroll position restored
- [ ] Restore happens after content is loaded and layout is complete
- [ ] If file content changed (different line count), scroll position clamped to valid range

---

## Implementation Phases

### Phase 1: Block Line Tracking + Gutter Layout

- [ ] Add `startLine` and `endLine` to MarkdownBlock
- [ ] Update MarkdownBlockParser.parseFlat() to calculate line ranges
- [ ] Create GutterView SwiftUI component
- [ ] Wire HStack layout in NativeDocumentView
- [ ] Implement hybrid height estimation with onGeometryChange caching
- [ ] Unit tests for line range parsing
- **Verification:** `cd AIMDReader && swift build && swift test`

### Phase 2: Code Block Line Numbers + Bookmarks

- [ ] Add internal line-number column to code block view
- [ ] Implement bookmark toggle on gutter click
- [ ] Add Cmd+B keyboard shortcut
- [ ] Bookmark state flows through coordinator
- [ ] Visual bookmark indicator in gutter
- **Verification:** `swift build` + manual: open a markdown file with code blocks, verify line numbers, toggle bookmarks

### Phase 3: Persistence + Scroll

- [ ] Add bookmarkedLines to FileMetadata (SwiftData schema migration)
- [ ] Implement bookmark save/restore lifecycle
- [ ] Implement best-effort bookmark line shift on content change
- [ ] Implement Cmd+G "Go to Line" dialog
- [ ] Wire scroll offset → reading progress badge
- [ ] Implement scroll position save/restore per-file
- **Verification:** `swift build && swift test` + manual: toggle bookmarks, restart app, verify they persist. Cmd+G to jump. Check reading progress badge updates on scroll.

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-10 pass
- [ ] All implementation phases verified
- [ ] Tests pass: `cd AIMDReader && swift test`
- [ ] Build succeeds: `cd AIMDReader && swift build`
- [ ] Enhanced mode shows gutter with source-file line numbers
- [ ] Code blocks show internal line numbers
- [ ] Bookmarks toggle on click and persist across restarts
- [ ] Cmd+G scrolls to specified line
- [ ] Cmd+B toggles bookmark at current position
- [ ] Reading progress badge shows actual scroll position
- [ ] Scroll position restores when switching files

---

## Technical Notes

### Files Created
- `Sources/Views/NativeRenderer/GutterView.swift` — SwiftUI gutter column
- `Sources/Views/NativeRenderer/GoToLineOverlay.swift` — Cmd+G dialog

### Files Modified
- `Sources/Views/NativeRenderer/MarkdownBlock.swift` — add startLine/endLine
- `Sources/Views/NativeRenderer/NativeDocumentView.swift` — HStack layout, scroll tracking, keyboard shortcuts
- `Sources/Views/NativeRenderer/ContentBlockView.swift` — code block internal line numbers
- `Sources/Persistence/FileMetadata.swift` — bookmarkedLines property, schema migration
- `Sources/Coordinator/AppCoordinator.swift` — bookmark state, scroll position save/restore
- `Sources/Views/Screens/MarkdownView.swift` — wire scroll progress to ReadingProgressBadge

### SwiftData Migration
- Add `bookmarkedLines: [Int]` to FileMetadata
- Lightweight migration (additive property with default empty array)

### Height Estimation Algorithm
```
For each block:
  estimatedHeight = fontSize * 1.3 * (endLine - startLine + 1)
  
  // Add padding per block type
  if heading:  estimatedHeight += topPadding(level)
  if codeBlock: estimatedHeight += headerHeight + paddingHeight
  
As blocks render:
  onGeometryChange { size in
    heightCache[block.id] = size.height
  }
  
Gutter position for block N:
  y = sum(heightCache[0..<N] ?? estimatedHeight[0..<N])
```
