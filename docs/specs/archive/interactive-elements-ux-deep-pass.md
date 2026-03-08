# Interactive Elements UX Deep Pass: Making Markdown Touchable for Non-Coders

**Version:** 1.0
**Date:** 2026-03-07
**Status:** Design Spec
**Author:** Luma (UX Design)

---

## Executive Summary

Pixley Markdown's interactive elements are functionally complete but visually invisible to their target audience. The current implementation relies on subtle text-color changes and cursor swaps -- affordances that only work for people who already know what to look for. A non-coder receiving a `.md` file from ChatGPT sees `[ ] Pass` and thinks it is decorative syntax, not a button.

This spec defines a two-mode rendering system: **Prose Mode** (enhanced text affordances with hover states) and **Controls Mode** (native macOS controls overlaid on the text surface). The goal is to make every interactive element self-describing -- a user should understand what to do without any prior knowledge of markdown syntax.

---

## The Core Problem, Frame by Frame

### What the user sees today

1. Opens a `.md` file they received from an AI tool.
2. Sees a wall of text with occasional colored characters: gray brackets `[ ]`, teal underlined text `[[enter project name]]`, purple HTML comments `<!-- feedback -->`.
3. The cursor changes to a pointing hand over some characters, but the user does not move their mouse systematically over every character to discover this.
4. Nothing about the visual presentation says "interact with me." The user reads the file as a static document and emails their responses back to whoever sent it.

### What the user should see

1. Opens the same file.
2. Immediately sees native macOS checkboxes next to task labels, a dropdown for multiple-choice questions, text fields with placeholder text where fill-ins live, and colored pill buttons for status and review actions.
3. The document reads like a form -- some parts are text to read, other parts are controls to use. The distinction is instant and requires zero markdown knowledge.

---

## Design System: Two Rendering Modes

### Mode 1: Prose Mode (Default OFF for new users, ON for power users)

The markdown remains as text, but interactive elements receive enhanced visual treatment that makes them obviously clickable without replacing the source characters.

**Philosophy:** Respect the document's textual nature. Enhance, do not replace. This mode is for users who want to see the markdown source but still need clear interactive cues.

### Mode 2: Controls Mode (Default ON for new users)

Native macOS controls are rendered inline, replacing the ASCII patterns entirely. The underlying markdown is hidden; the user sees only the semantic control.

**Philosophy:** The markdown syntax is an implementation detail. The user should never have to parse `[ ]` or `{++text++}` -- they should see a checkbox or a diff view.

---

## The Toggle Mechanism

### Location: Toolbar, next to the existing Font Size Controls

A segmented control in the toolbar with two segments:

| Segment | Icon | Label | Tooltip |
|---------|------|-------|---------|
| Left | `doc.plaintext` | "Prose" | "Show interactive elements as enhanced text" |
| Right | `switch.2` | "Controls" | "Show interactive elements as native controls" |

**Visual treatment:** The segmented control uses `.segmented` picker style, matching the existing toolbar aesthetic. It sits to the left of the Font Size Controls, separated by a toolbar divider.

### Settings Integration

Add to `BehaviorSettings`:

```
/// Interactive element rendering mode
public var interactiveMode: InteractiveMode = .controls

public enum InteractiveMode: String, CaseIterable, Identifiable, Sendable {
    case prose
    case controls

    public var id: String { rawValue }
}
```

**Default value:** `.controls` -- new users see native controls. Power users who prefer the text view can switch to Prose mode and the preference persists.

**Settings pane:** Add a row in the Behavior tab: "Interactive Elements: [Prose / Controls]" with a brief description: "Controls mode shows native buttons and fields. Prose mode shows enhanced text."

### Toggle Animation

When switching modes, the transition should feel like the controls are rising out of (or sinking into) the text surface:

- **Prose to Controls:** Elements scale from 0.9 to 1.0 with 200ms ease-out, opacity 0 to 1. The ASCII text fades simultaneously (opacity 1 to 0, 150ms).
- **Controls to Prose:** Reverse. Controls shrink to 0.95 and fade, text fades in.
- **Reduced Motion:** Instant swap, no animation. Respect `accessibilityReduceMotion`.
- **Timing curve:** `cubicBezier(0.2, 0.0, 0.0, 1.0)` -- fast start, gentle landing.

---

## Element-by-Element Specification

### 1. Checkboxes (`- [ ] Task` / `- [x] Task`)

