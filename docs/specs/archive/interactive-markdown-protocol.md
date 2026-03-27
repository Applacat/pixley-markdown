# Pixley Interactive Markdown Protocol

**Version:** 1.1 draft
**Date:** 2026-03-07
**Status:** Design

## Overview

Pixley Markdown Reader detects specific markdown patterns and makes them interactive. The human responds through the document — checking boxes, answering questions, filling blanks, picking options, choosing files, leaving feedback, and approving sections. Changes save back to the `.md` file so the AI can see them.

The same patterns are documented in a **Setup Prompt** that users copy-paste into their AI tools (ChatGPT, Claude, Cursor, etc.) so the AI knows how to write actionable documents.

## Core Rule

**Checkboxes outside blockquotes = multi-select (task lists).**
**Checkboxes inside blockquotes = single-select (radio buttons).**

This single rule unifies yes/no questions, multiple choice, and approvals — they're all "choices in a blockquote" with radio behavior.

## The Protocol

### 1. Checkboxes (Task Lists)

**Pattern:** Standard GitHub-flavored markdown task lists.

```markdown
- [ ] Unchecked task
- [x] Completed task
```

**Interaction:** Click toggles between `[ ]` and `[x]`. Multiple items can be checked independently.

**Detection:** Regex — `^[\t ]*[-*+][\t ]+\[([ xX])\]` — only outside blockquotes.

**Write-back:** Single character replacement (`' '` ↔ `'x'`).

---

### 2. Choices (Radio Buttons in Blockquotes)

**Pattern:** Blockquote containing 2+ checkbox lines. Selecting one deselects the others (radio behavior).

**Yes/No:**

```markdown
> **Should we use a database for this?**
> [ ] YES  [ ] NO
```

**Multiple Choice:**

```markdown
> **Which architecture should we use?**
> [ ] A. MVC — Simple, fast to build
> [ ] B. MVVM — Better testability
> [ ] C. TCA — Full unidirectional flow
```

**Responded state:**

```markdown
> **Which architecture should we use?**
> [ ] A. MVC — Simple, fast to build
> [x] B. MVVM — Better testability
> [ ] C. TCA — Full unidirectional flow
```

**Interaction:** Click an option → selects it, deselects all others in the same blockquote group.

**Detection:** Blockquote containing 2+ checkbox lines. Yes/No is a special case (exactly 2 options on one line with `YES` / `NO` labels) — same radio behavior either way.

**Write-back:** Toggle `[ ]` ↔ `[x]`, deselect others in the same blockquote group.

**Design note:** The blockquote is the grouping mechanism. The AI can use yes/no for binary questions, lettered options for multiple choice — detection and behavior are identical. No separate patterns needed.

---

### 3. Fill-in-the-Blank

**Pattern:** Double-bracket placeholders with type hints.

**Text input (default):**

```markdown
Project name: [[enter project name]]
API endpoint: [[enter URL]]
Deadline: [[pick date]]
```

**File/Folder picker:**

```markdown
Config file: [[choose file]]
Output directory: [[choose folder]]
```

**Responded state:**

```markdown
Project name: My App
Config file: /Users/steve/projects/config.json
Output directory: /Users/steve/Desktop/output
```

**Interaction:**
- `[[enter ...]]` / `[[pick date]]` → popover or inline text field → user types → placeholder replaced with value.
- `[[choose file]]` → triggers native macOS file picker (NSOpenPanel) → placeholder replaced with selected file path.
- `[[choose folder]]` → triggers native macOS folder picker (NSOpenPanel) → placeholder replaced with selected folder path.

**Detection:** Regex — `\[\[([^\]]+)\]\]`

**Type hint detection:** Match the text inside brackets against known prefixes:
- Starts with `choose file` → file picker
- Starts with `choose folder` → folder picker
- Starts with `pick date` → date picker (future)
- Everything else → text input (hint text shown as placeholder)

**Write-back:** Replace the entire `[[...]]` with the user's input or selected path.

**Design note:** Double brackets are uncommon in standard markdown and won't conflict with links (`[text](url)`) or images. The text inside serves dual purpose: type hint for Pixley's detection engine AND human-readable label. The file/folder picker gives the AI access to real filesystem paths — the human selects, the AI receives a concrete URL it can use.

