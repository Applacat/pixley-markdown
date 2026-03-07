# Spec 3: Pixley Modal + AI Field Interaction

**Version:** 1.0
**Date:** 2026-03-07
**Status:** Approved
**Depends on:** Spec 1 (Premium Gate + Self-Describing Protocol)

## Overview

Build the Pixley Modal — an inline chat component that shows AI-proposed changes to interactive elements, with editable fields and user confirmation before applying. This is the "AI can interact with parsed fields" Pro feature.

## Problem Statement

When the AI proposes changes to interactive elements ("mark all Section 3 tasks as done"), the user needs to review and confirm before changes are applied. The Pixley Modal provides a review-and-edit interface inline in the chat, where users can modify the AI's proposal (e.g., change "Section 3" to "Section 4") or add additional items before confirming.

## Core Interaction Flow

1. User asks AI: "Mark all purchase screen tests in Section 3 as done"
2. AI tool uses SectionResolver to find elements in Section 3
3. AI tool returns proposed changes via SelfDescribingElement protocol
4. **Pixley Modal** appears inline in chat showing:
   - Header: "AI wants to mark as done:"
   - Each proposed element as an editable row (looks like plain text, click to edit)
   - [+] button to add another item
   - [Confirm] [Cancel] buttons
5. User reviews, optionally edits rows or adds items
6. User clicks Confirm → changes applied via InteractionHandler
7. Chat shows confirmation: "Done — marked 3 items as complete"

## User Stories

### US-1: Pixley Modal Chat Component
**Description:** Build the inline modal component that renders in the chat view.

**Acceptance Criteria:**
- [ ] Modal renders inline in ChatView (not a separate sheet/popover)
- [ ] Header text describes the action ("AI wants to mark as done:")
- [ ] Each proposed change shown as a row with element text
- [ ] Rows look like plain text but are editable (invisible text field, activates on click)
- [ ] [+] button at bottom adds an empty row for user to type a search term
- [ ] [Confirm] button applies all changes
- [ ] [Cancel] button dismisses without changes
- [ ] Modal styled consistently with chat message bubbles
- [ ] Keyboard accessible: Tab between rows, Return to confirm

### US-2: Editable Rows
**Description:** Users can click into any row to edit the AI's proposal.

**Acceptance Criteria:**
- [ ] Each row is a text field that appears as static text until focused
- [ ] On focus: shows cursor, text becomes editable
- [ ] On blur/Return: row commits, looks like static text again
- [ ] Editing a row updates the proposed change (re-resolves through SelfDescribingElement if needed)
- [ ] User can delete a row (e.g., swipe-to-delete or minus button on hover)

### US-3: Add Row
**Description:** Users can add items the AI missed.

**Acceptance Criteria:**
- [ ] [+] button adds an empty editable row at the bottom
- [ ] User types a search term (e.g., "Section 6" or "login tests")
- [ ] System resolves matching elements via SectionResolver / text search
- [ ] If multiple matches: show disambiguation (e.g., "Found 3 items in Section 6 — add all?")
- [ ] Added items appear in the modal with the same editable row treatment

### US-4: Apply Changes on Confirm
**Description:** When user confirms, all proposed changes are applied atomically.

**Acceptance Criteria:**
- [ ] Confirm collects all rows' resolved elements
- [ ] Changes applied via InteractionHandler (batch `replaceMultiple`)
- [ ] FileWatcher suppressed for the write
- [ ] Chat shows confirmation message with count: "Done — marked N items as complete"
- [ ] Document re-renders with updated state
- [ ] If any change fails (range mismatch), show error for that item, apply others

### US-5: AI Tool Integration
**Description:** EditInteractiveElementsTool produces proposals that render as Pixley Modals.

**Acceptance Criteria:**
- [ ] Tool returns a `ProposedChanges` struct (not immediate application)
- [ ] ChatView detects `ProposedChanges` in tool output and renders Pixley Modal
- [ ] Tool uses SelfDescribingElement protocol to build proposals generically
- [ ] Tool uses SectionResolver when user references sections by name/number
- [ ] @Generable struct for tool arguments includes: elementIndices, field, newValue (sacred code)
- [ ] Tool checks entitlement — free users get upsell + explanation (Spec 1 gate)

