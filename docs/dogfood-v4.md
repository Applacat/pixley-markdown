# Pixley v4 Dogfood Report

**Tester:** [[your name]]
**Date:** [[today's date]]
**Build:** e1dfa56 (Hybrid interactive mode + ViewModePicker)

<!-- status: not started | in progress | complete -->
**Status:** not started

---

## 1. Launch & Window Management

### 1.1 Start Window

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Start window appears on launch
- [ ] Drag-and-drop folder onto start window opens browser
- [ ] "Open Folder" button works
- [ ] Recent folders/files appear (if any saved)
- [ ] Clicking a recent item opens browser window

### 1.2 Browser Window

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Browser window opens with sidebar + detail
- [ ] Multiple browser windows can coexist (Cmd+N then open folder)
- [ ] Closing browser window doesn't kill other windows
- [ ] Window remembers size on reopen

### 1.3 Keyboard Shortcuts

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Cmd+Shift+O opens folder
- [ ] Cmd+N opens new window
- [ ] Cmd+R reloads document
- [ ] Cmd+P opens quick switcher
- [ ] Cmd+W closes folder
- [ ] Cmd+F opens find bar
- [ ] Cmd+, opens settings

---

## 2. Sidebar & Navigation

### 2.1 Folder Tree

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Folder tree loads and shows files
- [ ] Folders expand/collapse on click
- [ ] Navigate-up button works (breadcrumb)
- [ ] Non-markdown files hidden by default
- [ ] Selecting .md file shows content in detail pane

### 2.2 Quick Switcher (Cmd+P)

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Quick switcher opens
- [ ] Search filters file list
- [ ] Selecting a file navigates to it
- [ ] ESC dismisses switcher

---

## 3. Markdown Rendering

### 3.1 Plain Mode

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Text renders with syntax highlighting
- [ ] Headings are styled (sized, colored)
- [ ] Code blocks highlighted
- [ ] Links are clickable
- [ ] Scroll position saves and restores

### 3.2 Enhanced Mode

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Interactive elements show colored pills/icons
- [ ] Hover highlight on interactive elements
- [ ] Tooltips appear on hover
- [ ] Tab navigation between elements (Cmd+[ / Cmd+])
- [ ] Focus ring visible on focused element

### 3.3 Hybrid Mode (Pro)

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED
> - [ ] N/A

- [ ] Native macOS controls appear inline
- [ ] Controls interact correctly
- [ ] Falls back gracefully if not Pro

### 3.4 Liquid Glass Mode (Pro)

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED
> - [ ] N/A

- [ ] Block-level rendering works
- [ ] Glass material backgrounds visible
- [ ] Content is readable

### 3.5 View Mode Switching

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Toolbar picker shows all modes
- [ ] Switching modes re-renders without crash
- [ ] Content stays on same scroll position after switch

---

## 4. Interactive Elements

**Test file:** open the Welcome/04-Interactive-Starter.md

### 4.1 Checkboxes

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Click toggles checkbox
- [ ] Change persists to file (check in another editor)
- [ ] Multiple checkboxes work independently

### 4.2 Choices (Radio Select)

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Click selects one option
- [ ] Previously selected option deselects
- [ ] Change persists to file

### 4.3 Fill-In

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Click opens popover/input
- [ ] Typing and submitting replaces placeholder
- [ ] Date picker works for date fields
- [ ] Change persists to file

### 4.4 Review

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Click on PASS/APPROVED selects immediately
- [ ] Click on FAIL/PASS WITH NOTES prompts for notes
- [ ] Timestamp appears after selection
- [ ] Change persists to file

### 4.5 Feedback

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Click opens text input
- [ ] Submitting saves feedback to file

### 4.6 CriticMarkup (Suggestions)

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Additions {++text++} visible and styled
- [ ] Deletions {--text--} visible and styled
- [ ] Accept/reject works
- [ ] Change persists to file

### 4.7 Status

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Status label shows current state
- [ ] Click advances to next state (or shows dropdown)
- [ ] Forward-only (can't go backwards)
- [ ] Change persists to file

### 4.8 Confidence

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] High confidence: click to confirm
- [ ] Low confidence: click to challenge (prompts for input)
- [ ] Change persists to file

---

## 5. File Watching & Reload

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Edit .md file externally (e.g. VS Code)
- [ ] "Content updated" reload pill appears
- [ ] Clicking Reload refreshes content
- [ ] Interactive edits from Pixley don't trigger false reload

---

## 6. Settings

### 6.1 Appearance

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Color scheme (System/Light/Dark) applies immediately
- [ ] Syntax theme changes re-render correctly
- [ ] Font size slider works (Cmd+= / Cmd+- also)
- [ ] Font family changes apply
- [ ] Heading scale changes apply
- [ ] Line numbers toggle works

### 6.2 Behavior

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Link behavior setting works (browser vs in-app)
- [ ] Underline links toggle applies

---

## 7. AI Chat (macOS 26+)

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED
> - [ ] N/A

- [ ] Cmd+Shift+A toggles chat panel
- [ ] Sending a question gets a response
- [ ] "Thinking..." indicator shows during response
- [ ] Forget (ESC) clears conversation
- [ ] Switching documents resets chat context
- [ ] Turn counter increments
- [ ] Chat works across multiple questions in a session

---

## 8. Edge Cases & Stress

> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

- [ ] Very large .md file (>100KB) opens without hang
- [ ] Empty .md file shows gracefully (no crash)
- [ ] File with no interactive elements renders fine
- [ ] Rapidly switching between files doesn't crash
- [ ] Closing folder while file is loading doesn't crash

---

## Known Issues Log

Record bugs found during dogfooding. Don't fix — just document.

### Bug 1

**Area:** [[which section]]
**Severity:**
> - [ ] Critical (crash/data loss)
> - [ ] Major (feature broken)
> - [ ] Minor (cosmetic/annoyance)

**Description:**
<!-- feedback -->

**Steps to reproduce:**
<!-- feedback -->

---

### Bug 2

**Area:** [[which section]]
**Severity:**
> - [ ] Critical (crash/data loss)
> - [ ] Major (feature broken)
> - [ ] Minor (cosmetic/annoyance)

**Description:**
<!-- feedback -->

**Steps to reproduce:**
<!-- feedback -->

---

### Bug 3

**Area:** [[which section]]
**Severity:**
> - [ ] Critical (crash/data loss)
> - [ ] Major (feature broken)
> - [ ] Minor (cosmetic/annoyance)

**Description:**
<!-- feedback -->

**Steps to reproduce:**
<!-- feedback -->

---

## Investigation History

Things we already tried/ruled out. Don't repeat these.

- [x] "Xcode-only crash" when opening markdown files — was **breakpoints** in MarkdownHighlighter.Theme.init pausing LLDB. Not a code bug.
- [x] GutteredScrollView + configureInsets(width: 0) — broke text rendering (text invisible). Reverted in 466ba77.
- [x] Removing `var parent: MarkdownEditor` from Coordinator — refactored to individual callbacks. Did not fix the phantom crash (because it was breakpoints). Change was reverted.
- [x] LineLayoutState as @Environment vs struct property — tested both. No impact (breakpoints were the issue).
- [x] Address Sanitizer build — found nothing (code is memory-safe).
- [x] Main Thread Checker injection — found nothing (no thread violations).
- [x] SwiftData "unknown model version" — happens when reverting schema changes. Fix: delete `~/Library/Containers/com.aimd.reader/Data/Library/Application Support/default.store*`

---

## Final Verdict

> - [ ] APPROVED
> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] BLOCKED

<!-- feedback: overall notes -->
