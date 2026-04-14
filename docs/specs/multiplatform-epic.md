# Multiplatform Epic — iOS / iPadOS / visionOS

**Status:** Ready for implementation
**Created:** 2026-04-14
**Epic:** #23
**Tickets:** #56, #57, #58, #59, #60, #61

---

## Overview

Bring Pixley Markdown to iOS, iPadOS, and visionOS. Ship **Enhanced mode only** on non-Mac platforms. Add **iCloud Drive integration on all platforms** so users save .md files on Mac and access immediately on iPhone/iPad.

The app is fully free (Relay Pro deprecated). No StoreKit work.

## Key Decisions

| # | Decision |
|---|---|
| 1 | **Enhanced only** on iOS/iPadOS/visionOS. Plain mode stays macOS-exclusive. |
| 2 | **Separate Xcode targets** via XcodeGen — not `#if os()` wrapping whole files. |
| 3 | **iCloud Drive on both platforms** — Mac gets iCloud browsing too, not just iOS. |
| 4 | **Browse any iCloud folder** — full file browser, not a dedicated Pixley folder. |
| 5 | **Cloud status badges** — show downloaded/downloading/cloud-only state. Explicit download on tap. |
| 6 | **Conflict banner** — detect iCloud conflict copies, let user pick which version to keep. |
| 7 | **Reload pill** for iCloud sync changes on iOS (same UX as Mac external edits). |
| 8 | **iOS 18.1+ minimum** — require Apple Foundation Models capable devices. No FM fallback. |
| 9 | **Multi-window on iPadOS** from day 1 — port existing per-window AppCoordinator. |
| 10 | **Adapted StartView** on iOS — recents + "Browse iCloud Drive" button + mascot. |
| 11 | **Incremental merges** to main at phase gates when macOS builds. No macOS release until iOS ready. |
| 12 | **XcodeGen** extended with iOS target in project.yml. User pushes play, Claude handles generation. |

## Scope

### In Scope

- iOS target in XcodeGen project.yml
- iPadOS multi-window support
- visionOS target
- iCloud Drive entitlement, container, provisioning (greenfield)
- iCloud Drive folder browsing on macOS AND iOS
- Download-on-demand with cloud status badges
- iCloud conflict detection + resolution banner
- iOS sidebar (List + DisclosureGroup)
- iOS app lifecycle (Scene-based window management)
- iOS StartView adaptation
- Enhanced-only enforcement on iOS (hide mode picker)
- Reload pill for iCloud-synced file changes
- NSFileCoordinator / NSFilePresenter for safe concurrent access

### Out of Scope

- Plain mode on iOS (stays macOS-exclusive)
- StoreKit / monetization (Relay Pro deprecated)
- New features beyond platform parity (no new controls, no new rendering)
- Mac Catalyst (native SwiftUI targets, not Catalyst)
- watchOS
- Offline-first architecture (iCloud handles offline gracefully already)

---

## Architecture

### Target Structure (XcodeGen project.yml)

```
AIMDReader.xcodeproj
├── AIMDReader (macOS)        — all source files
├── AIMDReader-iOS (iOS)      — cross-platform files only
└── AIMDReader-visionOS       — cross-platform + spatial adaptations
```

### macOS-Only Files (excluded from iOS/visionOS targets)

| File | Lines | Why |
|---|---|---|
| MarkdownEditor.swift | 754 | NSTextView |
| MarkdownEditorCoordinator.swift | 258 | NSTextView delegate |
| MarkdownTextViewNavigation.swift | 147 | NSTextView key handling |
| MarkdownTextViewPopovers.swift | 242 | NSPopover |
| PopoverControllers.swift | 600 | NSViewController |
| LineNumberRulerView.swift | 149 | NSView |
| GutterOverlayView.swift | 272 | NSView |
| OutlineFileList.swift | 697 | NSOutlineView |
| InteractiveAnnotator.swift | 500+ | NSFont/NSColor |
| MarkdownHighlighter.swift | 464 | NSColor |

### Shared Files Needing `#if os()` (~200 lines)

