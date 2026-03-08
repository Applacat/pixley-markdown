# Pixley Markdown v4 — Native Rendering & Missing Controls

**Version:** 1.0
**Date:** 2026-03-08
**Status:** BRD

---

## Thesis

Pixley exposes native Swift/SwiftUI/AppKit controls through markdown syntax. Just pipes. The AI and user decide what to do with them.

Previous specs dressed up use cases as features (confidence indicators = a slider with opinions). v4 strips that out: expose the controls, drop the opinions.

---

## Design Principles

1. **Classic markdown look** — inline controls render as standard macOS controls in the text flow. Not glass, not fancy. A slider looks like a slider.
2. **Glass for containers** — tables and popovers get Liquid Glass treatment. These are structural blocks, not inline controls.
3. **Just pipes** — expose the control. The AI writes labels, structure, and context. Pixley doesn't interpret what the labels mean.

---

## Part 1: Native Rendering Blocks

Markdown constructs that look bad as styled text. Rendered as SwiftUI blocks embedded inline in the NSTextView.

### Tables

**Detect:** `| col | col |` with `|---|---|` separator row.

**Render:** SwiftUI grid in a Liquid Glass container, plopped inline in the text flow. Proper column alignment, styled cells.

**Interactive elements inside cells:** Checkboxes, fill-ins, radios, etc. inside table cells are detected and interactive. Write-back targets the element's position in the source markdown, same as anywhere else.

**Write-back:** Only for interactive elements within cells. The table structure itself is display-only.

---

### Images

**Detect:** `![alt](path)` syntax.

**Render:** Actual image inline in the text flow. Local file paths resolved relative to the document.

**Write-back:** None. Display only.

---

### Code Blocks

**Detect:** Fenced code blocks with optional language identifier.

**Render:** SwiftUI framed container with syntax highlighting and a copy-to-clipboard button.

**Write-back:** None. Display only.

---

### Collapsible Sections

**Detect:** `<!-- collapsible: Title -->` ... `<!-- endcollapsible -->` (detection already exists in parser).

**Render:** Native SwiftUI DisclosureGroup. Click to expand/collapse.

**Write-back:** None. Ephemeral view state.

---

## Part 2: New Interactive Controls

New fill-in types using the existing `[[...]]` detection pattern, plus one new checkbox variant.

### Slider

**Trigger:** `[[slide MIN-MAX]]` or `[[rate MIN-MAX]]`

**Examples:**
```markdown
Priority: [[slide 1-10]]
Satisfaction: [[rate 1-5]]
Confidence: [[slide 0-100]]
```

**Native element:** NSSlider, rendered inline in the text flow as a standard macOS slider.

**Write-back:** `[[slide 1-10]]` → `7`

---

### Color Picker

**Trigger:** `[[pick color]]`

**Example:**
```markdown
Brand color: [[pick color]]
```

**Native element:** NSColorWell / SwiftUI ColorPicker, shown in a popover.

**Write-back:** `[[pick color]]` → `#FF5733`

---

### Stepper

**Trigger:** `[[pick number]]` or `[[pick number MIN-MAX]]`

**Examples:**
```markdown
Server count: [[pick number 1-20]]
Replicas: [[pick number]]
```

**Native element:** NSStepper, rendered inline.

**Write-back:** `[[pick number 1-20]]` → `3`

---

### Toggle Switch

**Trigger:** `[[toggle]]`

**Example:**
```markdown
Enable logging: [[toggle]]
Dark mode: [[toggle]]
```

**Native element:** NSSwitch, rendered inline as a standard macOS toggle.

**Write-back:** `[[toggle]]` → `on` or `off`

---

### Auditable Checkbox

**What it is:** A checkbox that auto-appends a timestamp when checked. Optionally prompts for a note. This is the primitive that replaces the old Review pattern.

**Trigger:** Documented pattern — the AI writes a checkbox with specific syntax to trigger audit behavior. The notes prompt is triggered by a documented pattern in the label (details to be defined in implementation, documented in the capabilities reference for AI consumers).

**Examples (AI writes):**
```markdown
- [ ] Deployed to staging
- [ ] Schema migration verified
- [ ] Load test completed
```

