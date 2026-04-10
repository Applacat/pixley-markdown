# Spec 4 — New Interactive Controls (Slider, Stepper, Toggle, Color, Auditable Checkbox, File Re-pick)

**Version:** 1.0
**Date:** 2026-04-10
**Status:** Spec
**Milestone:** v4: Native Renderer
**Closes:** #5, #6, #7, #8, #9, #10

---

## Overview

Add 6 new interactive controls to the Pixley interactive element system: slider, stepper, toggle, color picker, auditable checkbox, and re-pickable file/folder picker. All controls are inline native macOS widgets that detect via the `[[...]]` fill-in pattern (or checkbox variant), render as SwiftUI controls, and write their values back to the source markdown.

## Problem Statement

Pixley's interactive element system currently supports checkboxes, text fill-ins, choices, status, feedback, and confidence indicators. The v4 renderer needs additional controls to match the "just pipes" vision — expose native controls, drop opinions. Users want sliders for ratings, steppers for counts, toggles for flags, color pickers for hex values, auditable checkboxes that timestamp completions, and file pickers they can change their mind about.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Element model | **Separate enum case per control** | Each has distinct behavior, write-back format, and detection. OOD: single-responsibility per type. |
| Auditable checkbox | **Separate `AuditableCheckboxElement`** | Clean separation from basic checkbox. Own detection and notes logic. |
| Note prompt trigger | **`(notes)` suffix in label** | AI writes `- [ ] Deployed (notes)`. Parenthetical, natural language. Stripped on write-back. |
| Slider write mode | **On release only** | Clean file history, no write flood. |
| Slider range | **Inclusive, strict validation** | `[[slide 1-10]]` = 1..10 inclusive. Invalid ranges render as plain text (not detected). |
| Slider step | **Integer only, step 1** | No decimal ambiguity. Keeps value formatting simple. |
| Slider value label | **Right of slider** | `[====|====] 7`. Standard pattern. |
| Stepper look | **Standard NSStepper** | Native SwiftUI Stepper with value label. Platform-native. |
| Color display | **Swatch + hex** | Colored square next to `#FF5733`. Visual + explicit. |
| Color re-pick | **Click to re-open picker** | Users can change their mind. |
| Toggle label | **Text stays separate** | `Dark mode: [[toggle]]` = text + bare toggle. AI controls layout. |
| File picker badge | **Filename + faded parent path** | `~/Documents/‹ report.pdf`. Inline context. |
| All values re-editable | **Yes, inline** | Filled controls stay live. User can adjust anytime without manual edit. |
| Build order | **Infrastructure first, then all 6** | Phase 1: element types + detection. Phase 2: rendering. One release. |

---

## Scope

### In Scope

- 6 new interactive element types: `SliderElement`, `StepperElement`, `ToggleElement`, `ColorPickerElement`, `AuditableCheckboxElement`, plus re-pick support for existing `FillInElement.file`/`.folder`
- Detection patterns:
  - `[[slide MIN-MAX]]` or `[[rate MIN-MAX]]` → slider
  - `[[pick number]]` or `[[pick number MIN-MAX]]` → stepper
  - `[[toggle]]` → toggle switch
  - `[[pick color]]` → color picker
  - `- [ ] Label (notes)` or `- [x] Label (notes)` → auditable checkbox
- Filled-state detection for all 6 (recognize existing values and make them re-editable)
- Write-back in markdown:
  - Slider/stepper: `[[slide 1-10]]` → `7` (on release)
  - Toggle: `[[toggle]]` → `on` or `off`
  - Color: `[[pick color]]` → `#FF5733`
  - Auditable checkbox checked: `- [x] Label (notes) — 2026-04-10: user's note`
  - File picker re-pick: path badge click → NSOpenPanel → new path replaces old
- Native SwiftUI rendering in NativeControlView (Enhanced mode)
- Plain mode click-target support via existing `annotatePlainClickTargets` path
- Interactive elements work inside table cells and collapsible sections (already supported by existing renderer)

### Out of Scope

- Decimal/float sliders (strict integer only)
- Slider tick marks or custom step sizes
- Color picker with alpha channel
- Stepper with custom increment (always +/-1)
- Toggle with custom on/off labels (always `on`/`off` in markdown)
- Auditable checkbox with predefined note categories (free-text only)
- Custom timestamp formats (always `YYYY-MM-DD`)
- Multi-file selection in file picker re-pick
- Control grouping/dependencies (e.g., "show this slider only when X toggle is on")

---

## User Stories

### US-1: New InteractiveElement Types + Detection

**Description:** As a developer, I want new InteractiveElement enum cases and detection regex patterns so the rest of the system can recognize the new controls.

