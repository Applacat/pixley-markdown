# Pixley Interactive Markdown Protocol — Implementation Spec

**Version:** 3.0
**Date:** 2026-03-07
**Status:** Ready for implementation
**Protocol Design:** `docs/specs/interactive-markdown-protocol.md`

---

## Overview

Pixley Markdown (renamed from "Pixley Markdown Reader") evolves from a passive markdown reader into an AI-to-Human collaboration tool. The app detects 9 specific markdown patterns and makes them interactive. The human responds through the document — checking boxes, answering questions, picking options, approving sections, accepting/rejecting suggestions. Changes save back to the `.md` file so the AI can see them.

**UX metaphor:** "Digital redlining" — responding to a document, not editing it.

---

## Problem Statement

AI tools write markdown as their primary output format. Humans read these documents passively — they can't respond through the document itself. The feedback loop requires switching to a different tool (chat, email, PR comment) to communicate decisions back to the AI. This breaks flow and creates fragmented conversations.

Pixley Markdown makes the markdown file a bidirectional collaboration surface: AI writes structured patterns, human responds in-place, changes persist to disk for the AI to read.

---

## Scope

### In Scope

- 9 interactive markdown patterns (see User Stories)
- Document structure parser (section tree + interactive element index)
- Atomic file write-back engine
- FM context optimization (structured outlines)
- Voice commands via AI chat (FM tool calls)
- Progress bars per section (auto-calculated)
- Gutter refactor (section-level interaction surface)
- Sandbox entitlement change (read-write)
- Full app rename to "Pixley Markdown"
- Rename "Sample Files" to "Setup Files"
- Starter Files (onboarding + verification document)
- Unit tests per pattern
- iOS 26 / iPadOS 26 / visionOS targets
- Public repo: applacat/pixley (protocol + Claude Code skill)

### Out of Scope

- Full markdown editing
- Real-time conflict resolution / operational transform
- Push notifications (v3.1)
- AI-detected urgency classification (v3.1)
- ChatGPT / Cursor / Copilot skills (start with Claude Code only)

---

## User Stories

### US-1: Document Structure Parser

**Description:** As a developer, I need a parser that builds a structural model from markdown headings and detects interactive elements, so that all subsequent features have a foundation to work with.

**Acceptance Criteria:**
- [ ] `MarkdownStructureParser.parse(text:)` returns a `DocumentStructure` with section tree
- [ ] Sections have correct `level`, `title`, `range`, and `children`
- [ ] Parser detects all 9 interactive element types and assigns each to its containing section
- [ ] `outline(maxDepth:)` produces headings-only summary at specified depth
- [ ] `summary()` produces element count summary per section
- [ ] Re-parse completes in <5ms for a 10KB markdown file
- [ ] Unit tests cover: empty document, single heading, nested headings (3+ levels), heading with no content, multiple elements per section
- [ ] `xcodegen generate && xcodebuild -scheme AIMDReader -destination 'platform=macOS' build` succeeds

---

### US-2: Interaction Handler (Write-Back Engine)

**Description:** As a developer, I need a safe file write-back engine that reads from disk, applies a structured edit, and writes back atomically, so that all interactive patterns can share one write path.

**Acceptance Criteria:**
- [ ] `InteractionHandler.apply(edit:to:)` reads fresh from disk before modifying
- [ ] Uses `String.write(to:atomically:encoding:)` for all writes
- [ ] Never reads from NSTextStorage
- [ ] After successful write, updates `DocumentState.content` in-memory
- [ ] After successful write, suppresses FileWatcher reload pill for self-initiated changes
- [ ] Handles concurrent write attempts gracefully (second write re-reads disk)
- [ ] Unit tests cover: write to existing file, write to file changed by external process, write preserves non-modified content exactly
- [ ] Build succeeds

---

### US-3: Sandbox Entitlement + App Rename

**Description:** As a user, I see "Pixley Markdown" (not "Reader") everywhere, and the app can write back to files I've opened.

