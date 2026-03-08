# Debug Log

<!-- status: active | paused | all clear -->
**Status:** active

---

## Bug 1: Blue dots on sibling files after checkbox toggle

Checking a box in one file causes blue "changed" dots to appear on unrelated files in the sidebar.

- [ ] Fixed and verified

<!-- collapsible: Fix Attempt 1 — Folder change suppression -->
**Root cause:** Atomic writes (`String.write(to:atomically:)`) create a temp file and rename, which updates the parent directory's modification timestamp. The `FolderWatcher` (FSEvents) fires for the directory, and `handleFolderChanges()` marks ALL sibling files as changed via `collectFilePathsUnder()` — not just the file that was actually written.

**Fix:** Added a time-based `folderChangeSuppressedUntil` window on `AppCoordinator`. Every write-back path (`handleInteractiveClick`, `handleInputSubmitted`, `submitStatusAdvance`, file/folder pickers) calls `coordinator.suppressFolderChangeMarking()` before writing. When `handleFolderChanges` fires during the suppression window, it still reloads the tree but skips marking sibling files as modified.

**Files changed:**
- `AppCoordinator.swift` — added `folderChangeSuppressedUntil` property, `suppressFolderChangeMarking()` method, guard in `handleFolderChanges`
- `MarkdownView.swift` — added suppression calls in all 4 write-back entry points
<!-- endcollapsible -->

<!-- feedback -->

---

## Bug 2: Left margin clipped — text starts behind gutter

Text has no left padding. First characters on every line are clipped by or flush against the line number gutter. Happens on initial load and file switch.

- [ ] Fixed and verified

<!-- collapsible: Fix Attempt 1 — Pin horizontal scroll to zero -->
**Hypothesis:** Race condition between two scroll restoration mechanisms on file switch.

**Fix:** Pinned `x: 0` in `applyHighlighting`'s deferred scroll restoration.

**Result:** Did not fix the initial load case. The x offset isn't from scroll — it's from the text container layout itself.
<!-- endcollapsible -->

<!-- collapsible: Fix Attempt 2 — Switch from textContainerInset to lineFragmentPadding -->
**Root cause:** `textContainerInset.width` adds horizontal padding by expanding the text view's intrinsic content width beyond the clip view. This creates a horizontally scrollable area where `x: 0` (the clip view origin) shows the text starting at the padding boundary — i.e., the padding is scrolled offscreen to the left.

`lineFragmentPadding` adds left/right padding WITHIN each line fragment without inflating the content width. The text container stays within the clip view bounds.

**Fix:** Changed `textContainerInset` to height-only, moved horizontal padding to `lineFragmentPadding`:
```swift
textView.textContainerInset = NSSize(width: 0, height: scaledInset)
textView.textContainer?.lineFragmentPadding = scaledInset
```
Also added inset update on font size change in `updateNSView`.

**Files changed:**
- `MarkdownEditor.swift` — `makeNSView` (line ~680) and `updateNSView` (font change block)

**Result:** Reduced the issue but didn't fix it. Text still starts behind the gutter.
<!-- endcollapsible -->

<!-- collapsible: Fix Attempt 3 — scrollView.tile() after ruler setup -->
**Root cause:** NSScrollView needs to recalculate its subview layout after the ruler is added. In a SwiftUI `NSViewRepresentable`, the clip view frame isn't automatically adjusted for the ruler — it fills the full scroll view width, and the ruler draws on top. The text view (document view) fills the un-tiled clip view, so the first 40pt of text content sits behind the 40pt ruler.

**Fix:** Added `scrollView.tile()` after setting up the ruler in `makeNSView`. This forces NSScrollView to reposition the clip view to the right of the ruler. Also tile when toggling ruler visibility in `updateNSView`.

**Files changed:**
- `MarkdownEditor.swift` — `scrollView.tile()` after ruler setup, and on ruler visibility toggle
<!-- endcollapsible -->

<!-- collapsible: Fix Attempt 4 — GutteredScrollView refactor -->
**Root cause:** `NSScrollView.tile()` runs correctly at call time, but SwiftUI's layout system re-frames the scroll view after `makeNSView` returns. The re-frame triggers an internal `tile()` that doesn't properly offset the clip view for the ruler — the clip view stays at `x: 0` and the ruler draws on top of the text.

**Fix:** Full refactor of the scroll view + ruler layout:
1. Created `GutteredScrollView` (NSScrollView subclass) that overrides `tile()` to guarantee the clip view is offset by the ruler's thickness. Runs after every layout pass, catching SwiftUI re-frames.
2. Updated `LineNumberRulerView` init to accept the scroll view explicitly (removed force-unwrap of `enclosingScrollView`).
3. Extracted inset configuration to a shared `configureInsets()` method (eliminated duplication between `makeNSView` and `updateNSView`).
4. Cleaned up scroll restoration comments.

**Files changed:**
- `MarkdownEditor.swift` — Added `GutteredScrollView` class, replaced `NSScrollView()` with `GutteredScrollView()`, added `configureInsets()`, cleaned up ruler setup order
- `LineNumberRulerView.swift` — Init now takes `(textView:scrollView:)` instead of `(textView:)` with force-unwrap
<!-- endcollapsible -->

<!-- feedback -->
