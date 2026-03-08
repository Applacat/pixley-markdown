# Cross-Platform Compatibility Report

**Date:** 2026-03-07
**Targets:** iOS 26 / iPadOS 26 / visionOS (new) + macOS 15+ (existing)
**Conclusion:** ~70-75% code shareable. No hard blockers. Recommended: multi-target, not Catalyst.

---

## Platform Availability Matrix

| Framework / API | macOS 15+ | iOS 26 / iPadOS 26 | visionOS 2+ |
|---|---|---|---|
| SwiftUI (NavigationSplitView, WindowGroup) | Yes | Yes | Yes |
| SwiftData | Yes | Yes | Yes |
| AppKit (NSView, NSTextView, NSOutlineView) | Yes | **No** | **No** |
| UIKit | No | Yes | Yes (partial) |
| Foundation Models (`LanguageModelSession`) | macOS 26+ | **iOS 26+** | **Unknown** |
| `DispatchSource.makeFileSystemObjectSource` | Yes | **No** | **No** |
| `FSEventStream` (FSEvents) | Yes | **No** | **No** |
| `NSOpenPanel` | Yes | **No** | **No** |
| Security-scoped bookmarks | Yes | **Partial** (different options) | **No** |
| `Settings` scene | Yes | **No** | **No** |

---

## Shared Code Estimate

| Category | Lines | Shareable | Notes |
|---|---|---|---|
| Models (FolderItem, ChatMessage, etc.) | ~109 | **100%** | Pure value types |
| Coordinator (AppCoordinator, Registry) | ~549 | **~90%** | FolderWatcher ref is macOS-specific |
| Persistence (SwiftData models + repos) | ~415 | **100%** | Fully cross-platform |
| Settings (SettingsRepository) | ~288 | **100%** | UserDefaults-backed |
| Services (Chat, Folder, Welcome, etc.) | ~892 | **~95%** | Minor path differences |
| FileWatcher + FolderWatcher | ~180 | **0% on iOS** | macOS-only APIs |
| SecurityScopedBookmarkManager | ~166 | **~70%** | Bookmark options differ |
| RecentFoldersManager | ~371 | **~85%** | Bookmark creation differs |
| Views (pure SwiftUI) | ~563 | **~90%** | Minor adaptations |
| Views (AppKit-specific) | ~1,064 | **0%** | Must rewrite for iOS |
| Views (mixed) | ~1,457 | **~75%** | NSOpenPanel, NSApp refs |
| AIMDReaderApp | ~351 | **~30%** | Heavy platform code |
| MarkdownHighlighter | ~289 | **~80%** | NSColor→UIColor |

**Total: 6,680 lines. ~70-75% shareable as-is or with minor `#if os()` conditionals.**

---

## AppKit Dependencies — Migration Assessment

### Hard (complete rewrite needed)

#### OutlineFileList.swift (597 lines)
- **Uses:** NSOutlineView, NSScrollView, NSTableCellView, NSButton, NSLayoutConstraint
- **iOS replacement:** SwiftUI `List` + `OutlineGroup`, custom row views for star/dot/count
- **Note:** Largest and most complex AppKit component

#### MarkdownEditor.swift (346 lines)
- **Uses:** NSTextView, NSTextFinder, NSLayoutManager, NSTextContainer, NSCursor, NSClipView
- **iOS replacement:** `UITextView` + `UIViewRepresentable`, `UIFindInteraction` for find bar
- **Note:** NSTextView↔UITextView mapping is mostly 1:1 but large surface area

#### AIMDReaderApp.swift (351 lines)
- **Uses:** NSApplicationDelegate, NSApp, NSOpenPanel, NSTextFinder, NSWindow, NSMenuItem
- **iOS replacement:** UIApplicationDelegateAdaptor, toolbar actions, fileImporter modifier
- **Note:** Must split or heavily `#if os()` gate. Settings scene → in-app sheet on iOS

#### LineNumberRulerView.swift (121 lines)
- **Uses:** NSRulerView, NSBezierPath, NSLayoutManager
- **iOS replacement:** Custom UIView overlay with CoreGraphics drawing
- **Note:** Can ship iOS without line numbers initially

