# Spec 3 — Add Comment, Tab Navigation & Comment Threading for NativeDocumentView

**Version:** 1.0
**Date:** 2026-04-09
**Status:** Spec
**Milestone:** v4: Native Renderer
**Depends on:** Spec 1 (renderer-foundation), Spec 2 (gutter/bookmarks)

---

## Overview

Add gutter-triggered inline comments with threading, Tab-based focus cycling through interactive elements, and comment indicators to the NativeDocumentView (Enhanced mode).

## Problem Statement

The NativeDocumentView has gutter line numbers and bookmarks (Spec 2) but no way to add inline comments. Plain mode supports comments via gutter popover. Enhanced mode needs parity plus threading (multiple comments per line displayed as a stacked list). Additionally, interactive elements in the SwiftUI renderer have no keyboard navigation — users must click each control individually.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Comment trigger | **Gutter click** | Same as Plain mode. Consistent UX across modes. |
| Comment format | **`<!-- comment: text -->`** appended to end of line | Same as Plain mode. Markdown-native. |
| Write path | **Reuse InteractionHandler** | Same write path as Plain mode. Tested, coordinates with FileWatcher. |
| Popover UI | **SwiftUI `.popover` on GutterLineView** | Native SwiftUI popover, dismissed on click outside. |
| Comment indicator | **Small dot in gutter using `palette.comment`** | Distinct from bookmark dot (palette.keyword). Thematic — it's a comment. |
| Comment detection | **Scan raw content, pass as `Set<Int>`** | Same pattern as bookmarkedLines. Parser unchanged. |
| Threading | **Separate `<!-- comment: text -->` tags on consecutive lines** | Each comment is its own tag. Multiple tags = thread. |
| Thread display | **Stacked list + text input at bottom** | Mini chat style. Oldest first, new input at bottom. |
| Keyboard nav | **Tab cycles interactive elements** | Space/Enter activates. Arrow keys scroll. Standard macOS focus ring. |
| Focus ring | **Standard macOS `.focusable()` ring** | Platform-native, good for accessibility. |
| Tab wrap | **Wrap around** | Last element → first. Standard form behavior. |
| Hover states | **Interactive elements only** | No extra hover effects. Native controls handle their own hover. |

---

## Scope

### In Scope

- Gutter "Add Comment" popover (SwiftUI `.popover` on GutterLineView)
- Comment written as `<!-- comment: text -->` at end of clicked line via InteractionHandler
- Comment indicator dot in gutter (palette.comment color) for lines with existing comments
- Comment detection by scanning raw content for `<!-- comment: ... -->` pattern
- Comment threading: multiple comments on consecutive lines shown as stacked list in popover
- Tab focus cycling through interactive elements (checkboxes, fill-ins, pickers, etc.)
- Standard macOS focus ring on focused interactive elements
- Space/Enter activates focused element
- Tab wraps from last element to first

### Out of Scope

- Comment editing/deletion from gutter (future)
- Hover effects on non-interactive elements
- Block-level focus navigation (arrow keys between blocks)
- Comment persistence in SwiftData (comments live in the markdown file)

---

## User Stories

### US-1: Comment Detection and Gutter Indicator

**Description:** As a user, I want to see which lines have inline comments so I can review existing annotations.

**Acceptance Criteria:**
- [ ] `MarkdownView` scans content for `<!-- comment: ... -->` pattern and produces `commentedLines: Set<Int>`
- [ ] `commentedLines` passed to NativeDocumentView
- [ ] GutterLineView shows a small circle using `palette.comment` color for lines in `commentedLines`
- [ ] Comment dot is visually distinct from bookmark dot (different color)
- [ ] Both dots can appear simultaneously on the same line (comment + bookmark)
- [ ] Empty documents show no comment indicators
- [ ] `swift build` succeeds

### US-2: Gutter Comment Popover (Single Comment)

**Description:** As a user, I want to click a gutter line to add a comment to that line.

**Acceptance Criteria:**
- [ ] Clicking a gutter line number (or comment dot) shows a SwiftUI `.popover`
- [ ] Popover contains a text field and "Add" button
- [ ] Pressing Enter or clicking "Add" writes `<!-- comment: text -->` at the end of `block.startLine`
- [ ] File write goes through InteractionHandler (same path as Plain mode)
- [ ] Popover dismisses after adding comment
- [ ] Escape dismisses popover without adding
- [ ] After adding, `commentedLines` updates and gutter indicator appears
- [ ] `swift build` succeeds

### US-3: Comment Threading (Multiple Comments)

**Description:** As a user, I want to see and add to a thread of comments on a line.

**Acceptance Criteria:**
- [ ] When a line already has comments (consecutive `<!-- comment: ... -->` tags below it), popover shows existing comments as a stacked list
- [ ] Comments displayed oldest-first (top to bottom, matching file order)
- [ ] Each comment shows its text (no timestamp or author for now)
- [ ] Text input at bottom of list for adding a new comment to the thread
- [ ] New comment appended as a new `<!-- comment: text -->` tag on the next line after existing comments
- [ ] Thread popover scrolls if many comments
- [ ] `swift build` succeeds