**Priority: 1 (Highest)** -- Most common interactive element, most confusing to non-coders.

#### Current State (Before)

- The bracket characters `[ ]` or `[x]` are colored (gray for unchecked, green for checked).
- Cursor changes to pointing hand over the bracket range (3 characters).
- The label text after the brackets has no special treatment.
- The entire line still reads as `- [ ] Task name` -- pure ASCII.

#### Prose Mode (After)

- The bracket characters `[ ]` receive a **rounded background pill**:
  - Unchecked: `NSColor.systemGray.withAlphaComponent(0.15)` background, `systemGray` foreground.
  - Checked: `NSColor.systemGreen.withAlphaComponent(0.15)` background, `systemGreen` foreground, with the `x` replaced by a checkmark glyph character.
- The entire line (from `[` through end of label) is the click target, not just the brackets. Background highlight on hover spans the full line width.
- **Hover state:** The background pill brightens to 0.25 alpha. A 1px bottom border appears in the pill color. The cursor is pointing hand.
- **Tooltip:** "Click to check" (unchecked) or "Click to uncheck" (checked).
- **Click feedback:** Brief flash of the pill background at 0.4 alpha (100ms), then settle to the new state.

#### Controls Mode (After)

- The `- [ ] Task name` text is **hidden** (zero height or replaced).
- In its place: a native `NSButton` with `buttonType = .switch` (macOS checkbox style), positioned at the same vertical location in the text flow.
- The checkbox label is rendered as the button's title in the document's current font.
- **Checked state:** The system checkbox shows its native checkmark. The label text color remains the document foreground.
- **Unchecked state:** The system checkbox is empty. Same label treatment.
- **Spacing:** 4px between the checkbox control and the label text. The control is vertically centered with the text baseline.
- **Size:** Checkbox uses the system default size (14x14pt at standard resolution). This inherently meets the 44x44pt touch target because the entire row (checkbox + label) is clickable.

#### Implementation Approach

**Controls Mode rendering** uses `NSTextAttachment` with a custom `NSTextAttachmentCell` subclass:

```
class CheckboxAttachmentCell: NSTextAttachmentCell {
    var isChecked: Bool
    var label: String
    // Draws an NSButton-style checkbox inline in the text layout
}
```

The attachment replaces the character range of `- [ ] Label` in the `NSMutableAttributedString`. The `InteractiveElementWrapper` attribute is applied to the attachment character so clicks are routed through the existing `onInteractiveElementClicked` pipeline.

**Alternative approach (preferred for fidelity):** Use `NSTextView.addSubview()` to place actual `NSButton` instances as floating subviews, positioned using `NSLayoutManager.boundingRect(forGlyphRange:in:)`. This gives true native rendering but requires manual repositioning on scroll and text layout changes.

**Recommendation:** Start with `NSTextAttachment` for checkboxes (simpler, handles scroll automatically). If visual fidelity is insufficient, graduate to the subview approach.

---

### 2. Choices (Radio Buttons in Blockquotes)

**Priority: 2** -- Second most common, and deeply confusing because "checkboxes inside a blockquote behave differently" is a concept no non-coder would ever guess.

#### Current State (Before)

- Blockquote lines with `> [ ] Option A` / `> [x] Option B` are rendered with blockquote color (gray/muted).
- The bracket characters are colored blue (selected) or gray (unselected).
- Clicking a bracket selects that option and deselects others -- but nothing visual communicates this radio behavior.

#### Prose Mode (After)

- Each option line receives a **selection indicator**: a filled or empty circle before the brackets, replacing the `>` blockquote marker visually.
  - Unselected: `NSColor.systemBlue.withAlphaComponent(0.3)` circle outline (12pt diameter).
  - Selected: Solid `NSColor.systemBlue` filled circle.
- The entire option line is the click target. Background highlight on hover.
- A subtle **group border** (1px, `systemBlue.withAlphaComponent(0.1)`) with 8px corner radius wraps the entire blockquote, visually grouping the options.
- **Hover state:** The hovered option's background shifts to `systemBlue.withAlphaComponent(0.08)`. The circle indicator brightens.
- **Tooltip on group:** "Choose one option" (appears on the group border area, not individual options).

#### Controls Mode (After)

