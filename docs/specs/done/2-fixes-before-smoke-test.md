# Spec: 2 Fixes Before Smoke Test

**Date:** 2026-03-09
**Status:** READY FOR IMPLEMENTATION

---

## Overview

Two targeted fixes to improve the interactive experience before the v1.5 smoke test:
1. **Fill-in re-edit** — allow changing already-submitted fill-in values
2. **Gutter comments** — unified bookmark + comment popover from the line number gutter

---

## US-1: Fill-In Re-Edit

**Description:** As a reader, I want to click an already-filled `[[value]]` to change my answer, so that I can correct mistakes or update information without manually editing the file.

### Current Behavior
- User clicks `[[enter project name]]` → popover opens → submits "My Project" → file becomes `[[My Project]]`
- Clicking `[[My Project]]` again does nothing (or opens empty popover)

### Desired Behavior
- Clicking `[[My Project]]` reopens the same popover with "My Project" pre-populated
- Cursor positioned at end of text
- Submit replaces the old value
- Works for all fill-in types: text, date, file, folder

### Acceptance Criteria
- [ ] Clicking a filled `[[My Project]]` opens popover with "My Project" pre-filled
- [ ] Submitting a new value replaces the old value in the file
- [ ] Date fill-ins pre-populate with the existing date
- [ ] File/folder fill-ins show the current path and allow re-picking
- [ ] Same "Submit" button label whether editing or filling fresh
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### Technical Notes
- The filled value is already stored as the hint text in the `FillInElement` (the detector parses `[[text]]` where `text` becomes the hint)
- The popover (`showElementPopover` in `MarkdownNSTextView`) needs to check if the fill-in already has a value and pre-populate the text field
- Distinguish "unfilled placeholder" from "filled value": unfilled hints typically contain words like "enter", "choose", "pick", "select", or "date" — a filled value won't match these patterns
- For date type: parse the existing date string back into a date picker value
- For file/folder type: show the existing path in the popover, clicking re-opens the native picker

---

## US-2: Gutter Comments via Feedback Insertion

**Description:** As a reader, I want to click a line number in the gutter to leave a comment (and optionally bookmark), so that I can annotate documents with notes that persist in the file.

### Current Behavior
- Clicking a line number toggles an orange bookmark dot
- Bookmarks are stored in SwiftData only (not in the file)
- No way to attach text to a line

### Desired Behavior
- Clicking a line number opens a popover with:
  - **Bookmark toggle** (checkbox at top)
  - **Comment text field** (multi-line)
  - **Submit / Cancel buttons**
- Submitting a comment inserts `<!-- feedback: user text -->` on the line below the clicked line
- If a `<!-- feedback: ... -->` already exists on the next line, the popover pre-fills with the existing text
- Submitting an empty comment removes the `<!-- feedback -->` tag entirely
- Lines with comments show an SF Symbol `text.bubble` icon in the gutter (replaces the orange dot)
- Lines with only a bookmark (no comment) keep the orange dot
- Bookmark toggle in the popover controls the SwiftData bookmark independently

### Acceptance Criteria
- [ ] Clicking gutter opens popover with bookmark toggle + comment field
- [ ] Submitting comment inserts `<!-- feedback: text -->` after the clicked line
- [ ] Existing `<!-- feedback: text -->` pre-fills the comment field
- [ ] Submitting empty comment removes the `<!-- feedback -->` line from the file
- [ ] Gutter shows `text.bubble` SF Symbol for lines with comments
- [ ] Gutter shows orange dot for lines with bookmarks only
- [ ] Bookmark toggle works independently of comment
- [ ] File watcher suppressed during write-back (no spurious reload pill)
- [ ] Comment persists after file reload
- [ ] Build succeeds

### Technical Notes
- **Write-back:** Use existing `InteractionHandler` pattern — read file, find line, insert/replace/remove `<!-- feedback -->` tag, write file, update document content
- **Detection:** `InteractiveElementDetector` already detects `<!-- feedback -->` and `<!-- feedback: text -->` — use this to check if next line has a comment
- **Popover:** Create a new `GutterCommentPopover` (or reuse popover pattern from `MarkdownNSTextView`) attached to the `GutterOverlayView`
- **Gutter drawing:** In `GutterOverlayView.draw()`, check if the line below each visible line contains a `<!-- feedback -->` tag. If so, draw `text.bubble` SF Symbol instead of the bookmark dot.
- **File watcher suppression:** Same pattern as other interactions — `fileWatcher?.suspend()` before write, resume after

---

## Implementation Phases

### Phase 1: Fill-In Re-Edit
- Modify popover creation in `MarkdownNSTextView.showElementPopover()` to detect filled values and pre-populate
- Add heuristic to distinguish placeholder hints from filled values
- Test with text, date, file, folder fill-in types
- **Verify:** Open a file with fill-ins, fill one in, click it again → popover shows current value

### Phase 2: Gutter Comment Popover
- Add popover to `GutterOverlayView.mouseDown()` instead of direct bookmark toggle
- Create popover UI: bookmark toggle checkbox + text field + submit/cancel
- Wire bookmark toggle to existing bookmark system
- Wire comment submission to insert/edit/remove `<!-- feedback -->` via `InteractionHandler`
- **Verify:** Click gutter → popover appears → submit comment → `<!-- feedback: text -->` appears in file

### Phase 3: Gutter Visual Indicators
- Update `GutterOverlayView.draw()` to scan for `<!-- feedback -->` on next lines
- Draw `text.bubble` SF Symbol for commented lines, orange dot for bookmark-only lines
- **Verify:** File with `<!-- feedback -->` tags shows speech bubble icons in gutter

---

## Out of Scope
- Gutter comments for Liquid Glass rendering mode (enhanced mode only for now)
- Inline comment display in the text view (comments are only visible via gutter icon + popover)
- Multi-line comment editing UI (single text field is sufficient)
- Comment threading or replies