#### FileWatcher.swift + FolderWatcher.swift (~180 lines)
- **Uses:** DispatchSource.makeFileSystemObjectSource, FSEventStream
- **iOS replacement:** **None equivalent.** Use foreground-resume polling (check modification dates when app returns from background)
- **Note:** No live file watching on iOS. Accept "check on resume" pattern

### Medium

#### MarkdownHighlighter.swift (289 lines)
- NSColor→UIColor, NSFont→UIFont, NSFontTraitMask→UIFontDescriptor.SymbolicTraits
- Mechanical replacement. Use `PlatformColor`/`PlatformFont` typealiases

#### ContentView.swift (440 lines)
- NSApp.windows, NSOpenPanel (NavigateUpButton), NSWorkspace.reduceMotion
- Most view is pure SwiftUI. Platform pieces isolated

#### StartView.swift (439 lines)
- NSOpenPanel (2 usages, already `#if os(macOS)`)
- Replace with `fileImporter` on iOS

### Easy

#### ChatView.swift (373 lines)
- One `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` → `UIAccessibility.isReduceMotionEnabled`

#### ErrorBanner.swift (85 lines)
- `import AppKit` but no actual AppKit API usage. Delete the import

#### MarkdownView.swift (205 lines)
- Hosts MarkdownEditor. Easy once MarkdownEditor is ported

---

## Key Architectural Changes

### 1. File Access (CRITICAL)

| | macOS | iOS/iPadOS |
|---|---|---|
| Folder picker | NSOpenPanel | `fileImporter` modifier |
| Folder browsing | Direct filesystem access | Security-scoped access per session |
| Bookmarks | `.withSecurityScope` option | Standard bookmarks (different options) |
| Persistence | Bookmark data in UserDefaults | Same, but different creation flags |

### 2. File Watching (CRITICAL)

| | macOS | iOS/iPadOS |
|---|---|---|
| File changes | DispatchSource (real-time) | **Not available** |
| Folder changes | FSEventStream (real-time) | **Not available** |
| Mitigation | — | Check modification dates on foreground resume |
| iCloud files | FSEvents detects | NSMetadataQuery for iCloud-backed folders |

### 3. Window Management

| | macOS | iOS/iPadOS |
|---|---|---|
| Multi-window | WindowGroup + Window | WindowGroup (iPad only) |
| Settings | Settings scene | In-app settings sheet |
| Menu bar | CommandGroup | Toolbar actions |
| About panel | NSApp.orderFrontStandardAboutPanel | Custom view |

### 4. Foundation Models

- Already guarded with `#if canImport(FoundationModels)` and `@available(macOS 26, *)`
- Just add `@available(iOS 26, *)` alongside existing annotations
- Available on iPhone 16+ and M-series iPads running iOS/iPadOS 26
- **visionOS: unconfirmed** — ship without AI chat on visionOS

---

## Recommended Approach

### Single project, multiple platform targets

```yaml
# project.yml additions
targets:
  PixleyMarkdown-iOS:
    type: application
    platform: iOS
    sources:
      - path: Sources
      - path: Resources/Assets.xcassets
      - path: Resources/Welcome
    settings:
      base:
        IPHONEOS_DEPLOYMENT_TARGET: "26.0"
```

### Platform abstraction layer

```swift
#if canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage
#endif
```

### Do NOT use Mac Catalyst
- App already has excellent AppKit integration
- Catalyst would force UIKit-on-macOS compromise
- Multi-target with shared code is the right approach

---

## visionOS Assessment

**Recommendation: Deprioritize.** Ship macOS + iPadOS first.

- Foundation Models not confirmed
- File access model is most restrictive
- "Browse local markdown folders" is a poor fit for spatial computing
- Window management differs fundamentally (volumetric windows)
- Could revisit if Apple confirms FM support and adds better file access

---

## iCloud Sync

**No special integration needed.** If the user's markdown files are in an iCloud Drive folder:
- Changes sync automatically via the OS
- macOS: AI writes file → iCloud syncs → iOS: Pixley sees updated file on foreground resume
- The user picks a folder that happens to be in iCloud Drive — Pixley just reads/writes files

This enables the killer cross-platform workflow:
1. AI (Cursor/Claude on Mac) writes interactive markdown to iCloud folder
2. File syncs to iPhone/iPad automatically
3. Human opens in Pixley Markdown on iPhone, responds (checks boxes, approves, fills in)
4. Changes sync back to Mac
5. AI reads the updated file and continues
