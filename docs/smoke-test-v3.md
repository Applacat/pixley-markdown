# Pixley Markdown v3.0 Smoke Test

**Tester:** [[fill-in: name | Your name]]
**Date:** [[fill-in: date | Test date]]
**Build:** [[fill-in: text | Commit hash]]
**Overall verdict:** [[status: not-started > in-progress > pass > fail]]

---

## 3.0 — View Mode Picker

- [ ] Toolbar shows view mode picker (segmented or menu)
- [ ] Four modes available: Plain, Enhanced, Hybrid, Liquid Glass
- [ ] Switching modes re-renders the document immediately
- [ ] Mode selection persists in Settings > Behavior
- [ ] Mode selection survives app restart
- [ ] Hybrid and Liquid Glass show Pro gate for free users
- [ ] Switching modes does not lose scroll position

**View mode notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Plain Mode

- [ ] Text renders as monospaced raw markdown
- [ ] No colored pills, highlights, or hover effects
- [ ] Checkboxes still toggle on click
- [ ] Check marks render as styled glyphs (not raw `[x]`)
- [ ] Pro elements are NOT interactive (no popover on click)
- [ ] Links still work

**Plain mode notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Enhanced Mode

- [ ] Interactive elements render with colored pills/highlights
- [ ] Hover shows accent-color background on interactive elements
- [ ] Click shows flash feedback
- [ ] Checkboxes toggle with visual feedback
- [ ] Choices show as styled blockquotes with selectable options
- [ ] Fill-ins show `[[value]]` or `[[placeholder]]` inline
- [ ] Status shows current state with styled pill
- [ ] Confidence shows with level indicator
- [ ] CriticMarkup renders with colored markers (`{++add++}`, `{--del--}`, `{~~old~>new~~}`)
- [ ] Progress bars appear on section headings with checkboxes

**Enhanced mode notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Hybrid Mode (Pro)

- [ ] Text renders as Enhanced (syntax-highlighted)
- [ ] Native macOS controls appear inline for interactive elements:
  - [ ] Checkbox → Toggle(.checkbox)
  - [ ] Choice (<=4 options) → Segmented Picker
  - [ ] Choice (>4 options) → Menu Picker
  - [ ] Fill-in text → TextField with Save button
  - [ ] Fill-in date → Graphical DatePicker
  - [ ] Fill-in file/folder → Button with icon
  - [ ] Feedback → TextEditor with Submit button
  - [ ] Status → Menu Picker with "Status:" label
  - [ ] Confidence → Gauge + Confirm/Challenge button
  - [ ] Suggestion → Diff view with Accept/Reject buttons
  - [ ] Review → Segmented Picker + notes field
  - [ ] Collapsible → DisclosureGroup
- [ ] Native controls update the file on interaction
- [ ] Controls reflect current values from file
- [ ] Scrolling through many controls is smooth

**Hybrid mode notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Liquid Glass Mode (Pro)

### Structure & Layout

- [ ] Document renders as SwiftUI blocks (not NSTextView)
- [ ] H1 sections wrap in glass material containers
- [ ] H2 nests inside H1 glass with visual depth
- [ ] H3 nests inside H2 (compounding depth)
- [ ] H4 nests inside H3
- [ ] Non-heading content (paragraphs, lists) renders between glass blocks
- [ ] Large documents scroll smoothly (LazyVStack performance)

### Glass Behavior

- [ ] Glass containers have visible frosted-glass effect
- [ ] Glass depth increases with heading nesting level
- [ ] Glass appearance adapts to Light/Dark mode
- [ ] Glass appearance adapts to color scheme changes

### Collapsible Headings

- [ ] Clicking a heading collapses its section
- [ ] Collapsed heading shows line count badge
- [ ] Clicking again expands the section
- [ ] Collapse state is per-session (resets on file switch)

### Typography

- [ ] SF Mono renders uniformly across all text
- [ ] Headings scale correctly (H1 largest → H6 smallest)
- [ ] Bold, italic, strikethrough render within glass blocks
- [ ] Inline code renders with distinct background

