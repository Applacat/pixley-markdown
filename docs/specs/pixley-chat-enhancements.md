# BRD: Pixley Chat Enhancements

**Feature:** Rebrand AI Chat as Pixley Chat with context-aware suggested prompts
**Status:** PENDING
**Created:** 2026-03-24
**GitHub Issue:** #27

---

## Problem Statement

The AI chat sidebar is branded generically as "AI Chat" and has a minimal empty state ("Ask about this document"). Users don't discover that the AI can toggle checkboxes, fill in fields, select choices, or perform other collaboration actions. There's no onboarding or guidance into the relay workflow.

## Solution

1. Rebrand "AI Chat" → "Pixley Chat" everywhere (header, tooltips, menu items, accessibility labels).
2. Replace the empty state with context-aware suggested prompt chips that scan the document for interactive elements and show relevant actions.

---

## Design Decisions

### D1: Branding
Rename "AI Chat" → "Pixley Chat" in ALL references: header label, toolbar button tooltip, View menu item, noFileView placeholder text, and accessibility labels. Keep the existing bubble icon.

### D2: Suggested prompts are context-aware
Scan the document using `InteractiveElementDetector` and show prompts relevant to what's in the document. A doc with checkboxes gets "Mark all tasks as done". A plain doc gets "Summarize this document".

### D3: Max 4 chips
Up to 4 prompt chips visible at once. 1-2 contextual based on document content + 1-2 universal prompts.

### D4: Icon + text chips
Each chip has an SF Symbol icon + label text (e.g., checkmark.circle + "Mark tasks done").

### D5: Auto-send on tap
Tapping a chip immediately sends it as a message — no populate-then-edit step.

### D6: Reappear on Forget
Chips show whenever the message list is empty. Clearing chat with "Forget" brings them back. Switching documents brings them back (with new context-appropriate chips).

### D7: No chips in no-file state
The noFileView (no document selected) keeps its current message. Prompt chips only appear when a document is loaded.

---

## Context-Aware Prompt Logic

Scan document content with `InteractiveElementDetector.detect(in:)` and build prompt list:

| Document has | Prompt | Icon |
|---|---|---|
| Checkboxes | "Mark all tasks as done" | `checkmark.circle` |
| Checkboxes | "What's left to do?" | `list.bullet` |
| Fill-ins | "Fill in the blanks" | `pencil.line` |
| Choices | "Help me decide" | `arrow.triangle.branch` |
| *(always)* | "Summarize this document" | `doc.text.magnifyingglass` |
| *(always)* | "What is this about?" | `questionmark.circle` |

**Selection rules:**
1. Start with contextual prompts based on detected elements (max 2)
2. Fill remaining slots with universal prompts (up to max 4 total)
3. If no interactive elements detected, show 2-3 universal prompts
4. Deduplicate — don't show both checkbox prompts if there's only room for one

---

## Scope

### In Scope
- Rename "AI Chat" → "Pixley Chat" in all UI strings and accessibility labels
- Context-aware prompt chips in empty chat state
- Auto-send on chip tap
- Chips reappear after Forget / document switch
- SF Symbol icons on chips

### Out of Scope
- Mascot integration in chat (decided against — just rename)
- Prompt chips in no-file state
- Customizable prompts
- Streaming responses (requires @Generable, separate effort)
- Changes to chat message bubbles or input area

---

## User Stories

### US-1: Rebrand to Pixley Chat
**Description:** Rename all "AI Chat" references to "Pixley Chat" across the app.

**Acceptance Criteria:**
- [ ] Chat header label reads "Pixley Chat" (ChatView.swift chatHeader)
- [ ] Toolbar button tooltip reads "Show Pixley Chat" / "Hide Pixley Chat" (ContentView.swift AIChatModifier)
- [ ] View menu item reads "Show Pixley Chat" / "Hide Pixley Chat" (AIMDReaderApp.swift)
- [ ] noFileView text reads "Pixley Chat" and "Select a file to ask Pixley about it" (ChatView.swift)
- [ ] Accessibility labels updated to "Pixley Chat"
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### US-2: Context-aware suggested prompt chips
**Description:** Replace the empty chat state with tappable prompt chips based on document content.