**Acceptance Criteria:**
- [ ] `InteractiveElement` enum gains `.slider(SliderElement)`, `.stepper(StepperElement)`, `.toggle(ToggleElement)`, `.colorPicker(ColorPickerElement)`, `.auditableCheckbox(AuditableCheckboxElement)`
- [ ] Each element struct carries `range: Range<String.Index>` and kind-specific fields
- [ ] `InteractiveElementDetector.detect(in:)` finds all 6 patterns in document content
- [ ] Detection recognizes both empty (`[[slide 1-10]]`) and filled (`7`) states
- [ ] Invalid ranges (e.g., `[[slide 10-1]]`) are not detected — render as plain text
- [ ] `FillInElement` recognition for file/folder types recognizes filled paths as re-editable badges
- [ ] Unit tests for each detection pattern
- [ ] `swift build && swift test` passes

### US-2: Slider Control

**Description:** As a user, I want to see `[[slide MIN-MAX]]` patterns render as inline sliders that I can drag to set a value.

**Acceptance Criteria:**
- [ ] `[[slide 1-10]]` and `[[rate 1-5]]` render as native SwiftUI Slider
- [ ] Slider shows current value label to the right
- [ ] Dragging the slider does not write to file until release
- [ ] On release, file updates: `[[slide 1-10]]` → `7`
- [ ] Filled state (`7` in place of `[[slide 1-10]]`) re-renders as slider with value pre-set
- [ ] Dragging a filled slider updates the value in place
- [ ] Invalid ranges render as plain text (not detected)
- [ ] Inline in text flow alongside surrounding paragraph text

### US-3: Stepper Control

**Description:** As a user, I want to see `[[pick number MIN-MAX]]` render as an inline stepper with up/down arrows.

