# Spec 2: Classic Rendering Mode (Native Embedded Controls)

**Version:** 1.0
**Date:** 2026-03-07
**Status:** Approved
**Depends on:** Spec 1 (Premium Gate + Self-Describing Protocol)

## Overview

Add a "Classic" rendering mode that embeds real native macOS controls (NSButton, NSPopUpButton, NSTextField) inline in the text view using NSTextAttachmentViewProvider. This is the beginner-friendly mode — interactive elements look like actual Mac UI controls, familiar to anyone who's used a settings window.

## Problem Statement

The current "Pro" rendering mode uses SF Symbol images and styled text to represent interactive elements. While compact and document-like, it requires users to understand that visual indicators are clickable. Classic mode makes this obvious by rendering actual native controls that users instinctively know how to interact with.

## Two Rendering Modes

### Classic Mode (Beginner)
- Real embedded NSControls inline in the text via `NSTextAttachmentViewProvider` (macOS 12+)
- Looks like a Mac settings pane inside the document
- Controls:
  - `NSButton` (checkbox style) for checkboxes
  - `NSButton` (radio style) for choices/reviews
  - `NSPopUpButton` for status dropdowns
  - `NSTextField` with standard macOS styling for fill-in fields
  - Native `NSButton` (push style) for CriticMarkup Accept/Reject

### Pro Mode (Power User) — Current Implementation
- SF Symbol indicators for checkboxes/radios
- Styled text with background colors
- Native NSMenu for status dropdowns (popup, not embedded)
- Glass text field appearance for fill-ins
- Compact, document stays document-like

### Mode Selection
- Setting in Preferences > Rendering (or dedicated toggle in toolbar)
- Default: Classic (beginner-friendly first impression)
- Both modes available to all users (free and Pro)
- Mode only affects how interactive elements render — markdown text is unchanged
- Free users see controls but can only interact with checkboxes (gate from Spec 1 applies)

## User Stories

### US-1: NSTextAttachmentViewProvider Infrastructure
**Description:** Build the infrastructure to embed arbitrary NSViews as text attachments in MarkdownNSTextView.

**Acceptance Criteria:**
- [ ] Custom `NSTextAttachmentViewProvider` subclass created for each control type
- [ ] Attachments properly size themselves to match surrounding text metrics (line height, baseline)
- [ ] Attachments respond to click/interaction and fire callbacks to the text view
- [ ] Attachments don't break text selection, copy/paste, or accessibility
- [ ] Attachments survive re-highlighting (not lost when `applyHighlighting` runs)
- [ ] `lastAppliedText` tracking still works correctly with embedded views

### US-2: Checkbox Controls (NSButton)
**Description:** Render checkboxes as real NSButton checkbox controls in Classic mode.

**Acceptance Criteria:**
- [ ] `- [ ]` renders as unchecked NSButton (checkbox style) inline in text
- [ ] `- [x]` renders as checked NSButton (checkbox style) inline in text
- [ ] Clicking the NSButton toggles the checkbox and writes back to file
- [ ] Visual state matches surrounding text size
- [ ] Tab navigation works between checkbox controls
- [ ] VoiceOver announces as "checkbox, unchecked" / "checkbox, checked"

### US-3: Radio Controls (NSButton)
**Description:** Render choice/review options as real NSButton radio controls in Classic mode.

**Acceptance Criteria:**
- [ ] Choice options render as NSButton (radio style) inline
- [ ] Selecting one deselects others (radio behavior maintained)
- [ ] Review options render similarly with status-appropriate colors
- [ ] Write-back works correctly through InteractionHandler
- [ ] Gated for free users (clicking shows upgrade popover from Spec 1)

### US-4: Dropdown Controls (NSPopUpButton)
**Description:** Render status elements as real NSPopUpButton dropdowns in Classic mode.

**Acceptance Criteria:**
- [ ] Status element renders as NSPopUpButton with current state selected
- [ ] Dropdown shows all valid states from the element's `states` array
- [ ] Selecting a state advances status and writes back to file
- [ ] Terminal states show date stamp after selection
- [ ] Gated for free users

