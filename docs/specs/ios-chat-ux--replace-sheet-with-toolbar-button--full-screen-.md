# iOS Chat UX — Toolbar Button + Full-Screen Push

**Issue:** #72
**Date:** 2026-04-15
**Status:** Spec complete, ready for implementation
**Epic:** #23 (Multiplatform) — Phase 3 polish

---

## Problem Statement

The current iOS chat uses a sheet with detents. Once dismissed, there's no visible way to bring it back. On iPhone's small screen, a sheet overlay feels wrong — it covers the document partially and competes for attention. The chat needs a dedicated, discoverable entry point and its own full-screen space.

## Scope

### In Scope
- Replace sheet-based chat with full-screen NavigationStack push on iOS
- Persistent chat toolbar button (trailing, always visible when file selected)
- History dot indicator on chat button (Mail/Messages pattern)
- Remove custom ChatView header on iOS — use NavigationStack nav bar
- "Forget" button as toolbar trailing item on iOS
- Full AI feature parity (edit tool works from chat on iOS)

### Out of Scope
- iPad-specific treatment (inspector panel) — deferred to future pass
- Changes to macOS chat (inspector panel stays as-is)
- #70 (spurious reload pill) — separate fix
- #71 (chat auto-open on first launch) — separate fix
- Suggested prompts layout changes — keep as-is on iOS

---

## User Stories

### US-1: Chat toolbar button with history indicator

**Description:** As a user viewing a document on iOS, I want a persistent chat button so I can always access Pixley Chat.

**Acceptance Criteria:**
- [ ] Chat bubble icon visible in trailing toolbar position when a file is selected
- [ ] Icon is `bubble.left.and.bubble.right` (outline)
- [ ] Small filled circle overlay appears when chat history exists for the current document
- [ ] Dot disappears when conversation is reset via "Forget"
- [ ] Button hidden when no file is selected
- [ ] macOS toolbar unchanged (still uses AIChatModifier inspector toggle)
- [ ] Build succeeds: `xcodebuild -scheme AIMDReader-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

### US-2: Full-screen chat push navigation

**Description:** As a user, I want tapping the chat button to push a full-screen chat view so I can focus on the conversation.

**Acceptance Criteria:**
- [ ] Tapping chat button pushes ChatView via NavigationStack
- [ ] Navigation bar shows "Pixley Chat" as title
- [ ] Back button shows document name (standard iOS back behavior)
- [ ] "Forget" (reset) button in trailing toolbar position (↺ icon)
- [ ] Custom ChatView header (`chatHeader`) hidden on iOS — nav bar replaces it
- [ ] Suggested prompts appear when no messages (same as macOS)
- [ ] Input field at bottom with keyboard avoidance
- [ ] Tapping back pops to document, scroll position preserved

### US-3: Remove sheet-based chat on iOS

**Description:** Remove the current iOSChatModifier sheet presentation and replace with the push navigation.

**Acceptance Criteria:**
- [ ] `iOSChatModifier` removed from ContentView.swift
- [ ] No sheet presentation of chat on iOS
- [ ] `coordinator.ui.isAIChatVisible` still used to track push state (or replaced with NavigationPath)
- [ ] AI edit tool (editInteractiveElements) works from chat — edits apply to file, visible when user pops back
- [ ] Both iOS and macOS targets build
- [ ] macOS behavior completely unchanged

---

## Technical Design

### Navigation Architecture

The chat push lives inside BrowserView's NavigationSplitView detail column. On iOS, when the user taps the chat button, a NavigationLink pushes ChatView onto the detail's NavigationStack.

```
BrowserView
  └── NavigationSplitView
        ├── sidebar: iOSSidebarView
        └── detail: NavigationStack
              ├── MarkdownView (root)
              │     toolbar: [FontSize] [Chat 💬]
              └── ChatView (pushed)
                    toolbar: [Forget ↺]
```

### Files Modified

| File | Change |
|------|--------|
| `Sources/ContentView.swift` | Remove `iOSChatModifier`, add chat NavigationLink + toolbar button to iOS branch |
| `Sources/Views/Screens/ChatView.swift` | Conditionally hide `chatHeader` on iOS (`#if os(macOS)`) |
| `Sources/Views/Components/ChatToolbarButton.swift` | **NEW** — Reusable button with history dot indicator |

### Chat History Detection

Use existing `ChatSummaryRepository` to check if a summary exists for the current document:

```swift
private var hasHistory: Bool {
    guard let url = coordinator.navigation.selectedFile,
          let repo = coordinator.chatSummaryRepository else { return false }
    return repo.getSummary(for: url.path) != nil
}
```

### History Dot Overlay

```swift
Image(systemName: "bubble.left.and.bubble.right")
    .overlay(alignment: .topTrailing) {
        if hasHistory {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .offset(x: 3, y: -3)
        }
    }
```

### ChatView Header Conditional

```swift
// In ChatView.body:
#if os(macOS)
chatHeader
Divider()
#endif
```

On iOS, the NavigationStack provides the title bar. The "Forget" button moves to `.toolbar { ToolbarItem(placement: .confirmationAction) }`.

---

## Implementation Phases

### Phase 1: Chat toolbar button + push navigation
- [ ] Create `ChatToolbarButton` with history dot indicator
- [ ] Add NavigationLink/NavigationDestination for ChatView in iOS detail column
- [ ] Add chat button to iOS toolbar (trailing position)
- [ ] Wire push state (NavigationPath or @State bool)
- [ ] **Verification:** `xcodebuild -scheme AIMDReader-iOS build` + run on simulator, tap chat button, see full-screen chat

### Phase 2: ChatView iOS adaptation + cleanup
- [ ] Hide `chatHeader` on iOS (`#if os(macOS)`)
- [ ] Add "Forget" as toolbar trailing button on iOS
- [ ] Remove `iOSChatModifier` from ContentView.swift
- [ ] Verify suggested prompts display correctly
- [ ] Verify AI edit tool works (toggle a checkbox from chat, pop back, see change)
- [ ] **Verification:** Both targets build, macOS inspector unchanged, iOS push works end-to-end

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-3 pass
- [ ] Chat button visible and tappable on iOS
- [ ] Full-screen push with native nav bar + back button
- [ ] History dot appears/disappears correctly
- [ ] "Forget" resets conversation and clears dot
- [ ] AI edit tool works from chat on iOS
- [ ] macOS behavior completely unchanged
- [ ] Both targets build: `xcodebuild -scheme AIMDReader -configuration Debug build && xcodebuild -scheme AIMDReader-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- [ ] Manual smoke test on iPhone

---

## Implementation Notes
*(To be filled during implementation)*