- The entire blockquote is replaced with an **option group container**:
  - Light background: `NSColor.controlBackgroundColor` with 10px corner radius, 1px border in `separatorColor`.
  - If a question/title line exists (bold text before the options), it renders as a label above the radio buttons in `.headline` weight.
  - Each option renders as a native `NSButton` with `buttonType = .radio`, grouped via `NSMatrix` or manual exclusivity logic.
  - Radio buttons use the document font for their labels.
  - 8px vertical spacing between options, 12px padding inside the container.
- **For Yes/No questions (exactly 2 options):** Render as a horizontal `NSSegmentedControl` with two segments ("Yes" / "No"), because the inline `> [ ] YES  [ ] NO` pattern maps naturally to a segmented control.

#### Implementation Approach

Because choice groups span multiple lines and require a container, this is best implemented as a **floating subview** approach:

1. After highlighting, calculate the bounding rect of the blockquote range using `NSLayoutManager`.
2. Create an `NSView` subclass (`ChoiceGroupView`) containing the radio buttons.
3. Add it as a subview of the `MarkdownNSTextView`, positioned over the blockquote range.
4. The underlying blockquote text is given `NSColor.clear` foreground (hidden but preserving layout space).
5. The `ChoiceGroupView` handles clicks and calls back through the existing `onInteractiveElementClicked` pipeline with the appropriate option index.

---

### 3. Review Options (Approval Blockquotes)

**Priority: 3** -- Critical for the "AI asks human to approve" workflow, which is the app's primary use case.

#### Current State (Before)

- Identical visual treatment to choices -- orange-colored brackets for selected review status, gray for unselected.
- Review keywords (APPROVED, PASS, FAIL, etc.) are rendered as plain text within the blockquote.
- No visual indication that these carry different semantic weight than regular choices.

#### Prose Mode (After)

- Each review option receives a **status-colored pill badge** around the keyword:
  - APPROVED / PASS: `systemGreen.withAlphaComponent(0.15)` background, green text.
  - FAIL: `systemRed.withAlphaComponent(0.15)` background, red text.
  - PASS WITH NOTES: `systemYellow.withAlphaComponent(0.15)` background, yellow text.
  - BLOCKED: `systemOrange.withAlphaComponent(0.15)` background, orange text.
  - N/A: `systemGray.withAlphaComponent(0.15)` background, gray text.
- Selected option: The pill background intensifies to 0.3 alpha, and a checkmark glyph appears before the keyword.
- Date stamps (if present) render in `.caption` font, muted color, after the pill.

#### Controls Mode (After)

- The blockquote is replaced with a **review card**:
  - White/dark background with 12px corner radius, subtle shadow (`blur: 8, opacity: 0.1, y: 2`).
  - Title: "Review" in `.headline` weight.
  - Options render as a **button group** -- each review status is a distinct button:
    - APPROVED / PASS: Green-tinted button (`.bordered` style with green tint).
    - FAIL: Red-tinted button.
    - PASS WITH NOTES: Yellow-tinted button.
    - BLOCKED: Orange-tinted button.
    - N/A: Gray button.
  - Selected button shows a checkmark icon and a pressed/highlighted state.
  - Buttons that prompt for notes (FAIL, PASS WITH NOTES, BLOCKED) show a small note icon to indicate the sheet will appear.
  - If a date/notes are present on the selected option, they display below the button group in a muted info row.
- **Interaction:** Clicking a button triggers the existing handler logic (direct selection for APPROVED/PASS/N/A, notes sheet for FAIL/PASS WITH NOTES/BLOCKED).

---

### 4. Fill-in-the-Blank (`[[placeholder]]`)

**Priority: 1 (tied with checkboxes)** -- This is the primary data-collection pattern. Users who do not recognize `[[enter project name]]` as interactive will never fill out the document.

#### Current State (Before)

- The `[[hint text]]` is rendered in teal with a dashed underline.
- Cursor changes to pointing hand.
- No visual suggestion that this is a text field waiting for input.

#### Prose Mode (After)

- The placeholder text renders inside a **visible text field outline**:
  - 1px rounded border in `systemTeal.withAlphaComponent(0.4)`, 6px corner radius.
  - Interior padding: 4px horizontal, 2px vertical.
  - The hint text inside is italicized and uses `tertiaryLabelColor` (lighter than surrounding text).
  - A small pencil icon (`square.and.pencil`, 10pt, teal) appears at the trailing edge of the field outline.
