# Pixley Markdown Smoke Test Checklist

**Tester:** [[fill-in: name | Your name]]
**Date:** [[fill-in: date | Test date]]
**Build:** [[fill-in: text | Build number or commit hash]]
**Overall verdict:** [[status: not-started > in-progress > pass > fail]]

---

## 1.0 Core — Launch & Window Management

- [ ] App launches without crash
- [ ] Start window appears (Pixelmator-style launcher)
- [ ] Drag-and-drop folder onto Start window opens browser
- [ ] "Open Folder" button works from Start window
- [ ] Recent folders appear in Start window
- [ ] Recent files appear in Start window
- [ ] Cmd+N opens new Start window
- [ ] Cmd+Shift+O opens folder picker
- [ ] Open Recent menu shows folders and files
- [ ] Clear Menu removes all recents
- [ ] Multiple browser windows can coexist independently
- [ ] Cmd+W closes the current folder
- [ ] About panel shows credits and version

**Launch notes:** [[fill-in: text | Any launch issues]]

## 1.0 Core — Sidebar & Navigation

- [ ] Folder tree loads and displays hierarchy
- [ ] Folders expand/collapse on click
- [ ] Markdown files (.md, .markdown) are selectable
- [ ] Non-markdown files are hidden
- [ ] Navigate-up button returns to parent
- [ ] Filter field narrows the tree
- [ ] Selecting a file loads it in the detail view
- [ ] Sidebar can be collapsed/expanded
- [ ] File selection persists when collapsing/expanding sidebar
- [ ] Bookmarks (stars) toggle in sidebar

**Sidebar notes:** [[fill-in: text | Any sidebar issues]]

## 1.0 Core — Markdown Rendering