### Content Types

- [ ] Code blocks render in glass cards with copy button
- [ ] Copy button copies code to clipboard
- [ ] Links are tappable and open in browser
- [ ] Lists render with proper indentation
- [ ] Blockquotes render with visual distinction
- [ ] Horizontal rules render as separators

### Native Controls (within Glass)

- [ ] All interactive elements from Hybrid mode work inside glass blocks
- [ ] Control changes write back to file immediately
- [ ] Controls reflect current file values

### Search in Glass

- [ ] Cmd+F opens search overlay
- [ ] Matching text highlights yellow within glass blocks
- [ ] Search navigates between matches

**Liquid Glass notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Fill-In Re-Edit

### Text Fill-Ins

- [ ] Click unfilled `[[placeholder]]` — popover opens with empty text field
- [ ] Type value, press Enter — value writes back, shows as `[[value]]`
- [ ] Click filled `[[value]]` — popover re-opens with current value pre-filled
- [ ] Edit value, press Enter — new value writes back
- [ ] Press Escape — popover closes, value unchanged
- [ ] Click Submit button — same as Enter
- [ ] Popover does NOT auto-submit on re-open (no blink-and-disappear)

### Date Fill-Ins

- [ ] Click unfilled date `[[pick date]]` — date picker popover opens
- [ ] Select date — writes back as `YYYY-MM-DD`
- [ ] Click filled date `[[2026-03-10]]` — date picker re-opens with saved date
- [ ] Change date — new date writes back

### File/Folder Fill-Ins

- [ ] Click unfilled `[[choose file]]` — NSOpenPanel opens
- [ ] Select file — path writes back
- [ ] Click filled file path — popover opens with path for re-edit
- [ ] Click unfilled `[[choose folder]]` — NSOpenPanel for directories
- [ ] Select folder — path writes back
- [ ] Click filled folder path — popover opens for re-edit

### Feedback Re-Edit

- [ ] Click feedback marker — text area popover opens
- [ ] Submit feedback — writes back as HTML comment
- [ ] Click feedback with existing text — popover re-opens with text pre-filled
- [ ] Edit and resubmit — updated text writes back

**Fill-in re-edit notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Interactive Element Navigation