### US-5: Text Field Controls (NSTextField)
**Description:** Render fill-in fields as real NSTextField controls in Classic mode.

**Acceptance Criteria:**
- [ ] Fill-in `[[placeholder]]` renders as NSTextField with placeholder text
- [ ] Filled-in `[[value]]` renders as NSTextField with value
- [ ] Pressing Return or clicking away commits the value and writes back to file
- [ ] Text field matches document font and size
- [ ] Gated for free users

### US-6: CriticMarkup Controls
**Description:** Render CriticMarkup suggestions with real Accept/Reject buttons in Classic mode.

**Acceptance Criteria:**
- [ ] Each suggestion shows Accept (checkmark) and Reject (x) NSButton controls
- [ ] Buttons are compact, inline, styled with green/red
- [ ] Clicking Accept/Reject applies the change via InteractionHandler
- [ ] Gated for free users

### US-7: Mode Toggle
**Description:** Allow users to switch between Classic and Pro rendering modes.

**Acceptance Criteria:**
- [ ] Setting persisted in SettingsRepository
- [ ] Changing mode re-renders current document immediately
- [ ] Mode toggle in Settings > Rendering
- [ ] Optional: toolbar toggle for quick switching
- [ ] Default mode: Classic

## Technical Design

### NSTextAttachmentViewProvider Pattern

```swift
// Custom view provider for checkbox controls
final class CheckboxAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled))
        button.state = isChecked ? .on : .off
        self.view = button
    }

    @objc private func toggled() {
        // Fire callback to MarkdownNSTextView for write-back
    }
}
```

### Integration Points
- `MarkdownHighlighter.annotateInteractiveElements` checks rendering mode
  - Classic: replaces element ranges with NSTextAttachment containing view providers
  - Pro: current SF Symbol / styled text approach
- View providers fire callbacks through `MarkdownNSTextView` delegate methods
- `InteractionHandler` write-back path unchanged — both modes produce the same `InteractiveEdit`
- Entitlement gate (Spec 1) applies equally to both modes

## Implementation Phases

### Phase 1: AttachmentViewProvider Infrastructure
- [ ] Create base `InteractiveAttachmentViewProvider` class
- [ ] Handle sizing, baseline alignment, callback plumbing
- [ ] Ensure compatibility with re-highlighting and `lastAppliedText`
- **Verification:** Embed a test NSButton in text view, verify it renders and survives re-highlight.

### Phase 2: Checkbox + Radio Controls (US-2, US-3)
- [ ] CheckboxAttachmentViewProvider
- [ ] RadioAttachmentViewProvider
- [ ] Wire to InteractionHandler
- **Verification:** Toggle checkboxes and select radio options in Classic mode, verify file write-back.

### Phase 3: Dropdown + TextField + CriticMarkup (US-4, US-5, US-6)
- [ ] DropdownAttachmentViewProvider (NSPopUpButton)
- [ ] TextFieldAttachmentViewProvider (NSTextField)
- [ ] CriticMarkupAttachmentViewProvider (Accept/Reject buttons)
- **Verification:** All control types render and interact correctly.

### Phase 4: Mode Toggle + Polish (US-7)
- [ ] Settings toggle
- [ ] Re-render on mode change
- [ ] Accessibility pass
- [ ] Default to Classic
- **Verification:** Switch modes, verify rendering changes. VoiceOver test.

## Definition of Done

- [ ] All 7 user stories pass acceptance criteria
- [ ] Classic mode renders all interactive elements as real NSControls
- [ ] Pro mode unchanged from current implementation
- [ ] Mode toggle persisted and functional
- [ ] Tests pass, build succeeds
- [ ] Accessibility: all controls announce correctly via VoiceOver

## Open Questions
- Should Classic mode controls have a slight visual distinction (e.g., subtle background) to separate them from surrounding text?
- How should nested elements render? (e.g., a choice inside a collapsible section)
- Performance: many embedded views in a large document — need testing

## Implementation Notes
*To be filled during implementation*