### US-6: Cancel and Rephrase
**Description:** When user cancels, the AI understands and can respond.

**Acceptance Criteria:**
- [ ] Cancel dismisses the modal
- [ ] Chat shows "Changes cancelled" message
- [ ] User can rephrase their request and the AI tries again
- [ ] Previous modal is replaced by the new one (not stacked)

## Technical Design

### ProposedChanges Model

```swift
struct ProposedChanges: Sendable {
    let description: String  // "Mark as done"
    let items: [ProposedItem]

    struct ProposedItem: Sendable, Identifiable {
        let id: UUID
        let elementText: String  // Display text for the row
        let element: InteractiveElement  // The resolved element
        let field: String  // Which field to change
        let newValue: String  // What to change it to
    }
}
```

### Pixley Modal View

```swift
struct PixleyModalView: View {
    let changes: ProposedChanges
    let onConfirm: ([ProposedChanges.ProposedItem]) -> Void
    let onCancel: () -> Void

    @State private var items: [ProposedChanges.ProposedItem]
    @State private var editingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(changes.description).font(.headline)
            ForEach($items) { $item in
                EditableRow(item: $item, isEditing: editingID == item.id)
            }
            AddRowButton { /* add empty row */ }
            HStack {
                Button("Cancel", action: onCancel)
                Button("Confirm") { onConfirm(items) }
                    .keyboardShortcut(.return)
            }
        }
    }
}
```

### Integration Points
- `ChatView` renders `PixleyModalView` when a message contains `ProposedChanges`
- `EditInteractiveElementsTool` returns `ProposedChanges` instead of directly applying
- `InteractionHandler.apply(edit:)` called from modal's onConfirm handler
- `SectionResolver` (from Spec 1) used to resolve section references
- `SelfDescribingElement` (from Spec 1) used to build proposals generically

## Implementation Phases

### Phase 1: ProposedChanges Model + Basic Modal UI (US-1)
- [ ] Define ProposedChanges model
- [ ] Build PixleyModalView with static rows, Confirm/Cancel
- [ ] Render inline in ChatView
- **Verification:** Hard-coded ProposedChanges renders as modal in chat.

### Phase 2: Editable Rows + Add Row (US-2, US-3)
- [ ] Invisible text field pattern for editable rows
- [ ] Add row with search/resolution
- [ ] Delete row support
- **Verification:** Edit a row, add a row, delete a row — all work.

### Phase 3: Apply Changes + Tool Integration (US-4, US-5)
- [ ] Wire Confirm to InteractionHandler batch apply
- [ ] Update EditInteractiveElementsTool to return ProposedChanges
- [ ] ChatView detects and renders proposals
- [ ] Entitlement gate check in tool
- **Verification:** AI proposes changes → modal appears → confirm → file updated.

### Phase 4: Cancel/Rephrase + Polish (US-6)
- [ ] Cancel flow with chat message
- [ ] Rephrase replaces previous modal
- [ ] Accessibility pass
- [ ] Error handling for failed applies
- **Verification:** Full flow: ask → modal → edit → confirm. Ask → modal → cancel → rephrase → new modal → confirm.

## Definition of Done

- [ ] All 6 user stories pass acceptance criteria
- [ ] Full flow works: AI proposal → Pixley Modal → user review/edit → confirm → file updated
- [ ] Cancel and rephrase flow works
- [ ] Entitlement gate blocks free users with upsell
- [ ] Tests pass, build succeeds

## Open Questions
- Should the modal support undo? (Cmd+Z after confirming to revert changes)
- How should very large proposals render? (e.g., "mark all 50 checkboxes as done" — scrollable list?)
- Should the AI be able to propose multiple different actions in one modal? (e.g., check some items AND fill in a field)

## Implementation Notes
*To be filled during implementation*