- [ ] Cmd+] jumps to next interactive element
- [ ] Cmd+[ jumps to previous interactive element
- [ ] Tab cycles forward through all interactive elements
- [ ] Shift+Tab cycles backward
- [ ] Focus ring draws around focused element
- [ ] Return/Space activates the focused element
- [ ] Esc clears focus ring
- [ ] Navigation wraps around (last → first, first → last)
- [ ] Navigation works across fragmented attribute ranges (fill-ins with brackets)

**Navigation notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Folder Watcher Stability

- [ ] Open a folder and select a file
- [ ] Click interactive elements rapidly — no "Content updated" pill appears
- [ ] Edit the file externally — "Content updated" pill appears within 2 seconds
- [ ] Click Reload — content updates
- [ ] Sidebar does NOT flash or re-render on every element click
- [ ] Interact with fill-in popover — popover stays open, no flicker

**Folder watcher notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Write-Back Integrity

### Atomic Operations

- [ ] Toggle a checkbox — only that checkbox changes in file
- [ ] Select a choice — only that choice group changes
- [ ] Fill in a value — only that field changes
- [ ] Leave feedback — comment inserts without corrupting nearby content
- [ ] Change status — only status line changes
- [ ] Accept a suggestion — markup replaced cleanly
- [ ] Reject a suggestion — markup removed cleanly

### Edge Cases

- [ ] Rapid toggle of same checkbox (click-click-click) — state consistent
- [ ] Fill-in then immediately switch files — value saved
- [ ] Edit file externally while popover is open — popover stays, reload deferred
- [ ] Toggle checkbox near end of file — no truncation
- [ ] Unicode content near interactive elements — ranges correct

### File Watching After Write-Back

- [ ] After write-back, FileWatcher does NOT show reload pill (suppression works)
- [ ] External edit AFTER write-back still triggers reload pill

**Write-back notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Pro Gate

- [ ] Checkboxes always work (free tier)
- [ ] Clicking Pro element as free user shows upgrade popover
- [ ] Upgrade popover shows element name and price
- [ ] Upgrade popover has button linking to Settings > Pro
- [ ] After purchase, all elements become interactive
- [ ] Hybrid mode available after purchase
- [ ] Liquid Glass mode available after purchase
- [ ] AI bulk edit tool unlocked after purchase
- [ ] Restore Purchase recovers entitlement

**Pro gate notes:** [[fill-in: text | Any issues]]

---

## 3.0 — AI Chat (macOS 26+)

### Basic Functionality

- [ ] Cmd+Shift+A toggles chat panel
- [ ] Chat panel appears as inspector (right side)
- [ ] Sending a question returns a response
- [ ] Response references current document content accurately
- [ ] "Thinking..." indicator shows during response generation
- [ ] 30-second timeout prevents infinite hang
- [ ] "Forget" button resets conversation

### Context & Memory

- [ ] Chat summary persists per document (survives app restart)
- [ ] Switching documents loads saved summary automatically
- [ ] FM tools: "What documents are in this folder?" returns file list
- [ ] FM tools: "What did we discuss about [file]?" returns history
- [ ] Per-turn condensation keeps context window manageable

### AI Bulk Edit (Pro)

- [ ] Ask AI to "mark all checkboxes as done" — checkboxes toggle
- [ ] Ask AI to "fill in the project name as Starlight" — fill-in updates
- [ ] Ask AI to "set status to review" — status advances
- [ ] Free users asking for edits see upgrade prompt
- [ ] AI edits trigger proper write-back (file updates)
- [ ] AI edits reflect immediately in the rendered view

### Error Handling

- [ ] Availability check shows message when FM unavailable
- [ ] Guardrail violation shows appropriate message (not crash)
- [ ] Context window exceeded shows appropriate message
- [ ] Unsupported language shows appropriate message

**AI Chat notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Dock Icon & Branding

- [ ] App name shows "Pixley Markdown" in menu bar
- [ ] About panel shows "Pixley Markdown"
- [ ] Dock icon is correctly sized (same as other apps, not oversized)
- [ ] Mascot direction (left/right) changes Dock icon
- [ ] Direction persists after restart
- [ ] Start window shows Pixley mascot (not "AIMD")

**Branding notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Settings Persistence

- [ ] All Appearance settings survive restart (scheme, font size, family, heading scale, line numbers, theme, mascot direction)
- [ ] All Behavior settings survive restart (link behavior, underline links, interactive mode)
- [ ] Pro purchase state survives restart
- [ ] Recent folders survive restart
- [ ] Recent files survive restart
- [ ] Chat summaries survive restart

**Settings notes:** [[fill-in: text | Any issues]]

---

## 3.0 — Regression Checks

> Quick pass to ensure v1.0/v1.5 features still work after v3.0 changes.

- [ ] Start window launches correctly
- [ ] Folder tree loads
- [ ] File selection renders markdown
- [ ] All 7 syntax themes apply
- [ ] Cmd+F find works
- [ ] Cmd+P Quick Switcher works
- [ ] Line number gutter works
- [ ] File watching shows reload pill for external edits
- [ ] Scroll position saves/restores per file

**Regression notes:** [[fill-in: text | Any issues]]

---

## Final Assessment

**Blockers (P0):** [[fill-in: text | Any ship-blocking issues]]
**Bugs (P1):** [[fill-in: text | Functional bugs that need fixes]]
**Polish (P2):** [[fill-in: text | Cosmetic or minor UX issues]]

**Ship decision:** [[review: Ready to ship v3.0? | Ship it | Needs fixes (notes) | Block release (notes)]]