- [ ] Plain text renders correctly
- [ ] Headings (H1-H6) render with correct sizing
- [ ] Bold, italic, strikethrough render
- [ ] Code blocks render with syntax highlighting
- [ ] Inline code renders
- [ ] Links render and are clickable
- [ ] Internal anchor links (#heading) scroll to target
- [ ] External links open in default browser
- [ ] Lists (ordered and unordered) render
- [ ] Blockquotes render
- [ ] Horizontal rules render
- [ ] Large files (>100KB) load without freeze
- [ ] Empty files show without error

**Rendering notes:** [[fill-in: text | Any rendering issues]]

## 1.0 Core — Themes & Appearance

- [ ] System/Light/Dark color scheme switches correctly
- [ ] Solarized theme applies (light + dark)
- [ ] Dracula theme applies
- [ ] Monokai theme applies
- [ ] Nord theme applies
- [ ] One Dark theme applies
- [ ] GitHub theme applies (light + dark)
- [ ] Theme auto-switches light/dark variant with color scheme
- [ ] Font size slider works (10-32pt range)
- [ ] Cmd+= increases font size
- [ ] Cmd+- decreases font size
- [ ] Font family changes (System, Serif, Sans-Serif, Monospaced)
- [ ] Heading scale changes (Compact, Normal, Large)
- [ ] Settings persist after app restart

**Appearance notes:** [[fill-in: text | Any appearance issues]]

## 1.0 Core — Reading Experience

- [ ] Scroll position shows percentage badge (top-right)
- [ ] Scroll position saves per file
- [ ] Scroll position restores when returning to a file
- [ ] Find bar opens with Cmd+F
- [ ] Find highlights matches
- [ ] Cmd+G finds next match
- [ ] Cmd+Shift+G finds previous match
- [ ] Esc dismisses find bar
- [ ] Quick Switcher opens with Cmd+P
- [ ] Quick Switcher filters files by name
- [ ] Quick Switcher selects file on Enter

**Reading notes:** [[fill-in: text | Any reading experience issues]]

## 1.0 Core — File Watching

- [ ] Editing a viewed file externally shows "Content updated" pill
- [ ] Clicking Reload updates the content
- [ ] Cmd+R reloads the document
- [ ] Scroll position preserved after reload

**File watching notes:** [[fill-in: text | Any file watching issues]]

## 1.0 Core — Mascot & Dock Icon

- [ ] Pixley faces left/right options appear in Settings > Appearance
- [ ] Selecting a direction updates the Dock icon immediately
- [ ] Chosen direction persists after restart
- [ ] App icon in About panel matches direction

**Mascot notes:** [[fill-in: text | Any mascot issues]]

---

## 1.5 Interactive — Line Numbers

- [ ] Toggle "Show Line Numbers" in Settings > Appearance
- [ ] Line numbers appear in gutter when ON
- [ ] Line numbers disappear when OFF
- [ ] Text content is fully visible when line numbers are ON
- [ ] Line numbers stay aligned with text lines while scrolling
- [ ] Line numbers update after file reload
- [ ] Gutter click toggles bookmark (orange dot + orange number)
- [ ] Line numbers scale with font size changes
- [ ] Line numbers use theme-appropriate color

**Line number notes:** [[fill-in: text | Any line number issues]]

## 1.5 Interactive — Checkboxes

- [ ] `- [ ]` renders as unchecked checkbox
- [ ] `- [x]` renders as checked checkbox
- [ ] Clicking toggles state and writes back to file
- [ ] Checkbox state persists after reload

**Checkbox notes:** [[fill-in: text | Any checkbox issues]]

## 1.5 Interactive — Choices (Radio)

- [ ] `[[choose: A | B | C]]` renders as selectable options
- [ ] Clicking an option selects it
- [ ] Selection writes back to file
- [ ] Previously selected option shows as selected on reload

**Choice notes:** [[fill-in: text | Any choice issues]]

## 1.5 Interactive — Fill-In Fields

- [ ] `[[fill-in: text | hint]]` shows clickable placeholder
- [ ] Clicking opens popover with text field
- [ ] Submitting writes value back to file
- [ ] `[[fill-in: date | hint]]` shows date picker
- [ ] `[[fill-in: file | hint]]` opens file picker
- [ ] `[[fill-in: folder | hint]]` opens folder picker
- [ ] Filled values display inline after submission

**Fill-in notes:** [[fill-in: text | Any fill-in issues]]

## 1.5 Interactive — Feedback

- [ ] `[[feedback: prompt]]` shows clickable marker
- [ ] Clicking opens popover with text area
- [ ] Submitting writes feedback back to file

**Feedback notes:** [[fill-in: text | Any feedback issues]]

## 1.5 Interactive — Review

- [ ] `[[review: question | Approve | Reject]]` renders options
- [ ] Clicking an option selects it
- [ ] Options with `(notes)` suffix open popover for notes
- [ ] Selection + notes write back to file

**Review notes:** [[fill-in: text | Any review issues]]

## 1.5 Interactive — Status

- [ ] `[[status: draft > review > done]]` renders current state
- [ ] Single next state: click advances directly
- [ ] Multiple next states: click shows dropdown menu
- [ ] State change writes back to file

**Status notes:** [[fill-in: text | Any status issues]]

## 1.5 Interactive — Confidence & Suggestions

- [ ] `[[confidence: high | claim]]` renders with indicator
- [ ] High confidence: click to confirm
- [ ] Low/medium confidence: click to challenge (popover)
- [ ] `{~~old~>new~~}` CriticMarkup renders with accept/reject
- [ ] Accepting replaces old text with new
- [ ] Rejecting keeps old text

**Confidence/suggestion notes:** [[fill-in: text | Any issues]]

## 1.5 Interactive — Navigation & Modes

- [ ] Cmd+] jumps to next interactive element
- [ ] Cmd+[ jumps to previous interactive element
- [ ] Tab cycles through interactive elements with focus ring
- [ ] Esc clears Tab focus
- [ ] Enhanced mode shows styled interactive elements
- [ ] Plain mode shows raw markdown (checkboxes still toggle)
- [ ] Hover highlights interactive elements
- [ ] Click flash feedback on activation
- [ ] Progress bars appear on section headings

**Navigation notes:** [[fill-in: text | Any navigation issues]]

## 1.5 Interactive — Pro Gate

- [ ] Free users see checkbox toggle (not gated)
- [ ] Free users clicking Pro elements see upgrade popover
- [ ] Upgrade popover has purchase button
- [ ] After purchase, Pro elements become interactive immediately
- [ ] Restore Purchase works
- [ ] Pro status shows in Settings > Pro tab

**Pro gate notes:** [[fill-in: text | Any Pro gate issues]]

## 1.5 Interactive — AI Chat (macOS 26+)

- [ ] Chat panel toggles with Cmd+Shift+A
- [ ] "Ask about this document" prompt appears
- [ ] Sending a question returns a response
- [ ] Chat references document content accurately
- [ ] "Forget" resets the conversation
- [ ] Chat summary persists per document
- [ ] Switching documents loads saved summary
- [ ] FM tools (listDocuments, getDocumentHistory) work
- [ ] Availability check shows when model unavailable

**AI Chat notes:** [[fill-in: text | Any AI Chat issues]]

---

## Final Assessment

**Blockers found:** [[fill-in: text | List any P0 blockers]]
**Regressions found:** [[fill-in: text | List any regressions from previous builds]]
**Polish items:** [[fill-in: text | List any P2 cosmetic issues]]

**Ship decision:** [[review: Ready to ship? | Ship it | Needs fixes (notes) | Block release (notes)]]