**Acceptance Criteria:**
- [ ] Entitlement changed from `com.apple.security.files.user-selected.read-only` to `com.apple.security.files.user-selected.read-write`
- [ ] `PRODUCT_NAME` updated to `Pixley Markdown` in project.yml
- [ ] `CFBundleName` updated to `Pixley Markdown`
- [ ] `CFBundleDisplayName` updated to `Pixley Markdown`
- [ ] Window title shows "Pixley Markdown"
- [ ] Menu bar shows "Pixley Markdown"
- [ ] About panel shows "Pixley Markdown"
- [ ] Help menu items reference "Pixley Markdown"
- [ ] "Sample Files" renamed to "Setup Files" in code, UI, and Welcome folder
- [ ] Build succeeds and app launches with new name

---

### US-4: Checkbox Toggle

**Description:** As a user reading a markdown document with `- [ ]` task lists, I can single-click a checkbox to toggle it, and the change saves to the file.

**Acceptance Criteria:**
- [ ] Single click on `[ ]` changes it to `[x]` in the rendered view
- [ ] Single click on `[x]` changes it back to `[ ]`
- [ ] Change is written to the `.md` file on disk immediately
- [ ] Only the checkbox character is modified (surrounding text unchanged)
- [ ] Checkboxes outside blockquotes toggle independently (multi-select)
- [ ] Visual affordance: checkbox rendered with styled interactive appearance (not plain text)
- [ ] Clicking non-checkbox text performs normal text selection
- [ ] Unit tests: toggle on, toggle off, toggle preserves surrounding content, nested list checkboxes
- [ ] Build succeeds

---

### US-5: Choice (Radio in Blockquote)

**Description:** As a user reading a blockquote with multiple checkbox options, I can click one to select it, and all others in the same blockquote are deselected.

**Acceptance Criteria:**
- [ ] Click `[ ] B` in a blockquote → `[x] B`, all other options become `[ ]`
- [ ] Yes/No on same line works: clicking YES deselects NO and vice versa
- [ ] Change written to disk immediately
- [ ] Visual affordance: blockquote choices rendered as card-like group with radio appearance
- [ ] Unit tests: select option, change selection, yes/no toggle, 3+ options, already-selected click
- [ ] Build succeeds

---

### US-6: Fill-in-the-Blank

**Description:** As a user seeing `[[enter project name]]` or `[[choose file]]`, I can click to provide input — text via popover or file/folder via native picker.

**Acceptance Criteria:**
- [ ] Click `[[enter text]]` → popover appears with auto-focused text field showing hint
- [ ] Press Enter or click outside → placeholder replaced with typed text in file
- [ ] Click `[[choose file]]` → NSOpenPanel (canChooseFiles: true) opens
- [ ] Selecting a file replaces `[[choose file]]` with the full file path
- [ ] Click `[[choose folder]]` → NSOpenPanel (canChooseDirectories: true) opens
- [ ] Selecting a folder replaces `[[choose folder]]` with the full folder path
- [ ] Pressing Escape / Cancel dismisses without changes
- [ ] Visual affordance: placeholders rendered with dotted underline and hint text
- [ ] Unit tests: text replacement, file path replacement, empty input handling
- [ ] Build succeeds

---

### US-7: Feedback

**Description:** As a user seeing a `<!-- feedback -->` marker, I can click it to leave a comment that's saved inside the HTML comment.

**Acceptance Criteria:**
- [ ] Pixley renders `<!-- feedback -->` as a visible feedback widget (icon/bubble)
- [ ] Click → popover with auto-focused text field
- [ ] Submit → file changes to `<!-- feedback: user's text -->`
- [ ] Already-filled feedback (`<!-- feedback: old text -->`) shows existing text in popover for editing
- [ ] Visual affordance: feedback marker rendered as distinct widget (not hidden like normal HTML comments)
- [ ] Unit tests: empty feedback, filled feedback, edit existing feedback
- [ ] Build succeeds

---

### US-8: Reviews (Approvals + QA)

