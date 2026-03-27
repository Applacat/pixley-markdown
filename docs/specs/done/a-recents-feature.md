# Recents Feature — Specification

**Status:** PENDING
**Created:** 2026-02-28
**Source:** Lisa interview

---

## Overview

Surface recently opened folders and files in the StartView launcher and in the File > Open Recent menu. The existing `RecentFoldersManager` already tracks up to 10 folders and 4 files with security-scoped bookmarks — this feature connects that data to the UI.

## Problem Statement

The app tracks recent folders and files internally but never shows them to the user. The StartView shows static shortcuts (Desktop, Documents, Downloads) that are less useful than a personalized recents list. There is no File > Open Recent menu.

---

## Scope

### In Scope
- StartView recents panel alongside existing folder shortcuts (side-by-side layout)
- File > Open Recent submenu in the menu bar
- Stale bookmark pruning (silent removal of dead entries)
- Right-click "Remove from Recents" context menu
- "Clear Recents" / "Clear Menu" actions

### Out of Scope
- Quick Switcher (Cmd+P) integration with recents
- iCloud sync of recents
- Pinned/favorited folders (separate from recents)
- Changing the recents cap (stays at 10 folders + 4 files in RecentFoldersManager)

---

## User Stories

### US-1: StartView Side-by-Side Layout with Recents Panel

**Description:** Expand the StartView window to show the existing shortcuts on the left and a recents list on the right, following the standard macOS welcome window convention (like Xcode, Pixelmator). When no recents exist (first launch), the window stays at its current compact size with shortcuts only.

**Layout (with recents):**
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                  [Mascot + Title]                        │
│                                                         │
│   Shortcuts            │  Recent                        │
│   ──────────────────   │  ──────────────────────────    │
│   Read Sample Files    │  MyProject/          folder    │
│   Desktop              │  notes.md            file      │
│   Documents            │  Docs/               folder    │
│   Downloads            │  api-spec.md         file      │
│   Choose Folder...     │  Archive/            folder    │
│                        │                                │
│                        │           Clear Recents        │
│                                                         │
│              ~ or drop a folder or .md file ~           │
└─────────────────────────────────────────────────────────┘
```

**Layout (no recents — first launch / cleared):**
```
┌───────────────────────────┐
│                           │
│     [Mascot + Title]      │
│                           │
│   Read Sample Files       │
│   Desktop                 │
│   Documents               │
│   Downloads               │
│   Choose Folder...        │
│                           │
│  ~ or drop a folder ~    │
└───────────────────────────┘
```

**Acceptance Criteria:**
- [ ] When `getAllRecents()` returns items, window expands to side-by-side layout (~720x520 or similar)
- [ ] Left side: all existing shortcuts remain (Read Sample Files, Desktop, Documents, Downloads, Choose Folder...)
- [ ] Right side: recents list with "Recent" header, interleaved folders + files sorted by date
- [ ] When `getAllRecents()` returns empty, window stays at current compact size (480x520) with shortcuts only
- [ ] Recents panel shows all available items (no arbitrary cap — list scrolls if needed)
- [ ] Folder icon (folder symbol) and file icon (doc.text symbol) distinguish item types
- [ ] No timestamps shown — order communicates recency
- [ ] Clicking a recent folder opens it with sidebar visible (existing `openFolder()` flow)
- [ ] Clicking a recent file opens its parent folder + selects the file with sidebar collapsed (`requestSidebarCollapsed()`)
- [ ] Right-click on any item shows context menu with "Remove from Recents"
- [ ] "Remove from Recents" calls `removeFolder()` or `removeRecentFile()` and refreshes the list
- [ ] "Clear Recents" button/link at bottom of recents panel calls `clearAll()`; window animates back to compact size
- [ ] Drop zone hint stays at the bottom spanning full width
- [ ] Mascot + title centered across full width
- [ ] `swift build` succeeds

### US-2: File > Open Recent Submenu

**Description:** Add a File > Open Recent submenu to the menu bar showing the same interleaved recents list with a "Clear Menu" item at the bottom.

**Acceptance Criteria:**
- [ ] "Open Recent" submenu appears in the File menu (via `CommandGroup`)
- [ ] Shows the same interleaved folders + files as StartView (from `getAllRecents()`)
- [ ] Menu items show folder/file names (no timestamps)
- [ ] Clicking a folder item opens it with sidebar visible
- [ ] Clicking a file item opens its parent folder + selects file with sidebar collapsed
- [ ] Separator + "Clear Menu" item at the bottom
- [ ] "Clear Menu" calls `clearAll()` and empties the submenu
- [ ] Menu updates dynamically when recents change (SwiftUI menu rebuilds on state change)
- [ ] Empty state: submenu shows a disabled "No Recent Items" placeholder
- [ ] `swift build` succeeds

### US-3: Stale Item Pruning

**Description:** Validate each recent item when building the display list. Silently remove items whose bookmarks can't be resolved or whose files/folders no longer exist on disk.

**Acceptance Criteria:**
- [ ] When building the recents list for display, each folder item is validated via `resolveBookmark()`
- [ ] Folders that fail resolution are removed via `removeFolderByPath()`
- [ ] Each file item is validated by checking `FileManager.default.fileExists(atPath:)`
- [ ] Files that no longer exist are removed via `removeRecentFile()`
- [ ] Pruning happens once when the list is first displayed (not on every render)
- [ ] Pruning does not block the main thread (items are loaded from in-memory cache)
- [ ] After pruning, if no items remain, StartView falls back to folder shortcuts
- [ ] `swift build` succeeds

---

## Technical Design

### Data Flow

Both StartView and the File > Open Recent menu read directly from `RecentFoldersManager.shared`. No AppCoordinator wrapper needed.

```
RecentFoldersManager.shared.getAllRecents()
  → returns [RecentItem] (folders + files interleaved by date)
  → StartView shows all (scrollable recents panel on right side)
  → File > Open Recent shows all