**Acceptance Criteria:**
- [ ] `[[pick number 1-20]]` renders as SwiftUI Stepper with value label
- [ ] `[[pick number]]` without range renders as unbounded stepper (defaults to 0..99)
- [ ] Clicking up/down updates value immediately (steppers don't have drag-release semantics)
- [ ] File updates on each change: `[[pick number]]` → `3`
- [ ] Filled state is re-editable
- [ ] Step size is always 1

### US-4: Toggle Switch

**Description:** As a user, I want to see `[[toggle]]` render as an inline switch.

**Acceptance Criteria:**
- [ ] `[[toggle]]` renders as bare SwiftUI Toggle (no label)
- [ ] Clicking flips state: `[[toggle]]` → `on` or `off`
- [ ] Filled state (`on`/`off`) re-renders as toggle with current state
- [ ] Clicking filled toggle flips the state in the file
- [ ] Surrounding text (e.g., `Dark mode:`) stays as plain text outside the toggle

### US-5: Color Picker

**Description:** As a user, I want to see `[[pick color]]` render as a color swatch that opens a color picker on click.

**Acceptance Criteria:**
- [ ] `[[pick color]]` renders as a clickable placeholder (e.g., gray swatch with "?" or plus icon)
- [ ] Click opens native SwiftUI ColorPicker
- [ ] After selection: file updates to `#FF5733` and renders as [colored swatch] `#FF5733`
- [ ] Filled state shows swatch + hex inline
- [ ] Clicking filled swatch re-opens color picker for re-selection

### US-6: Auditable Checkbox

**Description:** As a user, I want checkboxes with `(notes)` suffix to auto-append a date and prompt for an optional note on check.

**Acceptance Criteria:**
- [ ] Checkboxes with `(notes)` suffix in the label are detected as `AuditableCheckboxElement`
- [ ] `(notes)` is stripped from the rendered label
- [ ] On check, a popover prompts for an optional note
- [ ] If user confirms without note: `- [x] Label (notes) — 2026-04-10`
- [ ] If user confirms with note: `- [x] Label (notes) — 2026-04-10: note text`
- [ ] Unchecking removes the date/note suffix: `- [ ] Label (notes)`
- [ ] Checkboxes without `(notes)` remain regular CheckboxElement
- [ ] Note text is sanitized (strip `-->`, `--`) to prevent HTML corruption if inside a comment

### US-7: File/Folder Picker Re-pick

**Description:** As a user, I want filled `[[choose file]]` paths to render as clickable badges I can click to re-pick.

**Acceptance Criteria:**
- [ ] Existing `[[choose file]]` detection unchanged for empty state
- [ ] When a file/folder FillInElement has a filled value (path), it renders as a clickable badge
- [ ] Badge shows filename + faded parent directory: `~/Documents/‹ report.pdf`
- [ ] Click opens NSOpenPanel pre-seeded to the current path's directory
- [ ] New selection replaces the old path in the file
- [ ] Works for both `[[choose file]]` and `[[choose folder]]`

### US-8: Plain Mode Click Targets

**Description:** As a Plain mode user, I want the 6 new controls to have click targets + tooltips so they're still interactive.

**Acceptance Criteria:**
- [ ] `InteractiveAnnotator.annotatePlainClickTargets` handles the 6 new element types
- [ ] Clicking a slider/stepper/toggle element in Plain mode opens a small popover with the control
- [ ] Color picker in Plain mode opens native color picker on click
- [ ] Auditable checkbox in Plain mode behaves like regular checkbox click + note prompt
- [ ] Tooltips describe each control on hover

---

## Implementation Phases

### Phase 1: Element Types, Detection, Write-back

- [ ] Add new element structs in `Packages/aimdRenderer/Sources/aimdRenderer/Models/InteractiveElement.swift`
- [ ] Extend `InteractiveElement` enum with new cases
- [ ] Add detection patterns in `InteractiveElementDetector`
- [ ] Add write-back logic in `InteractionHandler` for each new type
- [ ] Unit tests for detection (both empty and filled states)
- **Verification:** `cd AIMDReader && swift build && swift test`

### Phase 2: Enhanced Mode Rendering (NativeControlView)

- [ ] Add slider view in NativeControlView (SwiftUI Slider + value label)
- [ ] Add stepper view (SwiftUI Stepper)
- [ ] Add toggle view (SwiftUI Toggle, unlabeled)
- [ ] Add color picker view (swatch + hex, ColorPicker on click)
- [ ] Add auditable checkbox view (checkbox + note popover on check)
- [ ] Add file/folder re-pick badge view (filename + parent path)
- [ ] Wire each to `onChanged` / `onClicked` callbacks
- **Verification:** `swift build` + manual: open a markdown file with all 6 patterns, interact with each, verify file updates

### Phase 3: Plain Mode Click Targets + Note Sanitization

- [ ] Extend `InteractiveAnnotator.annotatePlainClickTargets` for 6 new element types
- [ ] Implement small popovers for slider/stepper/toggle in Plain mode (AppKit)
- [ ] Auditable checkbox note prompt popover (shared between Plain and Enhanced)
- [ ] Sanitize note text to prevent HTML comment corruption
- [ ] Verify tooltips display correctly
- **Verification:** `swift build && swift test` + manual: test each control in both Plain and Enhanced modes

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-8 pass
- [ ] All implementation phases verified
- [ ] Tests pass: `cd AIMDReader && swift test`
- [ ] Build succeeds: `cd AIMDReader && swift build`
- [ ] All 6 controls work in Enhanced mode (NativeDocumentView)
- [ ] All 6 controls work in Plain mode (NSTextView click targets)
- [ ] Slider writes on release (not on drag)
- [ ] Color picker shows swatch + hex, re-pickable
- [ ] Auditable checkbox triggered by `(notes)` suffix only
- [ ] File picker re-pick works with pre-seeded directory
- [ ] Detection patterns documented in `pixley-platform-capabilities.md`

---

## Technical Notes

### Write-back Formats

| Control | Empty | Filled Example |
|---------|-------|----------------|
| Slider | `[[slide 1-10]]` | `7` |
| Stepper | `[[pick number 1-20]]` | `3` |
| Toggle | `[[toggle]]` | `on` or `off` |
| Color Picker | `[[pick color]]` | `#FF5733` |
| Auditable Checkbox (unchecked) | `- [ ] Label (notes)` | (same) |
| Auditable Checkbox (checked, no note) | n/a | `- [x] Label (notes) — 2026-04-10` |
| Auditable Checkbox (checked, with note) | n/a | `- [x] Label (notes) — 2026-04-10: note text` |
| File/Folder Picker | `[[choose file]]` | `/path/to/file` (rendered as badge) |

### Detection Priority

Because fill-in patterns overlap (`[[slide 1-10]]` could match a generic fill-in regex), detection order matters:

1. Slider (`\[\[(slide|rate)\s+\d+-\d+\]\]`)
2. Stepper (`\[\[pick number(\s+\d+-\d+)?\]\]`)
3. Toggle (`\[\[toggle\]\]`)
4. Color picker (`\[\[pick color\]\]`)
5. File/folder (existing `\[\[choose (file|folder)\]\]`)
6. Generic fill-in (existing `\[\[(enter|pick) .+?\]\]`)

Auditable checkbox detection happens in checkbox pass: if a checkbox label ends with `(notes)`, classify as `.auditableCheckbox` instead of `.checkbox`.

### Filled State Detection

Detecting filled values requires anchoring to surrounding context since a bare `7` or `#FF5733` could appear anywhere in a document. Strategy: after initial parse, walk the document a second time and look for "adjacent to label" patterns (e.g., `Priority: 7` where "Priority:" was known to precede a slider). Alternative: use invisible markers in the write-back format (e.g., `<!-- slider:1-10 -->7`), but that pollutes the markdown.

**Decision for MVP:** Keep the slider/stepper/toggle controls empty-state only for the first iteration. Re-editing requires the user to manually re-type `[[slide 1-10]]` to get the control back. File picker re-pick is the exception since it has its own detection pattern.

This simplifies the initial implementation. Re-editable filled controls can come in a follow-up spec.

### Plain Mode Popover Strategy

In Plain mode (NSTextView), the 6 new controls need click targets that open popovers. Reuse the existing `MarkdownTextViewPopovers` infrastructure (still exists as the Plain mode popover system after the renderer cleanup).
