# StartView Redesign — 3 Entry Points (v3.0)

**Issue:** #20
**Date:** 2026-03-27
**Status:** Spec complete, ready for implementation
**Milestone:** v3.0 — Relay MVP

---

## Problem Statement

The current StartView is folder-centric with Desktop/Documents/Downloads shortcuts that don't match how most users arrive at a markdown file. There's no "Open File" button — only "Choose Folder." The layout needs to shift from power-user folder browsing to a simpler "pick your file and go" experience.

## Scope

### In Scope
- Replace Desktop/Documents/Downloads shortcuts with three clear entry points
- Redesign button layout to prominent full-width style
- Time-grouped recents with path breadcrumbs
- Change launch behavior: always show StartView (no auto-restore)
- Add "Open File..." to File menu (Cmd+O)
- Cmd+N opens StartView (already works, confirm preserved)
- Full keyboard navigation in StartView
- New tagline: "Read and Collaborate with your AI's Markdown"

### Out of Scope
- "Create a Project" entry point (requires .pixley format, #19, shelved)
- Project root detection for single-file opens
- Changes to SecurityScopedBookmarkManager
- Changes to browser window behavior
- Auto-reappear of StartView when last browser closes

---

## User Stories

### US-1: New StartView Layout with Entry Points
**Description:** As a user, I want to see three clear actions when the app opens so I can quickly open a file, browse a folder, or explore sample files.

**Acceptance Criteria:**
- [ ] StartView shows mascot header with "Pixley Markdown" and tagline "Read and Collaborate with your AI's Markdown"
- [ ] Three full-width rounded buttons below the header: "Open File", "Open Folder", "Sample Files"
- [ ] "Open File" and "Open Folder" use accent color fill (primary style)
- [ ] "Sample Files" uses tertiary/outline style (dimmer)
- [ ] Button order from top: Open File → Open Folder → Sample Files
- [ ] Desktop/Documents/Downloads shortcut buttons are removed
- [ ] "or drop a folder or .md file anywhere" hint text remains at bottom
- [ ] Mascot header remains clickable (easter egg: opens welcome folder without auto-chat)
- [ ] Drag-and-drop behavior unchanged (accepts folders + .md files)
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### US-2: Time-Grouped Recents with Path Breadcrumbs
**Description:** As a user, I want my recent files organized by when I opened them, with enough context to distinguish items with similar names.

**Acceptance Criteria:**
- [ ] Recents column grouped into sections: "Today", "This Week", "Older"
- [ ] Empty time groups are hidden (only groups with items appear)
- [ ] Each recent item shows: icon + name (primary) + parent folder name (secondary text, dimmer)
- [ ] Folders show folder icon (blue); files show doc icon (secondary)
- [ ] Context menu "Remove from Recents" still works per item
- [ ] "Clear Recents" button at bottom of recents column still works
- [ ] Stale bookmarks silently pruned on appear (same as current)
- [ ] Adaptive sizing: compact (480px) when no recents, wide (720px) when recents exist
- [ ] Animation between compact/wide when recents state changes

### US-3: Launch Behavior — Always Show StartView
**Description:** As a user, I want to always see the StartView when the app launches so I can choose what to work on, rather than being dropped into the last session.

**Acceptance Criteria:**
- [ ] App launch always shows StartView (no auto-restore of last folder/file)
- [ ] First launch (never opened before) still bypasses StartView → goes straight to welcome tour
- [ ] No pre-selection of most recent item in recents list
- [ ] Closing the last browser window does NOT auto-reappear StartView
- [ ] Cmd+N (New Window) shows StartView
- [ ] Re-activating app via Dock click when no windows open shows StartView

### US-4: File Menu — "Open File..." + Keyboard Navigation
**Description:** As a user, I want keyboard shortcuts and menu items to open files without going through the StartView.

**Acceptance Criteria:**
- [ ] "Open File..." (Cmd+O) added to File menu, opens NSOpenPanel filtered to .md/.markdown
- [ ] .pixley UTI included in the file type filter (no-op until format exists, but filter is future-ready)
- [ ] "Open File..." from any context opens the same .md file picker
- [ ] "Open Folder..." (Cmd+Shift+O) remains in File menu, unchanged
- [ ] StartView keyboard navigation: Cmd+O triggers Open File, Cmd+Shift+O triggers Open Folder
- [ ] Tab cycles through entry point buttons
- [ ] Arrow keys navigate the recents list
- [ ] Return/Enter opens the selected (focused) recent item

---

## Technical Design

### Files Modified
- `Sources/Views/Screens/StartView.swift` — Primary rewrite
- `Sources/AIMDReaderApp.swift` — Add "Open File..." menu item, confirm launch behavior
- `Sources/Services/RecentFoldersManager.swift` — Add time-grouping helper method

### Data Model
No schema changes. `RecentItem` already has `dateOpened: Date` which is sufficient for time grouping.

### Time Grouping Logic
Add a computed method to group recents:
```swift
enum RecentTimeGroup: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case older = "Older"
}

func groupedRecents(_ items: [RecentItem]) -> [(RecentTimeGroup, [RecentItem])]
```
- "Today" = `Calendar.current.isDateInToday(dateOpened)`
- "This Week" = same week as today but not today
- "Older" = everything else
- Filter out empty groups

### Button Components
Replace `FolderShortcutButton` with new `EntryPointButton`:
- `style: .primary` (accent fill) or `.tertiary` (outline)
- Full-width, rounded corners, icon + label centered
- Hover and press states

### Launch Behavior Change
In `StartView.determineLaunchRequest()`:
- Remove the `lastSessionFolder` restore path
- Keep first-launch welcome bypass
- All other launches → show StartView (return `nil`)

### File Menu Addition
In `AIMDReaderApp.commands`:
- Add `Button("Open File...")` with `.keyboardShortcut("o", modifiers: [.command])`
- Presents `NSOpenPanel` filtered to `.md`, `.markdown` (and `.pixley` UTI slot)
- Opens browser with parent folder as tree root, sidebar collapsed

### Window Management
- `Cmd+N` already calls `openStartWindow()` — confirm this still works
- No changes to single-instance `Window(id: "start")` behavior

---

## User Experience

### Layout (Compact — No Recents)
```
┌─────────────────────────────────────┐
│                                     │
│          [Pixley mascot]            │
│        Pixley Markdown              │
│  Read and Collaborate with your     │
│        AI's Markdown                │
│                                     │
│   ┌─────────────────────────────┐   │
│   │    📄  Open File            │   │  ← accent fill
│   └─────────────────────────────┘   │
│   ┌─────────────────────────────┐   │
│   │    📁  Open Folder          │   │  ← accent fill
│   └─────────────────────────────┘   │
│   ┌─────────────────────────────┐   │
│   │    📖  Sample Files         │   │  ← tertiary/outline
│   └─────────────────────────────┘   │
│                                     │
│  or drop a folder or .md file       │
│            anywhere                 │
└─────────────────────────────────────┘
         480 × 520
```

### Layout (Wide — With Recents)
```
┌─────────────────────────────────────────────────────────┐
│                          │                              │
│      [Pixley mascot]     │  Recent                      │
│    Pixley Markdown       │                              │
│  Read and Collaborate    │  Today                       │
│  with your AI's Markdown │  📄 design.md                │
│                          │     project                  │
│  ┌────────────────────┐  │  📁 docs                     │
│  │  📄 Open File      │  │     Documents                │
│  └────────────────────┘  │                              │
│  ┌────────────────────┐  │  This Week                   │
│  │  📁 Open Folder    │  │  📄 notes.md                 │
│  └────────────────────┘  │     meetings                 │
│  ┌────────────────────┐  │  📁 specs                    │
│  │  📖 Sample Files   │  │     project                  │
│  └────────────────────┘  │                              │
│                          │  ─────────────────           │
│  or drop a folder or .md │  Clear Recents               │
│  file anywhere           │                              │
└─────────────────────────────────────────────────────────┘
                    720 × 520
```

### Edge Cases
- **No recents**: Compact layout, just buttons
- **All recents in one time group**: Only that section header shows
- **Very long file/folder names**: Truncated with ellipsis (middle truncation for names)
- **Stale bookmarks**: Pruned silently on appear before display
- **First launch**: Bypasses StartView entirely, opens welcome tour

---

## Implementation Phases

### Phase 1: Layout Rewrite + Launch Behavior
**Goal:** New StartView layout with entry points, launch behavior change, File menu addition.

- [ ] Create `EntryPointButton` component (primary + tertiary styles)
- [ ] Rewrite `StartView.shortcutsColumn` → three entry point buttons (Open File, Open Folder, Sample Files)
- [ ] Add "Open File..." NSOpenPanel handler (filtered to .md/.markdown + .pixley UTI slot)
- [ ] Update tagline to "Read and Collaborate with your AI's Markdown"
- [ ] Remove Desktop/Documents/Downloads `FolderShortcutButton` instances
- [ ] Remove `openStandardFolder()` and `showFolderPanel(for:)` methods from StartView
- [ ] Modify `determineLaunchRequest()`: remove last-session restore (keep first-launch welcome)
- [ ] Add "Open File..." (Cmd+O) to File menu in `AIMDReaderApp.swift`
- [ ] Confirm Cmd+N still shows StartView
- [ ] **Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### Phase 2: Time-Grouped Recents + Keyboard Navigation
**Goal:** Enhanced recents column with time grouping, breadcrumbs, and full keyboard nav.

- [ ] Add `RecentTimeGroup` enum and `groupedRecents()` helper to `RecentFoldersManager`
- [ ] Rewrite `recentsColumn` to use grouped sections with headers
- [ ] Add parent folder name as secondary text on each recent item
- [ ] Hide empty time groups
- [ ] Add keyboard shortcuts: Cmd+O (Open File), Cmd+Shift+O (Open Folder) in StartView
- [ ] Add arrow key navigation in recents list
- [ ] Add Return/Enter to open focused recent item
- [ ] Add Tab cycling between entry point buttons
- [ ] **Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-4 pass
- [ ] Both implementation phases verified
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- [ ] Manual smoke test: launch app → see StartView → open file → close browser → Cmd+N → see StartView again
- [ ] Manual smoke test: recents show time groups with parent folder breadcrumbs
- [ ] Manual smoke test: Cmd+O opens file picker, Cmd+Shift+O opens folder picker

## Ralph Loop Command

```bash
/ralph-loop "Implement StartView redesign per spec at docs/specs/github-issue-20.md

PHASES:
1. Layout Rewrite + Launch Behavior: New EntryPointButton component, replace shortcuts with 3 entry points (Open File/Folder/Sample Files), update tagline, remove Desktop/Documents/Downloads shortcuts, change launch to always show StartView, add Open File to File menu - verify with xcodebuild build
2. Time-Grouped Recents + Keyboard Nav: Add RecentTimeGroup grouping, rewrite recents column with sections + breadcrumbs, add Cmd+O/Cmd+Shift+O shortcuts, arrow keys + Return in recents, Tab between buttons - verify with xcodebuild build

VERIFICATION (run after each phase):
- xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```

## Implementation Notes
*(To be filled during implementation)*