---

### 4. Inline Comments / Feedback

**Pattern:** HTML comment with a `feedback` marker.

```markdown
Here is the proposed API design for the user service.

<!-- feedback -->
```

**Responded state:**

```markdown
Here is the proposed API design for the user service.

<!-- feedback: Looks good, but add rate limiting to the auth endpoint. -->
```

**Interaction:** Click the feedback marker → popover or inline text field → user types comment → saved inside the HTML comment.

**Detection:** Regex — `<!--\s*feedback\s*(:\s*(.*?))?\s*-->`

**Write-back:** Replace `<!-- feedback -->` with `<!-- feedback: [user's text] -->`.

**Design note:** HTML comments are invisible in most markdown renderers, so the feedback is "metadata" — visible in Pixley but not in GitHub/GitLab previews. This is intentional: feedback is for the AI, not for the rendered document. Pixley renders these as visible feedback widgets.

---

### 5. Reviews (Approvals & QA)

**Pattern:** Blockquote with review-status markers. Two variants: simple approval and QA review.

**Simple Approval:**

```markdown
> **Review: Database Schema v2**
> [ ] APPROVED
```

**Responded state:**

```markdown
> **Review: Database Schema v2**
> [x] APPROVED — 2026-03-07
```

**QA Review:**

```markdown
> **QA: Login Flow v2**
> [ ] PASS
> [ ] FAIL
> [ ] PASS WITH NOTES
> [ ] BLOCKED
> [ ] N/A
```

**Responded states:**

```markdown
> **QA: Login Flow v2**
> [x] PASS — 2026-03-07
```

```markdown
> **QA: Login Flow v2**
> [x] FAIL — 2026-03-07: Auth token not refreshing after expiry
```

```markdown
> **QA: Login Flow v2**
> [x] PASS WITH NOTES — 2026-03-07: Works but slow on first load (~3s)
```

```markdown
> **QA: Login Flow v2**
> [x] BLOCKED — 2026-03-07: Waiting on API endpoint deployment
```

**Interaction:**
- **APPROVED / PASS** → toggles checkbox, appends date. No notes prompt.
- **FAIL / PASS WITH NOTES / BLOCKED** → toggles checkbox, appends date, then immediately shows a text input popover for notes. Notes are appended after the date as `: [user's notes]`.
- **N/A** → toggles checkbox, appends date. No notes prompt.
- All options use radio behavior within the blockquote (selecting one deselects others).

**Detection:** Blockquote containing any of these keywords as checkbox labels: `APPROVED`, `PASS`, `FAIL`, `PASS WITH NOTES`, `BLOCKED`, `N/A`.

**Write-back:**
- Toggle `[ ]` ↔ `[x]`, deselect others in the same blockquote group.
- On selection: append ` — YYYY-MM-DD`.
- On selection of FAIL/PASS WITH NOTES/BLOCKED: append ` — YYYY-MM-DD: ` and prompt for notes.
- On deselection: remove the date suffix and any notes.

**Design note:** Simple approval (single `APPROVED` checkbox) and QA review (multiple status options) are both "review" patterns — blockquote checkboxes with date stamps. The difference is cardinality: one option vs many. Both detected by the same keyword scan. The notes prompt on failure/blocked statuses captures the "why" — critical for QA workflows where the AI needs to know what went wrong.

---

### 6. CriticMarkup (Inline Suggestions)

**Pattern:** CriticMarkup syntax for AI-proposed edits that the human accepts or rejects inline.

**Additions:**

```markdown
The API should {++include rate limiting++} for all public endpoints.
```

**Deletions:**

```markdown
The system {--currently uses polling but--} will switch to WebSockets.
```

**Substitutions:**

```markdown
Deploy to {~~staging~>production~~} after QA passes.
```

**Highlights with comments:**

```markdown
{==This endpoint has no authentication==}{>>Should we add OAuth here?<<}
```

**Interaction:** Pixley renders additions in green, deletions in red/strikethrough, substitutions as old→new. Each suggestion shows Accept/Reject buttons. Accepting applies the change to the source text. Rejecting removes the CriticMarkup wrapper, leaving the original.