**After human checks:**
```markdown
- [x] Deployed to staging — 2026-03-08
- [x] Schema migration verified — 2026-03-08: Had to run it twice
- [ ] Load test completed
```

**Behavior:**
- Check → appends ` — YYYY-MM-DD`
- Check with notes → appends ` — YYYY-MM-DD: user's note`
- Uncheck → removes timestamp and notes
- The AI writes whatever labels it wants. Pixley doesn't interpret PASS, FAIL, APPROVED — those are just text.

---

### File/Folder Picker (Re-pickable)

**Change:** After `[[choose file]]` or `[[choose folder]]` is filled, the path renders as a clickable badge. Clicking re-opens the native picker. New selection replaces the old path.

**Current behavior:** `[[choose file]]` → `/path/to/file` (gone forever, can't re-pick).

**New behavior:** `/path/to/file` renders as a tappable path badge → click → NSOpenPanel → new path replaces old.

---

## What Gets Dropped

| Old "Feature" | What It Actually Was | Replacement |
|---------------|---------------------|-------------|
| Confidence indicators | A slider with high/medium/low opinions | Slider control — `[[slide 0-100]]` or `[[rate 1-5]]` |
| Review pattern (PASS/FAIL/APPROVED) | An auditable checkbox with keyword opinions | Auditable checkbox — AI writes any label it wants |
| Conditional sections | Display logic, not a control | Punted (not a pipe) |

---

## Technical Considerations

### Embedding SwiftUI in NSTextView

Tables, images, code blocks, and collapsibles need to render as SwiftUI views inline in the NSTextView text flow. Approach options:

- **NSTextAttachmentViewProvider** (macOS 12+) — provides a SwiftUI/NSView for a text attachment. The attachment occupies space in the text layout.
- **Custom NSTextAttachment subclass** — draw into the text layout directly.
- **Overlay approach** — position SwiftUI views on top of the text view at computed rects.

### Inline Controls in Text Flow

Slider, stepper, toggle need to sit inline in attributed text. Same embedding challenge but smaller — single-line controls rather than multi-line blocks.

### Table Cell Interaction

When a table renders as a SwiftUI overlay, interactive elements inside cells need click detection. The SwiftUI table handles its own hit testing — elements inside it use SwiftUI's standard interaction model, not the NSTextView click detection path.

### Image Security

Local file paths only for v1. Remote URLs introduce network requests, caching, and potential security concerns. Can add remote support later.

---

## Summary of All Controls (v4)

### Inline (standard macOS controls in text flow)
| Control | Trigger | Writes back |
|---------|---------|-------------|
| Checkbox | `- [ ]` / `- [x]` | `[ ]` ↔ `[x]` |
| Auditable checkbox | Documented pattern | `[x] — DATE` or `[x] — DATE: notes` |
| Radio | Blockquote + checkboxes | `[x]` on one, `[ ]` on rest |
| Slider | `[[slide MIN-MAX]]` / `[[rate MIN-MAX]]` | Number |
| Stepper | `[[pick number]]` / `[[pick number MIN-MAX]]` | Number |
| Toggle | `[[toggle]]` | `on` / `off` |
| Dropdown | `<!-- status: a \| b \| c -->` | Selected state |
| File path (re-pickable) | Filled `[[choose file]]` | New path |

### Popover (opens on click)
| Control | Trigger | Writes back |
|---------|---------|-------------|
| Text input | `[[enter ...]]` | Text replacing `[[...]]` |
| Date picker | `[[pick date]]` | `YYYY-MM-DD` |
| Color picker | `[[pick color]]` | `#hex` |
| File picker | `[[choose file]]` | File path |
| Folder picker | `[[choose folder]]` | Folder path |
| Text area | `<!-- feedback -->` | `<!-- feedback: text -->` |
| Accept/Reject | CriticMarkup | Clean text |

### Rendering blocks (SwiftUI in text flow, display-only)
| Block | Trigger |
|-------|---------|
| Table | `\| col \| col \|` with separator |
| Image | `![alt](path)` |
| Code block | Fenced ``` with language |
| Collapsible | `<!-- collapsible: Title -->` |