| File | What changes |
|---|---|
| AIMDReaderApp.swift | Menu commands, AppDelegate (macOS only) |
| ContentView.swift | Toolbar placements, sidebar style |
| StartView.swift | Drag-drop (macOS), iCloud browse button (iOS) |

### Cross-Platform Files (shared as-is, ~6,800 lines)

- NativeRenderer: NativeDocumentView, ContentBlockView, NativeControlView, MarkdownBlock, GutterView
- Services: ChatService, TranscriptCondenser, ChatTools, FolderService, InteractionHandler, etc.
- Coordinator: AppCoordinator, CoordinatorRegistry
- Models: all
- Settings: SettingsRepository
- Views: ChatView, SettingsView, QuickSwitcher, ErrorBanner

### New Shared Code (iCloud)

| Component | Purpose |
|---|---|
| iCloudBrowser | SwiftUI view for browsing iCloud Drive folders |
| CloudFileManager | NSFileCoordinator/NSFilePresenter wrapper |
| CloudStatusBadge | Download state indicator (badge view) |
| ConflictResolver | Detect conflict copies, present resolution UI |
| iCloudFileWatcher | Monitor file changes via NSFilePresenter (replaces DispatchSource on iOS) |

---

## Branching Strategy

```
main (shipping macOS, untouched until iOS ready)
 └── multiplatform/ios (long-lived integration branch)
      ├── multiplatform/phase-1-target    → merge to multiplatform/ios → merge to main
      ├── multiplatform/phase-2-icloud    → merge to multiplatform/ios → merge to main
      ├── multiplatform/phase-3-ios-ui    → merge to multiplatform/ios → merge to main
      └── multiplatform/phase-4-visionos  → merge to multiplatform/ios → merge to main
```

Each phase merges to main at its gate **only if macOS still builds and works**. If disaster strikes, `main` is always in a shipping state.

---

## Implementation Phases

### Phase 1: Structure — Target + Build (#56)

Add the iOS target. Both platforms compile. No new features.

**Stories:**

**US-1: Add iOS target to XcodeGen project.yml**
- Add iOS target definition with deployment target iOS 18.1
- Configure source file membership (exclude macOS-only files)
- Set iOS-specific build settings (bundle ID, info.plist)

*Acceptance:*
- [ ] `xcodegen generate` produces project with both macOS and iOS targets
- [ ] `xcodebuild -scheme AIMDReader -configuration Debug build` succeeds (macOS)
- [ ] `xcodebuild -scheme AIMDReader-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` succeeds
- [ ] macOS app behavior unchanged

**US-2: Platform conditionals in shared files**
- `#if os(macOS)` in AIMDReaderApp.swift (menu commands, AppDelegate)
- `#if os(macOS)` in ContentView.swift (toolbar placements)
- `#if os(macOS)` in StartView.swift (drag-drop handling)
- `#if os(iOS)` stubs where needed (placeholder views)

*Acceptance:*
- [ ] Both targets build with zero `#if` errors
- [ ] macOS app launches and works identically to pre-branch
- [ ] iOS simulator launches to a placeholder or adapted StartView

**US-3: Enhanced-only enforcement on iOS**
- Hide Plain/Enhanced mode picker on iOS
- Default to Enhanced mode
- Remove any code paths that reference Plain mode on iOS

*Acceptance:*
- [ ] iOS target has no reference to InteractiveMode.plain in active code paths
- [ ] Mode picker not visible on iOS
- [ ] Both targets build