**Detection:** Regex patterns:
- Addition: `\{\+\+(.+?)\+\+\}`
- Deletion: `\{--(.+?)--\}`
- Substitution: `\{~~(.+?)~>(.+?)~~\}`
- Highlight: `\{==(.+?)==\}\{>>(.+?)<<\}`

**Write-back:**
- Accept addition: `{++text++}` → `text`
- Reject addition: `{++text++}` → (removed)
- Accept deletion: `{--text--}` → (removed)
- Reject deletion: `{--text--}` → `text`
- Accept substitution: `{~~old~>new~~}` → `new`
- Reject substitution: `{~~old~>new~~}` → `old`

**Design note:** CriticMarkup is an existing open standard used in Obsidian, MultiMarkdown, and academic writing tools. Key advantage: **live updates without reload**. When the AI writes CriticMarkup into a watched file, Pixley can render the suggestions immediately and the human responds without a full document reload cycle. This is the only pattern where the AI proposes changes to the document's own content (all other patterns are structured response points). It's "respond, don't edit" because the human still decides — the AI proposes, the human disposes.

---

### 7. Status Indicators (State Machines)

**Pattern:** HTML comment defining allowed status transitions, followed by a status line.

```markdown
<!-- status: draft | review | approved | implemented -->
**Status:** draft
```

**Responded states (progression):**

```markdown
<!-- status: draft | review | approved | implemented -->
**Status:** review
```

```markdown
<!-- status: draft | review | approved | implemented -->
**Status:** approved — 2026-03-07
```

**Interaction:** Click the status label → shows the allowed next states (only valid transitions). Clicking advances the status. Terminal states (`approved`, `implemented`) append a date stamp.

**Detection:** Regex — `<!--\s*status:\s*(.+?)\s*-->` followed by `\*\*Status:\*\*\s*(\w+)`

**Transition rules:**
- Only forward transitions by default (draft→review, not review→draft)
- The `|` separators define the ordered progression
- AI defines the valid states; Pixley enforces the transition order

**Write-back:** Replace the status word (and optionally append date on terminal states).

**Design note:** This gives documents a lifecycle. AI can check "what status is the spec at?" and act accordingly. Combined with Approvals, this creates a full review workflow: draft → review → human approves → status advances to approved.

---

### 8. Confidence Indicators

**Pattern:** Blockquote with confidence level marker on AI recommendations.

```markdown
> [confidence: high] Use REST for the public API
> [confidence: medium] Consider GraphQL for the admin dashboard
> [confidence: low] WebSocket might be needed for real-time updates
```

**Interaction:** Pixley renders these with visual treatment — green/yellow/red badges or opacity. Clicking a low-confidence item opens a feedback popover so the human can challenge or confirm the recommendation. Clicking a high-confidence item can quick-approve it.

**Detection:** Regex — `>\s*\[confidence:\s*(high|medium|low)\]\s*(.+)`

**Write-back:**
- Challenge: appends `<!-- feedback: [user's challenge] -->` after the line
- Confirm: changes to `[confidence: confirmed]`

**Design note:** This is metadata about the AI's own certainty. It helps humans focus review effort — skip high-confidence items, scrutinize low-confidence ones. The AI should use these when it's genuinely uncertain, not on every line.

---

### 9. Conditional / Collapsible Sections

**Pattern:** HTML comments marking sections that show/hide based on earlier decisions, or that can be collapsed/expanded.

**Conditional (based on a choice):**

```markdown
<!-- if: database = PostgreSQL -->
## PostgreSQL Setup
Run `docker-compose up -d postgres` and configure...
<!-- endif -->

<!-- if: database = SQLite -->
## SQLite Setup
The database file will be created at `~/data/app.db`...
<!-- endif -->
```

**Collapsible:**

```markdown
<!-- collapsible: Details -->
This section contains additional context that isn't needed for the
primary decision but provides background information...
<!-- endcollapsible -->
```

**Interaction:**
- **Conditional:** When the human selects "PostgreSQL" in a Choice block labeled `database`, Pixley shows the PostgreSQL section and hides the SQLite section. Sections for unselected options are visually hidden (dimmed or collapsed) but remain in the source markdown.
- **Collapsible:** Renders as a disclosure triangle / expandable section. Click to toggle. State is view-only — no write-back needed.