**Description:** As a user seeing approval or QA review blocks, I can click to approve/pass/fail with automatic date stamps and notes.

**Acceptance Criteria:**
- [ ] Click `[ ] APPROVED` → `[x] APPROVED — YYYY-MM-DD`
- [ ] Click to un-approve → removes date suffix
- [ ] Click `[ ] PASS` → `[x] PASS — YYYY-MM-DD` (no notes prompt)
- [ ] Click `[ ] FAIL` → `[x] FAIL — YYYY-MM-DD: ` + notes popover with autofocus
- [ ] Click `[ ] PASS WITH NOTES` → date stamp + notes popover
- [ ] Click `[ ] BLOCKED` → date stamp + notes popover
- [ ] Click `[ ] N/A` → date stamp only (no notes)
- [ ] Radio behavior: selecting one deselects others in same blockquote
- [ ] Visual affordance: review blocks rendered as distinct card with status styling
- [ ] Unit tests: each status type, date format, notes appending, deselection clears date+notes
- [ ] Build succeeds

---

### US-9: CriticMarkup

**Description:** As a user seeing CriticMarkup suggestions, I can accept or reject each inline change with a floating toolbar.

**Acceptance Criteria:**
- [ ] `{++text++}` rendered with green underline/highlight
- [ ] `{--text--}` rendered with red strikethrough
- [ ] `{~~old~>new~~}` rendered showing both old and new with visual distinction
- [ ] `{==text==}{>>comment<<}` rendered with highlight and visible comment
- [ ] Hover over any CriticMarkup → floating toolbar appears with Accept/Reject buttons
- [ ] Accept addition: `{++text++}` → `text` in file
- [ ] Reject addition: `{++text++}` → removed from file
- [ ] Accept deletion: `{--text--}` → removed from file
- [ ] Reject deletion: `{--text--}` → `text` in file
- [ ] Accept substitution: `{~~old~>new~~}` → `new` in file
- [ ] Reject substitution: `{~~old~>new~~}` → `old` in file
- [ ] Unit tests: all accept/reject operations, nested CriticMarkup, adjacent suggestions
- [ ] Build succeeds

---

### US-10: Status State Machines

**Description:** As a user seeing a status indicator, I can click to advance it through defined states.

**Acceptance Criteria:**
- [ ] `<!-- status: draft | review | approved | implemented -->` followed by `**Status:** draft` detected
- [ ] Click status label → shows popover/menu with valid next states only
- [ ] Selecting next state updates the status word in file
- [ ] Terminal states append date: `**Status:** approved — YYYY-MM-DD`
- [ ] Only forward transitions allowed (draft→review, not review→draft)
- [ ] Visual affordance: status label rendered as clickable badge with state color
- [ ] Unit tests: forward transition, terminal date stamp, invalid backward transition blocked
- [ ] Build succeeds

---

### US-11: Confidence Indicators

**Description:** As a user seeing AI confidence markers, I can visually distinguish confidence levels and challenge/confirm recommendations.

**Acceptance Criteria:**
- [ ] `> [confidence: high]` rendered with green badge
- [ ] `> [confidence: medium]` rendered with yellow badge
- [ ] `> [confidence: low]` rendered with red badge
- [ ] Click low-confidence item → feedback popover to challenge
- [ ] Challenge appends `<!-- feedback: user's challenge -->` after the line
- [ ] Click high-confidence item → changes to `[confidence: confirmed]`
- [ ] Unit tests: badge rendering trigger, challenge write-back, confirm write-back
- [ ] Build succeeds

---

### US-12: Conditional / Collapsible Sections

**Description:** As a user, conditional sections show/hide based on my choices, and collapsible sections can be expanded/collapsed.

**Acceptance Criteria:**
- [ ] `<!-- if: key = value -->...<!-- endif -->` content shown only when matching choice is selected
- [ ] Unmatched conditional content is hidden (not rendered) but preserved in source
- [ ] Changing a choice updates conditional visibility immediately
- [ ] `<!-- collapsible: Title -->...<!-- endcollapsible -->` renders as disclosure triangle
- [ ] Click disclosure triangle toggles content visibility
- [ ] Collapsible state is ephemeral (no write-back)
- [ ] Conditional linking matches bold heading text case-insensitively
- [ ] Unit tests: conditional show/hide, collapsible toggle, multiple conditionals for same key
- [ ] Build succeeds

