# Welcome Flow Refactor

> **Status:** Ready for Implementation
> **Created:** 2026-02-02
> **Scope:** StartView simplification, first-launch experience, session restore

## Summary

Eliminate the confusing two-panel welcome screen. Replace with a clear three-state launch flow:

1. **First launch** → Open directly into bundled Welcome folder (tutorial experience)
2. **Session restore** → Open directly to last-used folder (skip launcher)
3. **No folder state** → Minimal centered launcher (clean, focused)

## Problem Statement

Users report confusion with the current welcome screen. The two-panel layout with "Ask Pixley" and recents is overwhelming for a simple markdown reader. The goal is to teach by doing—not by presenting options.

## Design Principles

- **Show, don't tell** — First-time users learn by using the app, not reading about it
- **Zero decisions on first launch** — Auto-open welcome content immediately
- **Minimal launcher** — When no folder is open, show only what's needed to open one
- **Session continuity** — Returning users pick up where they left off

---

## User Stories

### US-1: First Launch Detection

**As a** new user
**I want** the app to recognize my first launch
**So that** I get the guided welcome experience

**Acceptance Criteria:**
- [ ] `UserDefaults.standard.bool(forKey: "hasLaunchedBefore")` returns `false` on first launch
- [ ] Flag is set to `true` after welcome browser view appears
- [ ] Deleting app data resets the flag (expected behavior)

**Implementation Notes:**
- Add constant `static let hasLaunchedBeforeKey = "hasLaunchedBefore"` to appropriate location
- Check in `PixleyReaderApp` scene phase or initial view

---

### US-2: First Launch Welcome Experience

**As a** first-time user
**I want** to immediately see the app in action with tutorial content
**So that** I understand how to use it without reading instructions

**Acceptance Criteria:**
- [ ] On first launch, browser window opens with bundled `Welcome` folder
- [ ] Sidebar shows all 6 welcome files, folder auto-expanded
- [ ] `01-Welcome.md` is auto-selected and displayed in detail pane
- [ ] No launcher/start window is shown
- [ ] `hasLaunchedBefore` flag is set after view appears

**Implementation Notes:**
- Copy `Resources/Welcome` to temp directory for security-scoped access
- Set `appState.rootFolderURL` to temp welcome folder
- Auto-expand the folder in sidebar (pre-populate `expandedFolders` set)
- Auto-select first `.md` file sorted alphabetically

---

### US-3: Session Restore on Launch

**As a** returning user
**I want** the app to reopen my last folder automatically
**So that** I can continue where I left off

**Acceptance Criteria:**
- [ ] `RecentFoldersManager.lastSessionFolder()` returns most recent folder
- [ ] On launch (when `hasLaunchedBefore == true`), attempt to resolve and open last session folder
- [ ] If successful, browser window opens directly (no launcher shown)
- [ ] If folder unavailable (deleted, unmounted, permission revoked), silently fall back to minimal launcher

**Implementation Notes:**
- Add method to `RecentFoldersManager`:
  ```swift
  func lastSessionFolder() -> RecentFolder? {
      getRecentFolders().first
  }
  ```
- Resolve bookmark with `resolveBookmark()`, check if valid
- No error message on failure—just show launcher

---

### US-4: Minimal Launcher View

**As a** user with no folder open
**I want** a simple, focused launcher
**So that** I can quickly open a folder without distraction

**Acceptance Criteria:**
- [ ] Launcher window is 480x520 pixels
- [ ] Content is centered (not left-aligned two-panel)
- [ ] Shows: Pixley photo, "Pixley Reader" title, "Read what AI writes" subtitle
- [ ] Shows folder shortcuts: Desktop, Documents, Downloads, Choose Folder...
- [ ] Shows footer: "or drop a folder anywhere"
- [ ] NO "Ask Pixley" section
- [ ] NO recents list
- [ ] Supports drag-and-drop folder opening

**Implementation Notes:**
- Refactor `StartView` to remove right panel entirely
- Center the branding panel content
- Update frame constraints to 480x520
- Keep existing `FolderShortcutButton` components
- Keep drop destination functionality

---

### US-5: Pixley Photo Easter Egg