**Detection:**
- Conditional: `<!--\s*if:\s*(\w+)\s*=\s*(.+?)\s*-->` paired with `<!--\s*endif\s*-->`
- Collapsible: `<!--\s*collapsible:\s*(.+?)\s*-->` paired with `<!--\s*endcollapsible\s*-->`

**Write-back:** Conditionals don't write back — they're purely visual. The underlying choice that controls them writes back via the Choice pattern. Collapsible state is ephemeral (view-only toggle).

**Design note:** Conditionals let the AI write one document with multiple paths. Instead of "if you chose PostgreSQL, see section 5" — the document just shows the relevant section automatically. This keeps documents clean and focused. The conditional references a Choice element by label name, creating a relationship between interactive elements. Collapsibles reduce visual noise for long documents without losing content.

---

## Rendering Enhancements

These are not interactive patterns — they're visual features Pixley adds automatically based on document state.

### Progress Bars

Pixley auto-calculates completion from checkbox/review state per section and renders a progress indicator next to section headings.

```
## Phase 1: Auth ████████░░ 80% (4/5)
## Phase 2: Payments ░░░░░░░░░░ 0% (0/3)
## Phase 3: Deploy ██████████ 100% (2/2)
```

**Calculation:** Count checked checkboxes + completed reviews in each section. Display as inline progress bar after the heading. Updates live as elements are toggled.

**No write-back.** Progress bars are purely rendered — they don't exist in the source markdown. They're computed from the document structure model.

---

## Setup Prompt (for users to give their AI)

This is the copy-paste template included in Pixley's Setup Files:

```
## How to Write for Pixley Markdown Reader

I use Pixley Markdown Reader, which makes certain markdown patterns interactive.
When writing documents for me, use these patterns so I can respond directly
in the document:

### Task Lists (I can check these off)
- [ ] Task description
- [ ] Another task

### Questions (I can pick an answer)
For yes/no:
> **Your question here?**
> [ ] YES  [ ] NO

For multiple choice:
> **Your question here?**
> [ ] A. First option
> [ ] B. Second option
> [ ] C. Third option

### Fill in the Blank (I can type or choose)
Use double brackets for placeholders I need to fill in:
Project name: [[enter project name]]
Deadline: [[pick date]]

To let me choose a file or folder from my Mac:
Config file: [[choose file]]
Output directory: [[choose folder]]

### Feedback Points (I can leave comments)
When you want my feedback on something, add:
<!-- feedback -->

### Approvals (I can sign off)
> **Review: Section or document title**
> [ ] APPROVED

### QA Reviews (I can pass, fail, or flag)
> **QA: Feature or test case name**
> [ ] PASS
> [ ] FAIL
> [ ] PASS WITH NOTES
> [ ] BLOCKED
> [ ] N/A

### Inline Suggestions (I can accept or reject)
Use CriticMarkup when you want to propose specific changes:
- Addition: {++new text++}
- Deletion: {--removed text--}
- Substitution: {~~old text~>new text~~}
- Comment: {==highlighted==}{>>your comment<<}

### Status Tracking (I can advance the status)
<!-- status: draft | review | approved | implemented -->
**Status:** draft

### Confidence Levels (I can challenge or confirm)
When you're uncertain, mark your confidence:
> [confidence: high] Strong recommendation
> [confidence: medium] Reasonable suggestion
> [confidence: low] Uncertain — needs my input

### Conditional Sections (shown based on my choices)
<!-- if: architecture = MVVM -->
Content shown only if I chose MVVM...
<!-- endif -->

### Collapsible Details
<!-- collapsible: Additional Context -->
Extra information I can expand if needed...
<!-- endcollapsible -->

---

Use these patterns whenever you create checklists, ask me questions,
need my input, want a file path from me, want my sign-off, need
QA status, or want to propose changes. I'll respond through the
document itself — my reader saves changes back to the file so you
can see them. My reader also shows progress bars per section and
highlights your confidence levels so I know where to focus.
```

## Detection Priority