---

### US-13: Progress Bars

**Description:** As a user, I see auto-calculated progress indicators next to section headings.

**Acceptance Criteria:**
- [ ] Section headings with checkboxes show `████░░ 60% (3/5)` style progress
- [ ] Progress includes both checkboxes and completed reviews
- [ ] Progress updates live when elements are toggled
- [ ] Sections with no interactive elements show no progress bar
- [ ] Progress bars are rendered only — not written to source markdown
- [ ] Build succeeds

---

### US-14: Gutter Refactor

**Description:** As a user, I can interact with section-level affordances in the gutter area — commenting, bookmarking, and color-coding sections.

**Acceptance Criteria:**
- [ ] Gutter shows section-level interaction elements (replacing line number dots)
- [ ] Click gutter at a section → shows bubbly SwiftUI affordances (comment, bookmark, color)
- [ ] Section comment: opens popover, saves text to SwiftData keyed by file+section
- [ ] Section bookmark: toggles bookmark state, persisted in SwiftData
- [ ] Section color: lets user pick a highlight color for the section, persisted in SwiftData
- [ ] Annotations survive app close (SwiftData persistence)
- [ ] Annotations do NOT modify the .md file
- [ ] Build succeeds

---

### US-15: FM Context Optimization

**Description:** As the AI chat system, I receive a structured document outline instead of truncated raw markdown, so I can operate on interactive elements efficiently within Foundation Models' limited context.