**As a** user who wants to revisit the tutorial
**I want** to click the Pixley photo to reopen the welcome tour
**So that** I can refresh my memory without it being obvious

**Acceptance Criteria:**
- [ ] Single-click on Pixley photo opens Welcome folder in browser
- [ ] Same behavior as current `openWelcomeFolder()` function
- [ ] No visible label or hint (discoverable but not advertised)

**Implementation Notes:**
- Keep existing `PixleyMascotButtonStyle` and click handler
- Existing `openWelcomeFolder()` function already implements this

---

### US-6: Auto-Show Launcher on Window Close

**As a** user who closes the browser window
**I want** the launcher to appear automatically
**So that** the app never has zero windows

**Acceptance Criteria:**
- [ ] Closing browser window shows minimal launcher
- [ ] Closing folder (via menu) shows minimal launcher
- [ ] Clicking dock icon when no windows open shows minimal launcher

**Implementation Notes:**
- In `BrowserView.onDisappear`, call `openWindow(id: "start")`
- Ensure `PixleyReaderApp` handles `applicationShouldHandleReopen` for dock clicks

---

### US-7: Update Welcome Content

**As a** first-time user reading the welcome files
**I want** the content to accurately describe the current app flow
**So that** I'm not confused by outdated references

**Acceptance Criteria:**
- [ ] `01-Welcome.md` does not mention "start screen" or "buttons on the left"
- [ ] Content reflects that user is already viewing the app
- [ ] `03-Ask-Pixley.md` updated to reflect that Ask Pixley is only in browser view
- [ ] All welcome files reviewed for accuracy

**Files to Update:**
- `Resources/Welcome/01-Welcome.md`
- `Resources/Welcome/03-Ask-Pixley.md`
- Review others for consistency

---

## Implementation Phases

### Phase 1: Foundation (US-1, US-3)
- Add `hasLaunchedBefore` flag
- Add `lastSessionFolder()` to RecentFoldersManager
- Wire up launch state detection in app entry point

### Phase 2: Minimal Launcher (US-4, US-5, US-6)
- Refactor StartView to centered single-column layout
- Remove Ask Pixley and recents sections
- Update window size to 480x520
- Ensure window lifecycle (auto-show on close, dock click handling)

### Phase 3: First Launch Experience (US-2)
- Implement first-launch → welcome folder flow
- Auto-expand and auto-select in sidebar
- Set hasLaunchedBefore flag after display

### Phase 4: Content Update (US-7)
- Update welcome markdown files
- Review and test full flow

---

## Verification Commands

```bash
# Build
cd PixleyWriter && swift build

# Run (manual testing required for UI)
cd PixleyWriter && swift run

# Reset first-launch state for testing
defaults delete com.pixley.reader hasLaunchedBefore
```

---

## Out of Scope

- Recents in minimal launcher (removed by design)
- Ask Pixley in launcher (moved to browser only)
- Multiple window support (future consideration)
- Light mode (dark mode only per original spec)

---

## State Machine Reference

```
                      APP LAUNCH
                          │
                          ▼
               Check hasLaunchedBefore
                          │
           ┌──────────────┴──────────────┐
           │ false                       │ true
           ▼                             ▼
    ┌─────────────┐            ┌─────────────────┐
    │ FIRST       │            │ lastSession     │
    │ LAUNCH      │            │ Folder()        │
    │ → Welcome   │            └─────────────────┘
    │   folder    │                    │
    └─────────────┘        ┌───────────┴───────────┐
                           │ resolves              │ nil/fails
                           ▼                       ▼
                    ┌─────────────┐       ┌─────────────────┐
                    │ SESSION     │       │ MINIMAL         │
                    │ RESTORE     │       │ LAUNCHER        │
                    │ → Browser   │       │ → 480x520       │
                    └─────────────┘       └─────────────────┘
```

## Window Transitions

| From | Event | To |
|------|-------|-----|
| Browser | Close window | Minimal Launcher |
| Browser | Close folder (menu) | Minimal Launcher |
| Minimal Launcher | Open folder | Browser |
| Minimal Launcher | Click Pixley | Browser (Welcome) |
| App Launch | First launch | Browser (Welcome) |
| App Launch | Session restore OK | Browser (restored) |
| App Launch | No session | Minimal Launcher |