When scanning a document, detect patterns in this order:

1. **Reviews** — Blockquote containing `APPROVED`, `PASS`, `FAIL`, `PASS WITH NOTES`, `BLOCKED`, or `N/A`
2. **Choices** — Blockquote containing 2+ checkbox lines without review keywords (radio behavior)
3. **Confidence** — Blockquote lines matching `[confidence: high|medium|low]`
4. **Checkboxes** — Any `- [ ]` or `- [x]` outside a blockquote (multi-select)
5. **CriticMarkup** — `{++...++}`, `{--...--}`, `{~~...~>...~~}`, `{==...==}{>>...<<}`
6. **Status** — `<!-- status: ... -->` + `**Status:** ...` pairs
7. **Conditionals** — `<!-- if: ... -->` / `<!-- endif -->` and `<!-- collapsible: ... -->` / `<!-- endcollapsible -->`
8. **Fill-in-the-blank** — `[[...]]` placeholders (text, file, folder, date)
9. **Feedback** — `<!-- feedback -->` or `<!-- feedback: ... -->`

Reviews checked first (special blockquote case). CriticMarkup before fill-in-the-blank to avoid `{++[[text]]++}` ambiguity. Conditionals affect rendering before interactive elements are displayed.

## Document Structure Model

The parser doesn't just find interactive elements — it builds a structural model of the entire document from headings. This model serves three purposes: scoping interactive operations, optimizing FM context, and enabling smart navigation.

### Object Model

```
DocumentStructure
├── sections: [Section]                        // Tree from heading hierarchy
├── allElements: [InteractiveElement]          // Flat list, each knows its section
├── outline(maxDepth: Int) → String            // Headings-only summary for FM
├── summary() → String                        // "Phase 1: 3/5 tasks, 2 QA pending"
└── elements(in section: String) → [InteractiveElement]

Section
├── level: Int                                 // 1–6 (# through ######)
├── title: String                              // "Phase 1: Authentication"
├── range: Range<String.Index>                 // Full section in document
├── children: [Section]                        // Sub-sections
├── elements: [InteractiveElement]             // Elements in THIS section only
└── statusSummary() → String                   // "3/5 done, 2 QA pending"

InteractiveElement (enum)
├── .checkbox(range, isChecked, label)
├── .choice(blockquoteRange, options, selectedIndex)
├── .review(blockquoteRange, options, status, notes, date)
├── .fillIn(range, hint, type, value)
├── .feedback(range, existingText)
├── .suggestion(range, type: add|delete|substitute, old, new)
├── .status(commentRange, labelRange, states, currentState)
├── .confidence(range, level, text)
├── .conditional(range, key, value, contentRange, isVisible)
└── .collapsible(range, title, contentRange, isExpanded)
    // All cases carry: section: Section?
```

### FM Context Strategy

Instead of truncating raw markdown, give FM a structured outline:

| Context Budget | What FM Gets |
|---|---|
| Tight (~500 tokens) | `#` headings only + element counts per section |
| Medium (~1500 tokens) | `#` and `##` headings + element summaries with labels |
| Full (~3000 tokens) | All headings + full interactive element text + surrounding context |

Example tight context (200 tokens instead of 3000):

```
Document: "Project Spec v2"
Sections:
  # Phase 1: Auth — 3 tasks (2 done, 1 pending)
  # Phase 2: Payments — 3 QA reviews (all pending)
  # Phase 3: Deploy — 1 approval (pending)
  # Phase 4: Launch — 2 fill-ins (unfilled)
Interactive elements: 9 total (2 complete, 7 pending)
```

FM can request expansion of specific sections when needed for targeted edits.

### Parser Design

Single-pass line-by-line parser builds section tree and element index simultaneously:

```
MarkdownStructureParser.parse(text: String) → DocumentStructure

For each line:
  # heading     → push Section(level: 1), close previous level-1
  ## heading    → push Section(level: 2) as child of current level-1
  - [ ] outside blockquote → .checkbox in current section
  > [ ] with review keywords → .review in current section
  > [ ] without review keywords → .choice in current section
  [[...]]       → .fillIn in current section
  <!-- feedback --> → .feedback in current section
```