**Acceptance Criteria:**
- [ ] Empty chat state shows prompt chips instead of just "Ask about this document"
- [ ] Chips scan document via `InteractiveElementDetector.detect(in:)` for context
- [ ] Document with checkboxes shows checkbox-related prompts
- [ ] Document with fill-ins shows fill-in-related prompts
- [ ] Plain document (no interactive elements) shows universal prompts only
- [ ] Max 4 chips visible
- [ ] Each chip has SF Symbol icon + label text
- [ ] Tapping a chip auto-sends it as a chat message
- [ ] "Thinking..." indicator appears after chip tap
- [ ] Chips disappear after first message is sent
- [ ] Chips reappear after "Forget" clears messages
- [ ] Chips update when switching documents (new context scan)
- [ ] Build succeeds

---

## Technical Design

### Prompt generation

New function in ChatView (or extracted helper):

```swift
struct SuggestedPrompt: Identifiable {
    let id = UUID()
    let text: String
    let icon: String  // SF Symbol name
}

func suggestedPrompts(for content: String) -> [SuggestedPrompt] {
    let elements = InteractiveElementDetector.detect(in: content)
    var prompts: [SuggestedPrompt] = []

    // Contextual
    let hasCheckboxes = elements.contains { if case .checkbox = $0 { return true } else { return false } }
    let hasFillIns = elements.contains { if case .fillIn = $0 { return true } else { return false } }
    let hasChoices = elements.contains { if case .choice = $0 { return true } else { return false } }

    if hasCheckboxes { prompts.append(.init(text: "What's left to do?", icon: "list.bullet")) }
    if hasFillIns { prompts.append(.init(text: "Fill in the blanks", icon: "pencil.line")) }
    if hasChoices { prompts.append(.init(text: "Help me decide", icon: "arrow.triangle.branch")) }

    // Universal (fill remaining)
    let universal = [
        SuggestedPrompt(text: "Summarize this document", icon: "doc.text.magnifyingglass"),
        SuggestedPrompt(text: "What is this about?", icon: "questionmark.circle"),
    ]
    for u in universal where prompts.count < 4 {
        prompts.append(u)
    }

    return Array(prompts.prefix(4))
}
```

### Chip UI

Replace `emptyChat` view body with:
- Keep sparkles icon and "Ask Pixley about this document" text
- Below: horizontal wrapping layout of chip buttons
- Each chip: rounded rect with icon + text, secondary style
- On tap: call `sendMessage(prompt.text)` directly

### Integration points

- `ChatView.emptyChat` — replace with prompt chip layout
- `ChatView.chatHeader` — rename label
- `ContentView.AIChatModifier` — rename tooltip/accessibility
- `AIMDReaderApp.swift` — rename menu item text
- `ChatView.noFileView` — rename text

### Rename targets (grep "AI Chat")

All occurrences of "AI Chat" in Swift files should become "Pixley Chat":
- `ChatView.swift` — header label, noFileView text
- `ContentView.swift` — AIChatModifier toolbar label, help text
- `AIMDReaderApp.swift` — menu button text

---

## Implementation Phases

### Phase 1: Rebrand (US-1)
- Find/replace "AI Chat" → "Pixley Chat" in all UI strings
- Update accessibility labels
- Verify build

**Verification:**
- `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- Launch app, verify header says "Pixley Chat"
- Check toolbar tooltip and View menu

### Phase 2: Prompt chips (US-2)
- Implement `suggestedPrompts(for:)` function
- Build chip UI in `emptyChat`
- Wire tap → auto-send
- Wire document switch → recompute chips
- Verify context-awareness with test documents

**Verification:**
- Same build command
- Open `~/Desktop/pixley-test/progress-bar-test.md` — should show checkbox-related prompts
- Open a plain .md with no interactive elements — should show universal prompts only
- Tap a chip — message sends, "Thinking..." appears, chips disappear
- Hit "Forget" — chips reappear

---

## Definition of Done

- [ ] All acceptance criteria in US-1 and US-2 pass
- [ ] All implementation phases verified
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- [ ] Package tests pass: `cd Packages/aimdRenderer && swift test`
- [ ] No regression in chat functionality (send message, receive response, Forget, document switch)

---

## Ralph Loop Command

```bash
/ralph-loop "Implement Pixley Chat enhancements per spec at docs/specs/pixley-chat-enhancements.md

PHASES:
1. Rebrand (US-1): Rename 'AI Chat' to 'Pixley Chat' in all UI strings, tooltips, menu items, accessibility labels
2. Prompt chips (US-2): Context-aware suggested prompt chips in empty chat state, auto-send on tap, reappear on Forget

VERIFICATION (run after each phase):
- xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build
- cd Packages/aimdRenderer && swift test

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```