**Acceptance Criteria:**
- [ ] ChatService uses `DocumentStructure.outline(maxDepth:)` instead of raw text truncation
- [ ] Context budget selects appropriate depth: tight (# only), medium (# + ##), full (all headings + elements)
- [ ] FM session instructions include structured element index with section assignments
- [ ] Context size stays under FM token limits regardless of document size
- [ ] Unit tests: outline at each depth level, context budget selection logic
- [ ] Build succeeds

---

### US-16: Voice Commands via AI Chat

**Description:** As a user, I can type natural language in the AI chat like "mark all QA as passed" and the AI edits interactive elements in the document.

**Acceptance Criteria:**
- [ ] `editInteractiveElements` FM tool defined with `@Generable` + `@Tool`
- [ ] Tool supports: setCheckbox, setChoice, setReview, setFillIn, setFeedback
- [ ] "I QA'd phase 1, all passed" → marks all QA reviews in matching section as PASS
- [ ] "Check off the first 5 tasks" → toggles first 5 unchecked checkboxes
- [ ] "Project name is Starlight" → fills matching `[[enter project name]]` placeholder
- [ ] Ambiguous commands → AI asks follow-up question in chat
- [ ] Edits go through same InteractionHandler write path as click edits
- [ ] Build succeeds

---

### US-17: Setup Files + Starter Document

**Description:** As a user, I find a "Setup Files" section in the app with a Starter Document that demonstrates all 9 patterns and includes a copy-paste prompt for AI tools.

**Acceptance Criteria:**
- [ ] Welcome folder renamed from "Sample Files" to "Setup Files"
- [ ] Starter Document contains all 9 interactive patterns with working examples
- [ ] Copy-paste AI prompt template included in Starter Document
- [ ] Same Starter Document lives in public applacat/pixley repo
- [ ] Opening Starter Document and interacting with all patterns = build verification
- [ ] Build succeeds

---

### US-18: Multiplatform Targets

**Description:** As a user on iPad, iPhone, or Vision Pro, I can open and interact with Pixley markdown documents.

**Acceptance Criteria:**
- [ ] iOS 26 / iPadOS 26 / visionOS targets added to project
- [ ] AppKit dependencies abstracted behind platform-conditional code
- [ ] NSOpenPanel → UIDocumentPickerViewController on iOS
- [ ] NSTextView → platform-appropriate text rendering on iOS
- [ ] File watching works on iOS (or graceful fallback)
- [ ] Files in iCloud Drive folders work seamlessly across platforms
- [ ] NavigationSplitView adapts to iPad/iPhone layout
- [ ] All 9 interactive patterns work on all platforms
- [ ] Build succeeds on all target platforms

---

### US-19: Public Ecosystem Repo

**Description:** As an AI tool user, I can find the Pixley protocol and a Claude Code skill at applacat/pixley to teach my AI to write Pixley-compliant markdown.

**Acceptance Criteria:**
- [ ] Public repo at applacat/pixley created
- [ ] Protocol spec (interactive-markdown-protocol.md) published
- [ ] Claude Code skill (CLAUDE.md or similar) for writing Pixley-compliant markdown
- [ ] Sample documents demonstrating all patterns
- [ ] README explaining the protocol and how to use the skills
- [ ] Build succeeds (app bundles the same sample files)

---

## Technical Design

### Data Model

```swift
struct DocumentStructure {
    let sections: [Section]
    let allElements: [InteractiveElement]
    func outline(maxDepth: Int) -> String
    func summary() -> String
    func elements(in sectionTitle: String) -> [InteractiveElement]
}

struct Section {
    let level: Int
    let title: String
    let range: Range<String.Index>
    let children: [Section]
    let elements: [InteractiveElement]
    func statusSummary() -> String
}

enum InteractiveElement {
    case checkbox(range: Range<String.Index>, isChecked: Bool, label: String)
    case choice(blockquoteRange: Range<String.Index>, options: [ChoiceOption], selectedIndex: Int?)
    case review(blockquoteRange: Range<String.Index>, options: [ReviewOption], status: ReviewStatus?)
    case fillIn(range: Range<String.Index>, hint: String, type: FillInType, value: String?)
    case feedback(range: Range<String.Index>, existingText: String?)
    case suggestion(range: Range<String.Index>, type: SuggestionType, old: String?, new: String?)
    case status(commentRange: Range<String.Index>, labelRange: Range<String.Index>, states: [String], current: String)
    case confidence(range: Range<String.Index>, level: ConfidenceLevel, text: String)
    case conditional(range: Range<String.Index>, key: String, value: String, contentRange: Range<String.Index>)
    case collapsible(range: Range<String.Index>, title: String, contentRange: Range<String.Index>)

    var section: Section? // Back-reference to containing section
}
```

### Architecture

```
MarkdownStructureParser (in aimdRenderer package)
    → Parses text into DocumentStructure
    → Single-pass line-by-line
    → Builds section tree + element index simultaneously

InteractionHandler (in main app target)
    → apply(edit: InteractionEdit, to fileURL: URL) throws
    → Reads fresh from disk
    → Applies structured edit
    → Writes atomically
    → Updates DocumentState.content
    → Suppresses FileWatcher

InteractionDetector (in aimdRenderer package)
    → detect(at characterIndex: Int, in structure: DocumentStructure) -> InteractiveElement?
    → Hit-tests click position against known element ranges

Visual Affordances (in aimdRenderer package)
    → Applied during syntax highlighting pass
    → Styled boxes for checkboxes, card backgrounds for choices
    → Dotted underlines for fill-ins, icons for feedback
    → Green/red inline styles for CriticMarkup
    → Progress bars after section headings
```

### File Write Safety

- ALWAYS read fresh from disk before modifying
- ALWAYS use `String.write(to:atomically:encoding:)`
- NEVER write from NSTextStorage
- After write: update DocumentState.content, suppress FileWatcher
- Instant write per toggle (no debounce)

---

## Implementation Phases

### Phase 1: Foundation

**Stories:** US-1, US-2, US-3
**Delivers:** Parser, write-back engine, sandbox entitlement, app rename

- [ ] MarkdownStructureParser with section tree + element index
- [ ] InteractionHandler with atomic read-modify-write
- [ ] Sandbox entitlement → read-write
- [ ] Full app rename to "Pixley Markdown"
- [ ] Rename "Sample Files" to "Setup Files"
- [ ] Unit test infrastructure

**Verification:** `xcodegen generate && xcodebuild -scheme AIMDReader -destination 'platform=macOS' build && xcodebuild -scheme AIMDReaderTests -destination 'platform=macOS' test`

### Phase 2: Core Patterns

**Stories:** US-4, US-5, US-6, US-7
**Delivers:** Checkboxes, Choices, Fill-in, Feedback — the four simplest interactive patterns

- [ ] Checkbox toggle (click detection + write-back + visual affordance)
- [ ] Choice radio (blockquote grouping + radio behavior + visual affordance)
- [ ] Fill-in-the-blank (popover + text/file/folder + visual affordance)
- [ ] Feedback (popover + HTML comment write-back + visual affordance)
- [ ] Unit tests for each pattern

**Verification:** Build + tests + open Starter Document and interact with all 4 patterns

### Phase 3: Advanced Patterns

**Stories:** US-8, US-9, US-10, US-11, US-12, US-13, US-14
**Delivers:** Reviews, CriticMarkup, Status, Confidence, Conditionals, Progress Bars, Gutter

- [ ] Reviews (approvals + QA + date stamps + notes popover)
- [ ] CriticMarkup (inline rendering + accept/reject toolbar)
- [ ] Status state machines (transition enforcement + date stamps)
- [ ] Confidence indicators (badges + challenge/confirm)
- [ ] Conditional / collapsible sections
- [ ] Progress bars (auto-calculated)
- [ ] Gutter refactor (section interaction surface + SwiftData persistence)
- [ ] Unit tests for each pattern

**Verification:** Build + tests + open Starter Document and interact with all 9 patterns

### Phase 4: AI Integration

**Stories:** US-15, US-16, US-17
**Delivers:** FM context optimization, voice commands, Starter Files

- [ ] FM context optimization (structured outlines)
- [ ] editInteractiveElements FM tool
- [ ] Starter Document with all 9 patterns
- [ ] Setup Files with AI prompt template

**Verification:** Build + tests + "mark all QA as passed" in chat edits document correctly

### Phase 5: Multiplatform + Ecosystem

**Stories:** US-18, US-19
**Delivers:** iOS/iPadOS/visionOS targets, public repo

- [ ] Platform-conditional code for AppKit vs UIKit
- [ ] iOS/iPadOS/visionOS targets in project.yml
- [ ] Public repo applacat/pixley with protocol + Claude Code skill
- [ ] All patterns work on all platforms

**Verification:** Build succeeds on all platforms + interactions work on iPad simulator

---

## Non-Functional Requirements

- **NFR-1:** Parser completes in <5ms for a 10KB markdown file
- **NFR-2:** File write-back completes in <10ms
- **NFR-3:** Visual affordances render without flicker during syntax highlighting
- **NFR-4:** Click-to-toggle latency < 50ms (perceived instant)
- **NFR-5:** Full re-highlight after toggle < 50ms on Apple Silicon
- **NFR-6:** No data loss — interrupted writes must not corrupt files (atomic writes)

---

## Definition of Done

This feature is complete when:
- [ ] All 19 user stories pass their acceptance criteria
- [ ] All 5 implementation phases verified
- [ ] Unit tests pass: `xcodebuild -scheme AIMDReaderTests test`
- [ ] Build succeeds: `xcodegen generate && xcodebuild -scheme AIMDReader build`
- [ ] Starter Document opens and all 9 patterns work interactively
- [ ] App shows "Pixley Markdown" everywhere
- [ ] Public repo applacat/pixley is live with protocol + Claude Code skill

---

## References

- Protocol design: `docs/specs/interactive-markdown-protocol.md`
- Meeting notes: `cal/memories/2026-03-07.md`
- CriticMarkup standard: https://criticmarkup.com
- AGENTS.md standard: https://agents.md