**Verification:**
```bash
xcodegen generate
xcodebuild -scheme AIMDReader -configuration Debug build
xcodebuild -scheme AIMDReader-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Gate:** Merge to main when both targets build and macOS is unchanged.

---

### Phase 2: iCloud Drive Integration (#57, #58)

The hardest, most novel work. iCloud Drive on BOTH macOS and iOS.

**Stories:**

**US-4: iCloud entitlement + container setup**
- Add iCloud capability to both targets
- Create ubiquitous container identifier
- Configure entitlements file
- Update provisioning profiles (manual step — document for user)

*Acceptance:*
- [ ] Both targets have iCloud entitlement in build settings
- [ ] Ubiquitous container identifier configured
- [ ] Both targets build with entitlement

**US-5: iCloud Drive folder browser (shared)**
- New SwiftUI view: iCloudBrowser
- Uses FileManager.url(forUbiquityContainerIdentifier:) to access iCloud Drive
- Shows folder hierarchy with expand/collapse
- Shows .md files with tap-to-open
- Shows cloud status badges (downloaded / downloading / cloud-only)
- Works on both macOS and iOS

*Acceptance:*
- [ ] Browse iCloud Drive folders on macOS
- [ ] Browse iCloud Drive folders on iOS simulator
- [ ] Cloud-only files show cloud badge
- [ ] Downloaded files show checkmark or no badge
- [ ] Tapping a cloud-only file starts download + shows progress
- [ ] Tapping a downloaded .md file opens it in Enhanced mode

**US-6: NSFileCoordinator / NSFilePresenter integration**
- Wrap file reads/writes in NSFileCoordinator for safe concurrent access
- Implement NSFilePresenter to receive change notifications
- Replace DispatchSource file watching on iOS with NSFilePresenter

*Acceptance:*
- [ ] File reads coordinated (no partial reads during sync)
- [ ] File writes coordinated (no corruption during concurrent edits)
- [ ] iOS receives file change notifications via NSFilePresenter
- [ ] macOS FileWatcher still works (DispatchSource preserved, coordinator added)

**US-7: Reload pill for iCloud sync changes**
- When NSFilePresenter detects a file change on the currently viewed document:
  - Show reload pill (same UX as macOS external edit detection)
  - User taps → reload document content
- Works on both platforms

*Acceptance:*
- [ ] Edit .md file on Mac → iOS shows reload pill within 30 seconds
- [ ] Tap reload pill → document content updates
- [ ] Pill dismisses after reload or after timeout

**US-8: Conflict detection + resolution banner**
- Detect iCloud conflict copies (files named "... (conflict).md")
- Show banner: "This file was edited on another device. View changes?"
- Present both versions, let user pick
- Delete the conflict copy after resolution

*Acceptance:*
- [ ] Conflict copy detected within 60 seconds of sync
- [ ] Banner appears with clear description
- [ ] User can pick either version
- [ ] Conflict copy removed after resolution
- [ ] No data loss in either resolution path

**US-9: macOS StartView — add "Browse iCloud Drive" option**
- Add iCloud Drive as a source alongside existing folder open + recents
- New button/entry point on StartView
- Opens iCloudBrowser when tapped

*Acceptance:*
- [ ] macOS StartView shows "Browse iCloud Drive" option
- [ ] Tapping opens iCloud folder browser
- [ ] Existing folder open + recents still work unchanged

**Verification:**
```bash
xcodebuild -scheme AIMDReader -configuration Debug build
xcodebuild -scheme AIMDReader-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
# Manual: test iCloud sync between Mac and iPhone
```

**Gate:** Merge to main when iCloud browsing works on both platforms with conflict handling.

---

### Phase 3: iOS UI (#59, #60)

The iOS-specific UI layer. Sidebar, app lifecycle, StartView.

**Stories:**

**US-10: iOS sidebar — List + DisclosureGroup folder browser**
- Replace NSOutlineView with SwiftUI List + DisclosureGroup
- Same FolderItem model
- Tap folder → expand/collapse
- Tap .md file → select + open in detail
- Navigate-up button for parent folders
- Used on iOS only (macOS keeps OutlineFileList)

*Acceptance:*
- [ ] iOS sidebar shows folder hierarchy from iCloud Drive
- [ ] Folders expand/collapse on tap
- [ ] .md files open in Enhanced mode on tap
- [ ] Navigate-up button works
- [ ] macOS sidebar unchanged (still OutlineFileList)

**US-11: iOS app lifecycle — Scene-based window management**
- SwiftUI App lifecycle (no NSApplicationDelegate on iOS)
- Scene phase handling (foreground/background)
- Multi-window on iPadOS via WindowGroup
- Per-window AppCoordinator (port existing pattern)

*Acceptance:*
- [ ] iOS app launches correctly
- [ ] Background → foreground preserves state
- [ ] iPadOS: can open multiple windows (Simulator test)
- [ ] Each window has independent coordinator

**US-12: iOS StartView adaptation**
- Adapted StartView with:
  - Pixley mascot + branding
  - "Browse iCloud Drive" primary action
  - Recent files list
- No folder shortcuts (iOS doesn't have the same folder picker concept)
- No drag-drop (iOS uses share sheet / Files app instead)

*Acceptance:*
- [ ] iOS StartView shows mascot + recents + iCloud button
- [ ] Tapping "Browse iCloud Drive" opens iCloudBrowser
- [ ] Tapping a recent file opens it directly
- [ ] No macOS-specific UI visible (no NSOpenPanel, no drag-drop target)

**US-13: iOS navigation polish**
- NavigationSplitView with sidebar + detail
- Toolbar adapted for iOS (placement, sizing)
- AI Chat as sheet or inspector (not sidebar panel)
- Keyboard shortcuts for external keyboard (Cmd+F, Cmd+G, etc.)

*Acceptance:*
- [ ] Navigation feels native on iPhone (push/pop)
- [ ] Navigation feels native on iPad (split view)
- [ ] AI Chat accessible and dismissible
- [ ] External keyboard shortcuts work on iPad

**Verification:**
```bash
xcodebuild -scheme AIMDReader-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
# Manual: test on physical iPhone, iPad simulator
```

**Gate:** Merge to main when iOS app is functional end-to-end.

---

### Phase 4: visionOS (#61)

Layer on top of the iOS target. Smallest phase.

**Stories:**

**US-14: Add visionOS target**
- New target in project.yml
- Same source files as iOS target
- visionOS-specific build settings

*Acceptance:*
- [ ] `xcodebuild -scheme AIMDReader-visionOS` builds
- [ ] All three targets build simultaneously

**US-15: visionOS UI adaptation**
- Remove hover state assumptions
- Adapt touch targets for spatial input
- Test Enhanced renderer in spatial computing context
- Window ornaments if applicable

*Acceptance:*
- [ ] visionOS simulator launches app
- [ ] Enhanced mode renders correctly
- [ ] No crash from missing hover/mouse APIs
- [ ] Documents readable and interactive

**Verification:**
```bash
xcodebuild -scheme AIMDReader-visionOS -configuration Debug -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build
```

**Gate:** Merge to main. All four targets build. Ready for App Store submission.

---

## Test Strategy

| Platform | Device | Method |
|---|---|---|
| macOS | Development Mac | Direct build + run |
| iPhone | Physical iPhone | Xcode deploy via USB |
| iPad | Xcode Simulator | iPad Pro simulator (no physical device) |
| visionOS | Xcode Simulator | Apple Vision Pro simulator |

**iCloud sync testing:** Requires physical iPhone + Mac on same Apple ID. Cannot be fully tested in simulator.

**Regression:** After every phase merge, verify macOS app launches and opens a document without regression.

---

## Definition of Done

This epic is complete when:
- [ ] All 15 user stories pass their acceptance criteria
- [ ] All 4 phase gates passed
- [ ] macOS, iOS, and visionOS targets build from same project
- [ ] iCloud Drive browsing works on macOS and iOS
- [ ] User can: save .md on Mac → open on iPhone within 60 seconds
- [ ] Conflict handling works end-to-end
- [ ] Enhanced mode feature parity on iOS (checkboxes, fill-ins, choices, AI chat)
- [ ] No macOS regressions

---

## Tickets

| Phase | Ticket | Title |
|---|---|---|
| 1 | #56 | Add iOS target with shared cross-platform sources |
| 2 | #57 | iOS file access layer (fileImporter + iCloud Drive) |
| 2 | #58 | iCloud Drive integration — browse and sync .md folders |
| 3 | #59 | iOS sidebar — List + DisclosureGroup folder browser |
| 3 | #60 | iOS app lifecycle — Scene-based window management |
| 4 | #61 | visionOS adaptation — spatial input + hover removal |

**New tickets needed:**
- iCloud entitlement + container setup (US-4)
- iCloud conflict detection + resolution (US-8)
- macOS StartView iCloud browse option (US-9)
- iOS StartView adaptation (US-12)
- iOS navigation polish (US-13)
- Enhanced-only enforcement on iOS (US-3)