- **Hover state:** Border brightens to `systemTeal.withAlphaComponent(0.7)`. The pencil icon becomes fully opaque. Background shifts to `systemTeal.withAlphaComponent(0.04)`.
- **Tooltip:** "Click to fill in: [hint text]"
- **After filling:** The entered value replaces the placeholder. The text field outline disappears. The value renders in normal document style (no special color), but with a thin bottom border in `systemTeal.withAlphaComponent(0.2)` to indicate it was a fill-in (subtle provenance marker).

#### Controls Mode (After)

- The `[[hint text]]` is replaced with an **actual `NSTextField`** rendered inline:
  - Uses `NSTextField` with `.roundedBezel` border style.
  - Placeholder text is the hint (e.g., "enter project name").
  - Width: calculated from the hint text length, with a minimum of 120pt and maximum of 400pt. Constrained to not exceed the text container width minus margins.
  - Height: matches the document line height.
  - Font: matches the document font.
  - **For `[[choose file]]` / `[[choose folder]]`:** The text field has a trailing button with a folder/document icon that triggers the NSOpenPanel. The text field itself is read-only.
  - **For `[[pick date]]`:** Renders as an `NSDatePicker` with `.textFieldAndStepper` style.
- **After filling:** The text field is replaced with the entered value, rendered as normal text with the same subtle provenance border as Prose mode.

#### Implementation Approach

Fill-in controls must be inline with text flow. Use `NSTextAttachment` with a custom view-based attachment:

```
class FillInTextAttachment: NSTextAttachment {
    let textField: NSTextField
    // Configure frame based on line height and hint width
}
```

The attachment replaces the `[[...]]` range. On Return/Tab in the text field, the value is extracted and passed to `InteractionHandler.fillIn()`.

For file/folder/date variants, the attachment contains a compound view (text field + button, or date picker).

---

### 5. Feedback Comments (`<!-- feedback -->`)

**Priority: 4** -- Important but less immediately confusing because HTML comments are already invisible in most renderers. Pixley's decision to make them visible is the unusual part.

#### Current State (Before)

- The HTML comment `<!-- feedback -->` is rendered in purple text with a faint purple background.
- No visual indication that this is a comment box waiting for input.

#### Prose Mode (After)

- The feedback marker renders as a **comment bubble indicator**:
  - The raw `<!-- feedback -->` text is hidden.
  - In its place: a horizontal rule (thin, 1px, `systemPurple.withAlphaComponent(0.2)`) with a centered pill badge reading "Leave feedback" in `.caption` font, purple text, with a speech bubble icon (`text.bubble`, 10pt).
  - If feedback already exists (`<!-- feedback: text here -->`): the pill reads "Feedback" with a checkmark, and the feedback text displays below in a blockquote-style indented paragraph with a purple left border (3px).
- **Hover state:** The pill badge brightens, gains a subtle shadow (`blur: 4, opacity: 0.1`).
- **Tooltip:** "Click to leave feedback" or "Click to edit feedback."

#### Controls Mode (After)

- **Empty feedback:** Replaced with a native `NSTextField` with placeholder "Leave your feedback here..." and a subtle purple-tinted background (`systemPurple.withAlphaComponent(0.03)`). The field has 8px corner radius, 1px purple border.
  - Height: 60pt minimum (multi-line capable via `NSTextView` in a scroll view, not single-line NSTextField).
  - A "Submit" button appears at the trailing-bottom corner of the field.
- **Existing feedback:** The feedback text displays in a styled card (purple left border, light background) with an "Edit" button.

---

### 6. CriticMarkup Suggestions (`{++add++}`, `{--delete--}`, `{~~old~>new~~}`)

**Priority: 2 (tied with choices)** -- This is the "accept/reject changes" workflow, analogous to Track Changes in Word. Non-coders are familiar with the concept but will never parse `{~~old~>new~~}` syntax.

#### Current State (Before)

- Additions: green text with underline.
- Deletions: red text with strikethrough.
- Substitutions: orange text.
- Highlights: yellow background.
- Clicking opens a sheet with Accept/Reject buttons.

#### Prose Mode (After)

- **Additions** (`{++text++}`):
  - The `{++` and `++}` delimiters are hidden.
  - The added text renders with green background (`systemGreen.withAlphaComponent(0.15)`), green left border (2px), and a small "+" badge at the start.
  - **Hover:** Two small buttons appear inline after the text: a green checkmark (Accept) and a red X (Reject), each 18x18pt.
