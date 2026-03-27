# BRD: Progress Bar Fix

**Feature:** Replace text-insertion progress bars with NSTextAttachment rendering
**Status:** PENDING
**Created:** 2026-03-24
**GitHub Issue:** #25

---

## Problem Statement

Progress bars in Enhanced mode corrupt the attributed string. The current implementation inserts text characters (`██░░ 40% (2/5)`) into the NSMutableAttributedString at heading positions. This shifts all subsequent character positions, causing the checkbox SF Symbol annotation pass to corrupt text — splitting words, collapsing lines, and placing progress bars on wrong lines.

The two annotation passes (`annotateProgressBars` and `annotateInteractiveElements`) both assume the attributed string matches the original text positions. After either one runs, positions are shifted for the other.

## Solution

Replace text insertion with `NSTextAttachment`. Draw the progress bar dynamically into an `NSImage` at runtime using a function that takes `(completed, total)` and renders a native-style capsule bar. The attachment occupies a single character slot in the attributed string — no multi-character insertions, no position shifts.

---

## Design Decisions

### D1: What counts as progress
Checkboxes only. Choices and reviews are excluded. A heading's progress = checked checkboxes / total checkboxes in that section (including children).

### D2: Which headings show progress bars
H1 (`#`) and H2 (`##`) only. H3 and deeper do not get progress bars even if they have checkboxes.

### D3: Visual style
Native macOS progress indicator style:
- Rounded capsule bar
- System accent color for filled portion
- Gray track for empty portion
- Percentage + count text next to the bar (e.g., `60% (3/5)`)

### D4: 100% completion state
Bar turns green with a checkmark icon. Clear visual signal that the section is done.

### D5: Zero checkboxes
Headings with no checkboxes below them show no progress bar at all.

### D6: Rendering mode
Enhanced mode only. Plain mode does not show progress bars.

### D7: Attachment sizing
Bar height scales with heading font size (~60% of heading font size). H1 gets a proportionally larger bar than H2.

### D8: Update timing
Immediate. Toggling a checkbox re-annotates the heading's progress bar in the same highlight pass. No waiting for file reload.

---

## Technical Design

### Core: `ProgressBarAttachment`

A function (or small helper) that creates an `NSTextAttachment` with a dynamically drawn `NSImage`:

```swift
func makeProgressAttachment(
    filled: Int,
    total: Int,
    fontSize: CGFloat
) -> NSTextAttachment
```

The image is drawn via `NSImage(size:flipped:drawingHandler:)`:
1. Draw rounded capsule track (gray)
2. Draw filled portion (system accent color, or green if 100%)
3. Draw checkmark SF Symbol if 100%
4. Draw percentage + count text

The attachment is inserted at the end of the heading line (before the newline character) as a single character in the attributed string.

### Integration: `annotateProgressBars`

Rewrite `InteractiveAnnotator.annotateProgressBars` to:
1. Parse sections via `MarkdownStructureParser`
2. For each H1/H2 section with checkboxes, compute `(checked, total)`
3. Create an `NSTextAttachment` via `makeProgressAttachment`
4. Insert the attachment attributed string (1 character) at the end of the heading line
5. Process sections in **reverse document order** so single-character insertions don't shift positions for sections above

### Ordering in `MarkdownEditorCoordinator.applyHighlighting`

Progress bars run **after** `annotateInteractiveElements`. Since progress bar insertions are single-character attachments processed in reverse order, they don't affect the interactive element positions (which reference the original text and have already been applied).

### Checkbox toggle → immediate update

The existing flow: checkbox toggle → `InteractionHandler.apply()` → `onContentUpdated` → `coordinator.updateDocumentContent()` → triggers re-highlight via `applyHighlighting`. Since `applyHighlighting` runs the full annotation pipeline including progress bars, the progress bar updates immediately with the new checkbox state.

---

## Scope

### In Scope
- Replace text-insertion progress bars with NSTextAttachment
- Dynamic NSImage rendering of native-style capsule bar
- H1 and H2 headings only, checkboxes only
- Green bar + checkmark at 100%
- Scales with heading font size
- Enhanced mode only
- Immediate update on checkbox toggle
- Remove old `annotateProgressBars` text-insertion code