### US-4: Tab Focus Cycling

**Description:** As a user, I want to press Tab to navigate between interactive elements in the document.

**Acceptance Criteria:**
- [ ] Tab moves focus to the next interactive element (checkbox, fill-in, picker, toggle, etc.)
- [ ] Shift+Tab moves focus to the previous interactive element
- [ ] Focused element shows standard macOS focus ring
- [ ] Space or Enter activates the focused element (toggle checkbox, open picker, etc.)
- [ ] Tab wraps: last element → first element, Shift+Tab on first → last
- [ ] Arrow keys continue to scroll the document (not captured by focus system)
- [ ] Focus is visible at all zoom levels
- [ ] `swift build` succeeds

### US-5: Wire InteractionHandler for Enhanced Mode Comments

**Description:** As a developer, I want NativeDocumentView file writes to go through the same InteractionHandler as Plain mode.

**Acceptance Criteria:**
- [ ] NativeDocumentView receives an `onAddComment: (Int, String) -> Void` callback (lineNumber, commentText)
- [ ] MarkdownView's `nativeRendererContent` passes a closure that calls InteractionHandler to write the comment
- [ ] FileWatcher coordination works (write pauses watcher, resumes after)
- [ ] After write, content reloads and comment indicator appears in gutter
- [ ] `swift build` succeeds

---

## Implementation Phases

### Phase 1: Comment Detection + Gutter Indicator

- [ ] Add `commentedLines: Set<Int>` parameter to NativeDocumentView
- [ ] Scan content for `<!-- comment: ... -->` pattern in MarkdownView (reuse existing `refreshCommentedLines`)
- [ ] Pass `commentedLines` through to NativeDocumentView
- [ ] Update GutterLineView to show comment dot (palette.comment color)
- [ ] Support both bookmark and comment dots on same line
- **Verification:** `cd AIMDReader && swift build && swift test`

### Phase 2: Comment Popover + Threading

- [ ] Add `.popover` to GutterLineView triggered on click (distinct from bookmark toggle)
- [ ] Implement single-comment popover (text field + Add button)
- [ ] Wire `onAddComment` callback through MarkdownView to InteractionHandler
- [ ] Implement thread detection (scan consecutive `<!-- comment: ... -->` lines)
- [ ] Show existing comments as stacked list in popover
- [ ] New comment appends after existing thread
- **Verification:** `swift build` + manual: add comment via gutter, verify it appears in file and gutter indicator updates

### Phase 3: Tab Focus Cycling

- [ ] Add `.focusable()` to interactive element views in NativeControlView
- [ ] Implement Tab/Shift+Tab focus cycling with wrap-around
- [ ] Space/Enter activation for focused elements
- [ ] Verify standard macOS focus ring appears
- [ ] Verify arrow keys still scroll (not captured by focus)
- **Verification:** `swift build` + manual: Tab through checkboxes and fill-ins, verify focus ring and activation

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-5 pass
- [ ] All implementation phases verified
- [ ] Tests pass: `cd AIMDReader && swift test`
- [ ] Build succeeds: `cd AIMDReader && swift build`
- [ ] Gutter shows comment indicators for lines with `<!-- comment: ... -->`
- [ ] Gutter click opens popover to add comment
- [ ] Threading works: multiple comments shown as stacked list, new comments append
- [ ] Tab cycles through interactive elements with standard focus ring
- [ ] Comments written via InteractionHandler (same as Plain mode)

---

## Technical Notes

### Files Created
- None expected (features added to existing NativeRenderer files)

### Files Modified
- `Sources/Views/NativeRenderer/NativeDocumentView.swift` — commentedLines param, onAddComment callback, popover state
- `Sources/Views/NativeRenderer/NativeDocumentView.swift` (GutterLineView) — comment dot, popover trigger
- `Sources/Views/NativeRenderer/NativeControlView.swift` — .focusable() on interactive controls
- `Sources/Views/Screens/MarkdownView.swift` — pass commentedLines and onAddComment to NativeDocumentView

### Comment Detection Pattern
```swift
// Reuse existing refreshCommentedLines from MarkdownView
// Pattern: <!-- comment: ... -->
// Scan line-by-line, track which source lines have comment tags
```

### Threading Detection
```swift
// After finding a comment tag, check consecutive lines below for more comment tags
// Group them by the content line they annotate (the non-comment line above the first tag)
// Popover shows the group as a thread
```

### Tab Focus Implementation
```swift
// Use SwiftUI's @FocusState with a focusable enum or index
// Each NativeControlView element gets .focusable(true)
// Tab handler advances focus index, wrapping at bounds
```