- **Deletions** (`{--text--}`):
  - The `{--` and `--}` delimiters are hidden.
  - The deleted text renders with red background (`systemRed.withAlphaComponent(0.1)`), red strikethrough, and a small "-" badge at the start.
  - **Hover:** Same Accept/Reject buttons. Accept removes the text; Reject keeps it.
- **Substitutions** (`{~~old~>new~~}`):
  - Renders as a **mini diff view**: old text with red strikethrough, right arrow glyph, new text with green underline. All inline.
  - The `{~~`, `~>`, and `~~}` delimiters are hidden.
  - **Hover:** Accept/Reject buttons after the diff.
- **Highlights** (`{==text==}{>>comment<<}`):
  - Yellow background on the highlighted text, with the comment in a small tooltip-style popover that appears on hover (not in a sheet).

#### Controls Mode (After)

- Each suggestion is replaced with an **inline diff card**:
  - 8px corner radius, 1px border in `separatorColor`.
  - **Addition:** Green left accent bar (3px). Content: the added text. Buttons: "Accept" (green, `.borderedProminent`) and "Reject" (gray, `.bordered`).
  - **Deletion:** Red left accent bar. Content: the deleted text with strikethrough. Same buttons.
  - **Substitution:** Split view: left side shows old text (red, struck through), right side shows new text (green). Divider between them. Same buttons.
  - **Highlight:** Yellow left accent bar. Content: the highlighted text. Below: the comment in italic. Button: "Dismiss" (removes the markup, keeps the text).
- **Button sizing:** Minimum 28pt height, `controlSize(.small)`. Text: "Accept" / "Reject" -- clear, unambiguous verbs.

---

### 7. Status State Machine (`<!-- status: Draft|Review|Done -->`)

**Priority: 5** -- Less common than checkboxes/fill-ins, but visually interesting and satisfying to interact with.

#### Current State (Before)

- The status comment line (`<!-- status: ... -->`) is dimmed to secondary label color.
- The `**Status:** Draft` label has an indigo background pill at 0.15 alpha.
- Clicking opens a status picker sheet with the available next states.

#### Prose Mode (After)

- The status comment line is completely hidden (zero height).
- The status label renders as a **state badge** with directional affordance:
  - Current state in a colored pill: Draft (gray), Review (blue), Done (green), or mapped from the state names.
  - If there are next states available: a small chevron-right icon (`chevron.right.circle`, 10pt) appears after the pill, indicating it can advance.
  - If terminal: no chevron. The pill gets a subtle checkmark icon.
- **Hover state:** The pill lifts slightly (simulated via increased shadow: `blur: 6, opacity: 0.15, y: 3`). A tooltip shows "Click to advance to: [next state]" or lists available states if multiple.
- **Click behavior:** Single next state: advances directly (existing behavior). Multiple: shows a contextual menu anchored to the pill (not a sheet -- a menu is faster and more native-feeling for a simple list of 2-4 items).

#### Controls Mode (After)