### Out of Scope
- Progress bars in Plain mode
- Progress bars on H3+ headings
- Tracking choices/reviews in progress
- Animated transitions on progress change
- Progress bars in Liquid Glass mode (mode hidden from UI)

---

## User Stories

### US-1: NSTextAttachment progress bar rendering
**Description:** Replace text-insertion progress bars with NSTextAttachment-based rendering that doesn't corrupt the attributed string.

**Acceptance Criteria:**
- [ ] `makeProgressAttachment(filled:total:fontSize:)` function creates an NSTextAttachment with dynamically drawn NSImage
- [ ] Image shows rounded capsule bar with system accent color fill and gray track
- [ ] Percentage and count text rendered next to bar (e.g., "60% (3/5)")
- [ ] Attachment height = ~60% of heading font size
- [ ] No text corruption — checkbox labels render correctly with progress bars present
- [ ] No line collapsing or word splitting
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### US-2: Section filtering and completion state
**Description:** Only H1/H2 headings with checkboxes show progress bars. 100% shows green + checkmark.

**Acceptance Criteria:**
- [ ] H1 headings with checkboxes show progress bar
- [ ] H2 headings with checkboxes show progress bar
- [ ] H3+ headings do NOT show progress bars
- [ ] Headings with zero checkboxes show NO progress bar
- [ ] "Empty Section (no checkboxes)" heading shows nothing
- [ ] 100% completion: bar turns green, checkmark icon visible
- [ ] Partial completion: system accent color bar, no checkmark
- [ ] Progress counts include checkboxes in child sections (H3 under H2)
- [ ] Build succeeds

### US-3: Immediate update and mode gating
**Description:** Progress bars update immediately on checkbox toggle and only appear in Enhanced mode.

**Acceptance Criteria:**
- [ ] Toggle a checkbox → progress bar on its heading updates without file reload
- [ ] Switch to Plain mode → no progress bars visible
- [ ] Switch back to Enhanced → progress bars reappear
- [ ] Works across font sizes (10-32pt) — bar scales proportionally
- [ ] Multiple headings with different completion states render correctly simultaneously
- [ ] Build succeeds

---

## Implementation Phases

### Phase 1: Attachment renderer (US-1)
- Create `makeProgressAttachment` function
- Rewrite `annotateProgressBars` to use attachments instead of text insertion
- Process in reverse document order
- Verify: no text corruption, progress bars visible on headings

**Verification:**
- `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- Open `~/Desktop/pixley-test/progress-bar-test.md` in Enhanced mode
- Confirm progress bars appear on headings without corrupting checkbox text

### Phase 2: Filtering, completion state, and polish (US-2, US-3)
- Filter to H1/H2 only
- Green bar + checkmark at 100%
- Skip headings with zero checkboxes
- Verify mode gating (Enhanced only)
- Test immediate update on checkbox toggle
- Test across font sizes

**Verification:**
- Same build command
- Toggle checkboxes and confirm immediate progress bar update
- Switch modes and confirm progress bars appear/disappear
- Test with font sizes 10, 15, 24, 32

---

## Definition of Done

- [ ] All acceptance criteria in US-1 through US-3 pass
- [ ] All implementation phases verified
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- [ ] Package tests pass: `cd Packages/aimdRenderer && swift test`
- [ ] No regression in checkbox toggle, choice select, or other interactive elements
- [ ] Progress bars render correctly in test document with mixed heading levels and completion states

---

## Ralph Loop Command

```bash
/ralph-loop "Implement progress bar fix per spec at docs/specs/the-progress-bar-fix.md

PHASES:
1. Attachment renderer (US-1): Create makeProgressAttachment, rewrite annotateProgressBars to use NSTextAttachment, process in reverse order
2. Filtering + polish (US-2, US-3): H1/H2 only, green+checkmark at 100%, mode gating, immediate update, font scaling

VERIFICATION (run after each phase):
- xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build
- cd Packages/aimdRenderer && swift test
- Open ~/Desktop/pixley-test/progress-bar-test.md and visually verify

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```
