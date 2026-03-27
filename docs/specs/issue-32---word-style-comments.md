# Word-Style Range Comments

**Issue:** #32
**Date:** 2026-03-27
**Status:** Spec complete, ready for implementation
**Milestone:** v3.0 — Relay MVP

---

## Problem Statement

Users and AI collaborators need a way to attach comments to specific text ranges in markdown documents — like MS Word's comment feature. Currently, CriticMarkup highlights (`{==text==}{>>comment<<}`) are detected but rendered with an accept/reject popover that doesn't make sense for comments (both actions do the same thing). This feature repurposes the highlight pattern as a proper comment system.

## Scope

### In Scope
- Select text → "Add Comment" flow (context menu, Cmd+Shift+C, toolbar)
- Inline popover for typing comment text
- CriticMarkup write-back: `{==selected text==}{>>comment text<<}`
- Theme-specific highlight background color for commented text
- Gutter dot indicator on lines with comments (clickable, opens popover)
- Comment popover: read comment, edit, remove
- Replace existing highlight accept/reject with comment popover
- Multi-line text selection support
- Prevent overlapping comments
- Free tier (no paywall)

### Out of Scope
- CriticMarkup additions/deletions — accept/reject stays unchanged
- Margin bubble pane (Word-style sidebar)
- Comment threads / replies
- Comment author tracking
- Toolbar button (future polish)

---

## User Stories

### US-1: Add Comment to Selected Text
**Description:** As a user, I want to select text and add a comment so the AI (or another collaborator) can see my note attached to a specific passage.

**Acceptance Criteria:**
- [ ] Select text → right-click → "Add Comment" menu item appears
- [ ] Cmd+Shift+C keyboard shortcut triggers "Add Comment" when text is selected
- [ ] Inline popover appears at the selection with a text field
- [ ] Submitting the comment writes `{==selected text==}{>>comment text<<}` to the file
- [ ] If selection overlaps an existing comment, show alert: "This text already has a comment"
- [ ] Multi-line selections work correctly
- [ ] FileWatcher is suppressed during write-back (no reload flash)
- [ ] Build succeeds

### US-2: Render Comment Highlights
**Description:** As a user, I want to see which text has comments via visual highlighting and gutter indicators.

**Acceptance Criteria:**
- [ ] Text wrapped in `{==...==}{>>...<<}` gets a theme-specific background color
- [ ] CriticMarkup delimiters are dimmed (existing behavior preserved)
- [ ] GutterOverlayView shows a small dot on lines containing comment highlights
- [ ] Gutter dot color is theme-appropriate
- [ ] Highlight color works correctly in all bundled syntax themes (light and dark)
- [ ] Build succeeds

### US-3: Read, Edit, and Remove Comments
**Description:** As a user, I want to click a highlighted comment to read it, edit the comment text, or remove the comment.

**Acceptance Criteria:**
- [ ] Clicking highlighted text opens a popover showing the comment text
- [ ] Clicking the gutter dot opens the same popover
- [ ] Popover has an "Edit" button that makes the comment text editable
- [ ] Editing and submitting writes the updated `{>>new comment<<}` back to the file
- [ ] "Remove" button strips all CriticMarkup, leaving plain text in the file
- [ ] Popover dismisses on click outside or Escape
- [ ] Build succeeds

### US-4: Replace Highlight Accept/Reject with Comment View
**Description:** As a developer, I need to change the CriticMarkup `.highlight` type to show a comment popover instead of the meaningless accept/reject popover.

**Acceptance Criteria:**
- [ ] `SuggestionElement` with `.highlight` type now triggers comment popover (not accept/reject)
- [ ] `{++text++}` additions still show accept/reject popover (unchanged)
- [ ] `{--text--}` deletions still show accept/reject popover (unchanged)
- [ ] `{~~old~>new~~}` substitutions still show accept/reject popover (unchanged)
- [ ] `{==text==}{>>comment<<}` shows comment popover with edit/remove
- [ ] `{==text==}` bare highlight without comment shows "Add Comment" prompt
- [ ] Build succeeds

---

## Technical Design

### Syntax

CriticMarkup highlight (already detected by `InteractiveElementDetector`):
```
{==highlighted text==}{>>comment text here<<}
```

### Detection (Existing)

`InteractiveElementDetector` already detects highlights via regex:
```swift
pattern: #"\{==(.+?)==\}\{>>(.+?)<<\}"#
```

Returns a `SuggestionElement` with `type: .highlight`, `oldText: highlightedText`, `comment: commentText`.

### Write-Back: Add Comment

Use `InteractionHandler` pattern (read-modify-write with FileWatcher suppression):