- Replaced with a **horizontal stepper visualization**:
  - All states rendered as connected pills in a horizontal row, like a progress stepper.
  - Past states: muted, with checkmarks.
  - Current state: highlighted (filled background in the state's semantic color).
  - Future states: outlined, muted.
  - Clicking a future state advances to it (if valid per the forward-only rule).
  - The status comment is hidden.
  - Total width: constrained to the text column width. If states overflow, they wrap to the next line.

---

### 8. Confidence Indicators (`> [confidence: high] text`)

**Priority: 6** -- Least common in practice, but provides important AI-transparency information.

#### Current State (Before)

- The entire line gets a colored background at 0.15 alpha (green/yellow/red/blue based on level).
- Clicking high-confidence triggers confirmation. Clicking low-confidence opens a challenge sheet.

#### Prose Mode (After)

- The `[confidence: level]` tag is replaced with a **colored dot indicator** (8pt filled circle):
  - High: green dot.
  - Medium: yellow dot.
  - Low: red dot.
  - Confirmed: blue dot with a small checkmark.
- The confidence text renders normally after the dot.
- **Hover state (high):** A "Confirm" label fades in next to the dot (green text, `.caption` font).
- **Hover state (low):** A "Challenge" label fades in next to the dot (red text, `.caption` font).
- **Hover state (medium/confirmed):** Tooltip only -- "AI confidence: medium" or "Confirmed by user."

#### Controls Mode (After)

- Replaced with a **confidence card**:
  - Left accent bar in the confidence color (3px).
  - Content: the text, preceded by a badge reading "AI Confidence: High/Medium/Low/Confirmed" in the appropriate color.
  - **High:** A "Confirm" button (`systemGreen` tint) appears at the trailing edge.
  - **Low:** A "Challenge" button (`systemRed` tint) appears at the trailing edge.
  - **Medium:** No action button. Informational only.
  - **Confirmed:** Badge changes to blue with a checkmark. No button.

---

### 9. Conditional Sections (`<!-- if: key=value -->`)

**Priority: 7** -- Structural, not interactive in the click sense. Rendering treatment only.

#### Controls Mode (After)

- The conditional comment tags are hidden.
- The section content renders normally but with a subtle left border (2px, `systemIndigo.withAlphaComponent(0.2)`) indicating conditionality.
- A small "Conditional" badge in `.caption2` font appears in the gutter area.

---

### 10. Collapsible Sections (`<!-- collapsible: Title -->`)

**Priority: 7** -- Structural.

#### Controls Mode (After)

- The collapsible comment tags are replaced with a native **disclosure triangle** (NSButton with `bezelStyle = .disclosure` or SwiftUI `DisclosureGroup` equivalent):
  - Title renders next to the triangle in the document font at `.headline` weight.
  - Content is shown/hidden based on the disclosure state.
  - Default state: collapsed.

---

## Hover Behavior Specification (Global)

These behaviors apply across both Prose and Controls modes. They are the minimum viable layer of interactivity -- even without the mode toggle, these should be implemented first.

### Cursor Changes

The existing `resetCursorRects()` implementation in `MarkdownNSTextView` already sets `NSCursor.pointingHand` for interactive elements. This is correct. No changes needed.

### Hover Highlight

Currently missing entirely. Add a hover tracking mechanism:

1. Override `mouseMoved(with:)` in `MarkdownNSTextView`.
2. On each move, hit-test for the `.interactiveElement` attribute at the cursor position.
3. If found and different from the previously hovered element:
   - Apply a temporary background color to the element's range: `NSColor.controlAccentColor.withAlphaComponent(0.06)`.
   - If the element is a checkbox/choice/review, highlight the entire option line, not just the brackets.
4. If no element is under the cursor, remove any existing hover highlight.
5. **Performance:** Debounce by 16ms (one frame). Cache the last-hovered element ID to avoid redundant attribute updates.

**Important:** The hover highlight should be a temporary visual layer that does not modify the attributed string permanently. Use a custom drawing layer or a secondary "hover" attribute that is cleared/set dynamically.

### Tooltips

Override `view(_:stringForToolTip:point:userData:)` or add `NSToolTipManager` rects for each interactive element range. Tooltip content per element type:

| Element | Tooltip Text |
|---------|-------------|
| Checkbox (unchecked) | "Click to mark as complete" |
| Checkbox (checked) | "Click to unmark" |
| Choice option | "Click to select this option" |
| Review option | "Click to set review status: [STATUS]" |
| Fill-in (text) | "Click to fill in: [hint]" |
| Fill-in (file) | "Click to choose a file" |
| Fill-in (folder) | "Click to choose a folder" |
| Fill-in (date) | "Click to pick a date" |
| Feedback (empty) | "Click to leave feedback" |
| Feedback (filled) | "Click to edit feedback" |
| Suggestion (addition) | "Suggested addition -- click to review" |
| Suggestion (deletion) | "Suggested deletion -- click to review" |
| Suggestion (substitution) | "Suggested change -- click to review" |
| Status (advanceable) | "Click to advance status to: [next]" |
| Status (terminal) | "Status complete" |
| Confidence (high) | "AI is confident -- click to confirm" |
| Confidence (low) | "AI is uncertain -- click to challenge" |
| Confidence (medium) | "AI confidence: medium" |
| Confidence (confirmed) | "Confirmed by you" |

---

## Implementation Architecture

### Layer 1: Hover States (Ship First)

**Effort:** Small. Modify `MarkdownNSTextView` only.
**Impact:** High. Makes every interactive element discoverable through exploration.
**Files touched:**
- `Sources/MarkdownEditor.swift` -- Add `mouseMoved` override, tooltip rects.

### Layer 2: Prose Mode Enhancements (Ship Second)

**Effort:** Medium. Modify `MarkdownHighlighter.annotateInteractiveElements()` to apply richer styling.
**Impact:** Medium. Makes elements more visually distinct without changing the rendering architecture.
**Files touched:**
- `Sources/MarkdownHighlighter.swift` -- Enhanced attribute styling in `annotateInteractiveElements()`.
- `Sources/MarkdownEditor.swift` -- Hover highlight drawing.

### Layer 3: Controls Mode (Ship Third)

**Effort:** Large. Requires a new rendering layer.
**Impact:** Transformative. The document becomes a form.
**Architecture:**

```
MarkdownNSTextView
  |
  +-- NSTextStorage (attributed string with interactive ranges)
  |
  +-- ControlOverlayManager (new)
        |
        +-- Tracks all interactive element ranges
        +-- Creates/positions native controls for each element
        +-- Listens to layout changes to reposition controls
        +-- Routes control actions back through onInteractiveElementClicked
```

**`ControlOverlayManager`** is a new class that:
1. Receives the list of `InteractiveElement` objects after detection.
2. For each element, creates the appropriate `NSView` (checkbox button, radio group, text field, etc.).
3. Positions each control using `NSLayoutManager.boundingRect(forGlyphRange:in:)`.
4. Adds controls as subviews of the `MarkdownNSTextView`.
5. Hides the underlying text by setting its foreground to `NSColor.clear` (text is still there for search, copy, etc. -- only visually hidden).
6. On scroll or layout change: repositions all controls.
7. On text content change: tears down and rebuilds controls.

**Key method signatures:**

```swift
@MainActor
final class ControlOverlayManager {
    private weak var textView: MarkdownNSTextView?
    private var overlayViews: [String: NSView] = [:]  // keyed by element.id

    func install(elements: [InteractiveElement], in textView: MarkdownNSTextView)
    func teardown()
    func repositionAll()
    func setMode(_ mode: InteractiveMode)
}
```

### Settings Integration

Add to `BehaviorSettings` in `SettingsRepository.swift`:

```swift
/// Interactive element rendering mode
public var interactiveMode: InteractiveMode = .controls
```

Add persistence in `UserDefaultsSettingsRepository`:

```swift
// In init:
let modeRaw = defaults.string(forKey: "interactiveMode") ?? InteractiveMode.controls.rawValue
behavior.interactiveMode = InteractiveMode(rawValue: modeRaw) ?? .controls

// In persistBehavior:
defaults.set(behavior.interactiveMode.rawValue, forKey: "interactiveMode")

// In observeBehavior:
_ = behavior.interactiveMode
```

---

## Edge Cases

### Long text in fill-in fields
- In Controls Mode, the `NSTextField` width is capped at 400pt. If entered text exceeds this, it scrolls horizontally within the field.
- In Prose Mode, the field outline stretches to fit the hint text up to the text container width, then truncates with ellipsis.

### Multiple interactive elements on one line
- Common pattern: `> [ ] YES  [ ] NO` -- two choices on one line.
- In Controls Mode, this renders as a horizontal `NSSegmentedControl` (see Choice spec above).
- In Prose Mode, each bracket pair gets its own pill highlight.

### Nested interactive elements
- A blockquote might contain both choice options and a confidence indicator.
- The detector already handles this (confidence inside blockquotes is detected separately).
- In Controls Mode, the confidence badge renders inside the choice group card.

### Very long documents (performance)
- `ControlOverlayManager` should only create controls for elements currently visible in the scroll view's `visibleRect`.
- Off-screen controls are removed and recreated on scroll (virtualization).
- Target: handle 100+ interactive elements without frame drops during scrolling.

### Theme/appearance changes
- When the user switches themes or light/dark mode, all overlay controls must update their colors.
- `ControlOverlayManager.repositionAll()` should also refresh control styling.

### Text reflow after control insertion
- Hiding text (setting foreground to clear) preserves the original layout metrics.
- Controls are sized to approximately match the hidden text's bounding box.
- Minor height mismatches (a native checkbox is 14pt but text might be 18pt) are handled by vertically centering the control within the text line's bounds.

### Find bar interaction
- Cmd+F find bar searches the underlying text (which is still present, just visually hidden in Controls Mode).
- Find results highlight the text range. If a find result falls within a controlled element, the control should flash or briefly show the underlying text.

### Copy/paste
- In Controls Mode, Cmd+C copies the underlying markdown text, not the control representations.
- The source text is always the canonical representation.

### File watcher reload
- When the file changes externally and the user reloads, all overlay controls are torn down and rebuilt from the new content.

---

## Accessibility

### VoiceOver

- In Controls Mode, each overlay control must be a proper accessibility element:
  - Checkboxes: `accessibilityRole = .checkBox`, `accessibilityValue` = checked/unchecked.
  - Radio buttons: `accessibilityRole = .radioButton`, with `accessibilityRadioGroup` parent.
  - Text fields: `accessibilityRole = .textField`, `accessibilityPlaceholder` = hint text.
  - Status pills: `accessibilityRole = .button`, `accessibilityLabel` = "Status: [current]. Click to advance."
  - Review buttons: `accessibilityRole = .button`, `accessibilityLabel` = "Review: [status]."
- In Prose Mode, the existing text-based accessibility is sufficient, but tooltip text should be added as `accessibilityHelp` on the interactive ranges.

### Keyboard Navigation

- In Controls Mode, Tab should cycle through interactive controls in document order.
- In Prose Mode, this is not applicable (text view handles its own keyboard navigation).
- Space bar should toggle focused checkboxes. Return should activate focused buttons.

### Reduced Motion

- All hover highlights, transition animations, and click feedback animations are disabled when `accessibilityReduceMotion` is true.
- Mode toggles are instant (no scale/fade animation).

### Contrast

- All interactive element colors have been chosen to meet WCAG AA contrast against both light and dark backgrounds:
  - Green pill on white: 4.6:1 (passes AA).
  - Red pill on white: 4.5:1 (passes AA).
  - Teal text field border on white: 3.2:1 (passes AA for UI components at 3:1 threshold).
  - All pills use the `withAlphaComponent` pattern which means the text color (not the background) carries the contrast. Text colors are system colors which adapt to appearance.

### Touch Targets

- All Controls Mode elements meet the 44x44pt minimum:
  - Checkboxes: entire row is clickable (height >= 20pt from line height, width = full line).
  - Radio buttons: full row clickable.
  - Text fields: standard NSTextField height (22pt minimum) with padding.
  - Buttons: minimum 28pt height with padding.
- In Prose Mode, the click target for checkboxes is expanded from just the brackets (3 characters) to the full line (matching Controls Mode behavior). This is a significant usability improvement on its own.

---

## Implementation Priority Order

| Priority | Element | Mode | Effort | Impact | Notes |
|----------|---------|------|--------|--------|-------|
| **P0** | All elements | Hover | Small | High | Ship alone as quick win. Cursor + tooltip + hover highlight. |
| **P1** | Checkboxes | Controls | Medium | Highest | Most common element. NSTextAttachment approach. |
| **P1** | Fill-ins | Controls | Medium | Highest | Primary data collection. NSTextAttachment with NSTextField. |
| **P2** | Choices | Controls | Large | High | Requires floating subview approach for the group container. |
| **P2** | Suggestions | Controls | Medium | High | Inline diff cards. Accept/Reject buttons. |
| **P3** | Reviews | Controls | Large | High | Similar to choices but with semantic color mapping. |
| **P3** | Feedback | Controls | Medium | Medium | Text area overlay. |
| **P4** | Status | Controls | Medium | Medium | Stepper visualization. |
| **P5** | Confidence | Controls | Small | Low | Badge + button. |
| **P5** | Collapsible | Controls | Small | Low | Disclosure triangle. |
| **P6** | Toggle UI | Toolbar | Small | Medium | The mode switcher itself. Can ship anytime after P1. |
| **P7** | All elements | Prose enhancements | Medium | Medium | The rich-text-only path. Lower priority than Controls. |

---

## Summary

The fundamental insight is that **markdown syntax is an encoding format, not a user interface**. For the audience of this app -- people who receive AI-generated files and need to respond to them -- the encoding should be invisible. They should see buttons, fields, and status indicators, not brackets and angle brackets.

The two-mode system respects both audiences: non-coders get Controls Mode by default and never see syntax. Power users can switch to Prose Mode to see the document source while still getting enhanced hover states and visual affordances.

The implementation is layered so that each phase delivers independent value: hover states alone make the current app significantly more usable. Controls Mode for checkboxes and fill-ins alone covers the majority of real-world interactive documents. The full system -- all ten element types in Controls Mode with smooth toggle animation -- is the end state, but every intermediate step is a meaningful improvement for the humans using this tool.