```

### Key Methods Already Available

| Method | Purpose |
|--------|---------|
| `getAllRecents()` | Merged folder+file list sorted by date |
| `resolveBookmark(_:)` | Validate folder bookmark, returns URL or nil |
| `removeFolder(_:)` | Remove a folder from recents |
| `removeRecentFile(_:)` | Remove a file from recents |
| `clearAll()` | Clear all recents |
| `addFolder(_:)` | Add folder (already called on open) |
| `addRecentFile(_:parentFolder:)` | Add file (already called on select) |

### New Code Needed

1. **StartView layout refactor:** HStack with shortcuts (left) + recents panel (right). Window size toggles between compact (480x520, no recents) and expanded (~720x520, with recents) using `.frame()` conditionally.
2. **RecentsListView (or inline):** Scrollable list of recent items with folder/file icons, right-click context menu
3. **Pruning function:** Validates items and removes stale ones, called once on StartView appear
4. **CommandGroup for Open Recent:** New menu section in AIMDReaderApp commands
5. **Window resize:** The Start window currently uses `.windowResizability(.contentSize)` — the frame change should drive the window size automatically

### File Open Flow (for recent files)

```
User clicks recent file →
  1. Get parentPath from RecentItem
  2. Find matching RecentFolder by path
  3. Resolve folder bookmark
  4. coordinator.openFolder(resolvedURL)
  5. coordinator.selectFile(fileURL)
  6. coordinator.requestSidebarCollapsed()
  7. activateOrOpenBrowser()
  8. dismissWindow(id: "start")
```

If parent folder bookmark can't be resolved, silently remove the file from recents (it's inaccessible without the folder's security scope).

---

## Edge Cases

1. **All recents pruned:** After validation, no items remain → window collapses to compact size (shortcuts only)
2. **File exists but parent folder bookmark stale:** File is inaccessible → remove from recents
3. **Folder renamed/moved:** Bookmark resolution fails → silently removed
4. **App first launch:** No recents → compact window with shortcuts only (no recents panel)
5. **User clears recents:** `clearAll()` → window animates to compact size, recents panel disappears
6. **Mixed validity:** Some items valid, some stale → show valid ones, prune stale ones
7. **Window resize animation:** Transition between compact/expanded should feel smooth (withAnimation)

---

## Implementation Phases

### Phase 1: StartView Recents Panel (US-1 + US-3)
- Expand StartView to side-by-side layout (shortcuts left, recents right) when recents exist
- Dynamic window sizing: compact (480x520) vs expanded (~720x520)
- Implement stale item pruning
- Add right-click context menu
- Add "Clear Recents" action with window collapse animation
- **Verification:** `swift build` succeeds, manual test: open folders/files to build recents, relaunch app, verify side-by-side layout appears

### Phase 2: File > Open Recent Menu (US-2)
- Add Open Recent submenu via CommandGroup
- Wire click actions for folders and files
- Add "Clear Menu" item
- **Verification:** `swift build` succeeds, manual test: verify menu shows recents, clicking items opens them correctly

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1, US-2, US-3 pass
- [ ] `swift build` succeeds with 0 errors
- [ ] StartView shows recents when they exist, shortcuts when they don't
- [ ] File > Open Recent submenu works with both folders and files
- [ ] Stale items are silently pruned
- [ ] Right-click removal and Clear Recents/Clear Menu both work