1. Get the selected text range from NSTextView
2. Read the file content
3. Map NSTextView range → file string range (accounting for annotations)
4. Wrap the selected text: `{==selected==}{>>comment<<}`
5. Write back to file with FileWatcher suppression

### Write-Back: Edit Comment

1. Find the existing `{>>old comment<<}` range from the `SuggestionElement`
2. Replace with `{>>new comment<<}`
3. Write back with FileWatcher suppression

### Write-Back: Remove Comment

1. Find the full `{==text==}{>>comment<<}` range
2. Replace with just `text` (plain, unwrapped)
3. Write back with FileWatcher suppression

### Overlap Prevention

Before adding a comment, check if the selected range intersects any existing `SuggestionElement` with `.highlight` type. If so, show an alert.

### Rendering

- **Highlight color**: Add a `commentHighlight` color to each syntax theme. Should be a subtle, readable background tint (e.g., warm yellow for light themes, muted amber for dark themes).
- **Gutter dot**: Extend `GutterOverlayView` to show a small colored dot for lines containing `.highlight` elements.

### Popover

New `CommentPopoverController` (like existing `FillInPopoverController`):
- Shows comment text (read-only by default)
- "Edit" button → text becomes editable, shows "Save" button
- "Remove" button → strips markup, keeps text
- Anchored to the highlighted text rect in the NSTextView

### Files Modified

- `InteractiveAnnotator.swift` — Add comment highlight background color
- `MarkdownTextViewPopovers.swift` — Route `.highlight` to comment popover instead of accept/reject
- `PopoverControllers.swift` — New `CommentPopoverController`
- `GutterOverlayView.swift` — Add comment dot indicator
- `InteractionHandler.swift` — Add `addComment`, `editComment`, `removeComment` methods
- `MarkdownEditorCoordinator.swift` — Add context menu item + keyboard shortcut
- `Packages/aimdRenderer/.../SyntaxTheme.swift` — Add `commentHighlight` color
- Each theme file — Add comment highlight color values

---

## Implementation Phases

### Phase 1: Comment Popover + Highlight Rendering
**Goal:** Click existing `{==text==}{>>comment<<}` in a file → see comment in a popover.

- [ ] Create `CommentPopoverController` with read-only comment display + "Remove" button
- [ ] Route `.highlight` `SuggestionElement` to `CommentPopoverController` (not accept/reject)
- [ ] Add `commentHighlight` color to `SyntaxTheme` protocol + all bundled themes
- [ ] Apply comment highlight background in `InteractiveAnnotator`
- [ ] Gutter dot for comment lines in `GutterOverlayView`
- [ ] **Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### Phase 2: Add Comment Flow
**Goal:** Select text → "Add Comment" → writes CriticMarkup to file.

- [ ] Add "Add Comment" to NSTextView context menu in `MarkdownEditorCoordinator`
- [ ] Add Cmd+Shift+C keyboard shortcut
- [ ] Create inline popover for entering comment text
- [ ] Implement `addComment(selectedRange:comment:)` in `InteractionHandler`
- [ ] Overlap prevention: check against existing highlights before writing
- [ ] Multi-line selection support
- [ ] **Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### Phase 3: Edit Comment + Polish
**Goal:** Full edit/remove lifecycle from the popover.

- [ ] Add "Edit" mode to `CommentPopoverController` (text field becomes editable)
- [ ] Implement `editComment` in `InteractionHandler`
- [ ] Implement `removeComment` in `InteractionHandler`
- [ ] Handle bare `{==text==}` without comment → show "Add Comment" prompt in popover
- [ ] Verify all syntax themes have appropriate comment highlight colors (light + dark)
- [ ] **Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build && cd Packages/aimdRenderer && swift test`

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-4 pass
- [ ] All three implementation phases verified
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- [ ] Package tests pass: `cd Packages/aimdRenderer && swift test`
- [ ] Manual smoke test: select text → add comment → see highlight → click → read → edit → remove
- [ ] Verify highlight colors in at least 2 light and 2 dark themes

## Ralph Loop Command

```bash
/ralph-loop "Implement Word-style range comments per spec at docs/specs/issue-32---word-style-comments.md

PHASES:
1. Comment Popover + Highlight Rendering: CommentPopoverController, route .highlight to comment view, theme colors, gutter dot - verify with xcodebuild build
2. Add Comment Flow: context menu, Cmd+Shift+C, inline input popover, InteractionHandler.addComment, overlap prevention - verify with xcodebuild build
3. Edit Comment + Polish: edit mode in popover, editComment/removeComment in InteractionHandler, bare highlight handling, theme verification - verify with xcodebuild build + swift test

VERIFICATION (run after each phase):
- xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build
- cd Packages/aimdRenderer && swift test

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```

## Implementation Notes
*(To be filled during implementation)*