Re-parse on every edit. Markdown files are small — full re-parse is <1ms.

---

## Implementation Architecture

```
MarkdownNSTextView.mouseDown(event)
    → characterIndex(for: point)
    → InteractionDetector.detect(at: characterIndex, in: text)
    → returns InteractiveElement (see Document Structure Model for full enum)
    → InteractionHandler.handle(element, coordinator)
        → .checkbox, .choice: read-modify-write file, update DocumentState
        → .review: toggle + date stamp, if promptForNotes: show text popover, append notes
        → .fillIn(.text): show popover text field, on submit: write file
        → .fillIn(.file): present NSOpenPanel(canChooseFiles: true), write selected path
        → .fillIn(.folder): present NSOpenPanel(canChooseDirectories: true), write selected path
        → .feedback: show popover text field, on submit: write file
        → .suggestion: accept/reject → rewrite source text, remove CriticMarkup wrapper
        → .status: show valid next states, on select: update status label + date
        → .confidence: on challenge: show feedback popover; on confirm: set confirmed
        → .conditional: no handler — rendering only, controlled by linked Choice
        → .collapsible: no handler — view-only toggle, no write-back
```

## Voice Commands via AI Chat

The on-device Apple Intelligence (Foundation Models) can interpret natural language in the chat panel and apply bulk edits to the document's interactive elements. This turns the chat into a command layer for the document.

### Examples

| User says in chat | AI does to document |
|---|---|
| "I QA'd phase 1, it all passed" | Finds all QA review blocks, marks each as `[x] PASS — 2026-03-07` |
| "All but 3 passed" | Marks all as PASS, asks "Which 3 failed?" — user names them, AI marks those as FAIL and prompts for notes |
| "Approve the database schema" | Finds the approval block matching "Database Schema", marks `[x] APPROVED — 2026-03-07` |
| "Check off the first 5 tasks" | Toggles the first 5 unchecked checkboxes to `[x]` |
| "Project name is Starlight" | Finds `[[enter project name]]` placeholder, replaces with `Starlight` |
| "Everything in section 2 is blocked, waiting on API team" | Finds all QA blocks in section 2, marks as `[x] BLOCKED — 2026-03-07: Waiting on API team` |
| "Uncheck the deploy task" | Finds the checkbox matching "deploy", toggles back to `[ ]` |

### Implementation

```
ChatService receives user message
    → Foundation Models session has document content + interactive element index as context
    → FM identifies intent: bulk edit to interactive elements
    → FM returns structured tool call: editInteractiveElements([
        .setReview(heading: "Login Flow", status: .pass),
        .setReview(heading: "Signup Flow", status: .pass),
        .setReview(heading: "Checkout", status: .fail, notes: "Cart total wrong"),
      ])
    → InteractionHandler applies each edit via same read-modify-write path
    → DocumentState updates, FileWatcher suppressed
```

This uses the existing FM tool-calling mechanism (`@Generable` + `@Tool`). The AI chat already has document context. Adding a `editInteractiveElements` tool lets FM translate natural language into structured document edits.

**Ambiguity handling:** When the AI can't determine which elements to edit (e.g., "all but 3 passed" — which 3?), it asks a follow-up question in the chat. The human clarifies, the AI applies. Normal conversation flow.

**Scope:** The AI can only edit interactive elements (checkboxes, choices, reviews, fill-ins, feedback). It cannot rewrite arbitrary document content. This preserves the "respond, don't edit" principle — the human is still responding to the AI's document, just using natural language instead of clicks.

---

## File Write Safety

- ALWAYS read fresh from disk before modifying
- ALWAYS use `String.write(to:atomically:encoding:)`
- NEVER write from NSTextStorage (may diverge from source)
- After write: update DocumentState.content in-memory, suppress FileWatcher reload pill

## Sandbox Entitlement Change

Current: `com.apple.security.files.user-selected.read-only: true`
Required: `com.apple.security.files.user-selected.read-write: true`

**Note:** File/folder picker (`[[choose file]]` / `[[choose folder]]`) uses NSOpenPanel which grants temporary sandbox access to the selected path. The written-back path string is just text — no sandbox token is persisted. The AI receives a filesystem path it can use in its own tools.
