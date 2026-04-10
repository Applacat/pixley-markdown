# Renderer Foundation

**Version:** 1.0
**Date:** 2026-04-09
**Status:** Spec
**Milestone:** v4: Native Renderer (ships as part of v3)
**Issues:** #47, #48, #49

---

## Overview

Reskin the Liquid Glass SwiftUI renderer to use the monospace theme aesthetic (SyntaxPalette), delete the old Enhanced NSTextView mode, and collapse InteractiveMode from 4 cases to 2 (Plain + Enhanced). The reskinned SwiftUI renderer becomes the new "Enhanced" mode.

## Problem Statement

The Enhanced NSTextView rendering mode is structurally buggy — SF symbol replacements cause text reflow, attribute run fragmentation breaks click targets, popover/text-storage race conditions require deferred highlighting, and scroll position thrashes on interactive edits. These stem from fighting NSTextView's attributed string system to make markdown look different from its source.

The Liquid Glass SwiftUI renderer has the right architecture (typed block parser + SwiftUI views + native controls) but the wrong visual identity (glass materials, nested containers). The fix: reskin to match the monospace theme aesthetic, make it the new Enhanced, and delete the old Enhanced.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout model | **Flat scroll** | No section containers. Headings are inline styled text. Code-editor feel. |
| Theme bridge | **SwiftUI-first rewrite** | SyntaxPalette stores SwiftUI Color natively. Plain mode converts to NSColor. |
| Parse performance | **Cache + diff** | Cache previous block array. SwiftUI ForEach diffing handles minimal re-renders. |
| Plain mode scope | **Keep interactive** | Plain stays as-is with InteractiveAnnotator. No changes to Plain mode. |
| Collapsibles | **DisclosureGroup inline** | Only "container" element in the flat scroll. |
| Control style | **Native macOS widgets** | Toggle, Picker, TextField stay as standard SwiftUI controls. They stand out intentionally. |
| Cleanup depth | **Aggressive** | Remove all Enhanced-only code paths from MarkdownEditor, not just dead branches. |
| Feature gap | **Stub APIs** | NativeDocumentView accepts callback signatures for bookmarks, gutter, scroll, Add Comment as no-ops. |
| Test strategy | **Unit tests only** | Update palette/highlighter tests, delete dead Enhanced tests, add cache+diff tests. Manual visual verification. |
| Release | **Part of v3** | Ships alongside other v3 work. Settings migration at v3 launch. |

---

## Scope

### In Scope

- Reskin LiquidGlassDocumentView → flat monospace scroll using SyntaxPalette
- Delete GlassSectionView entirely
- Rewrite SyntaxPalette to SwiftUI Color-first (NSColor via computed property)
- Delete Enhanced NSTextView code paths (enhanced=true InteractiveAnnotator, SF symbol replacement, enhanced-only popover infrastructure)
- Aggressive cleanup of MarkdownEditor (remove hover tracking, popover workarounds, native indicator logic that only served Enhanced)
- Collapse InteractiveMode enum to `.plain` + `.enhanced`
- Rename `Views/LiquidGlass/` → `Views/NativeRenderer/`, types accordingly
- Cache + diff for MarkdownBlockParser output
- UserDefaults migration: "Hybrid" or "Liquid Glass" → "Enhanced"
- Stub API surface for bookmarks, gutter, scroll restore, reading progress, Add Comment
- Update settings UI to plain/enhanced toggle

### Out of Scope

- Line numbers, bookmarks, gutter implementation (Spec 2)
- Scroll position save/restore implementation (Spec 3)
- Add Comment / hover states / keyboard navigation (Spec 4)
- Native rendering blocks: tables, images, code blocks as embedded views (Spec 5)
- New controls: slider, stepper, toggle, color picker, auditable checkbox (Spec 6)

---

## User Stories

### US-1: SyntaxPalette SwiftUI Color Rewrite

**Description:** As a developer, I want SyntaxPalette to store SwiftUI Color natively so the new renderer can consume theme colors directly.

**Acceptance Criteria:**
- [ ] `SyntaxPalette` properties are `Color` type (not `NSColor`)
- [ ] `SyntaxPalette` has computed `nsColor` accessors (e.g. `backgroundNSColor`) for Plain mode
- [ ] All 10 themes produce identical hex colors as before
- [ ] `SyntaxThemeSetting` light/dark resolution works unchanged
- [ ] Existing `SyntaxThemeSettingTests` pass (updated for new API)
- [ ] `ThemeTests` in aimdRenderer package pass (updated for new API)
- [ ] `swift build` succeeds

### US-2: Flat Scroll Renderer (Reskin)

**Description:** As a user in Enhanced mode, I want to see a flat monospace document styled with my chosen syntax theme, not glass blocks.

**Acceptance Criteria:**
- [ ] Document renders as flat `LazyVStack` — no nested section containers
- [ ] Background color matches `palette.background`
- [ ] Foreground text uses `palette.foreground`
- [ ] Headings render with bold/semibold weight + size differentiation (24/20/17/15/14pt) + palette accent color
- [ ] Code blocks render with `palette.background` tint + monospace font + copy button
- [ ] Blockquotes render with palette-colored leading bar
- [ ] Inline styles (bold, italic, strikethrough, code, links) render correctly
- [ ] Lists (ordered + unordered) render correctly
- [ ] Horizontal rules render as divider
- [ ] All existing interactive controls (checkbox, choice, fill-in, feedback, status, confidence, suggestion, review) remain functional
- [ ] Collapsible sections render as SwiftUI DisclosureGroup
- [ ] Cmd+F search still works
- [ ] `GlassSectionView.swift` deleted
- [ ] No `.ultraThinMaterial` or `.background(.bar)` in renderer code

### US-3: Delete Enhanced NSTextView Mode

**Description:** As a developer, I want the old Enhanced NSTextView code removed so there's one rendering path per mode.

**Acceptance Criteria:**
- [ ] `InteractiveAnnotator.annotateInteractiveElements` enhanced=true path deleted
- [ ] `replaceWithNativeIndicators` method deleted
- [ ] `makeSFSymbolAttachment` method deleted
- [ ] Enhanced-only popover infrastructure removed from MarkdownEditor
- [ ] Hover state tracking (NSTrackingArea for interactive elements) removed from MarkdownNSTextView
- [ ] Focus highlight management removed
- [ ] SF-symbol-aware range expansion logic (`fullInteractiveElementRange`) removed
- [ ] Popover dismissal race condition workaround removed
- [ ] Plain mode (`enhanced=false` path) still works: click targets, tooltips, check glyphs
- [ ] `swift build` succeeds with no dead code warnings
- [ ] All remaining tests pass

### US-4: Collapse InteractiveMode Enum

**Description:** As a user, I want to see only Plain and Enhanced in settings, with Enhanced being the new SwiftUI renderer.

**Acceptance Criteria:**
- [ ] `InteractiveMode` has exactly 2 cases: `.plain`, `.enhanced`
- [ ] `.hybrid` and `.liquidGlass` deleted
- [ ] `MarkdownView.markdownContent` routes `.enhanced` to `NativeDocumentView`, `.plain` to `MarkdownEditor`
- [ ] Settings UI shows Plain / Enhanced picker (no Hybrid, no Liquid Glass)
- [ ] UserDefaults containing "Hybrid" or "Liquid Glass" resolve to `.enhanced` on load
- [ ] `ContentView.availableModes` updated
- [ ] Fresh install defaults to `.enhanced`

### US-5: Rename LiquidGlass → NativeRenderer

**Description:** As a developer, I want consistent naming that reflects the renderer's purpose.

**Acceptance Criteria:**
- [ ] `Views/LiquidGlass/` directory renamed to `Views/NativeRenderer/`
- [ ] `LiquidGlassDocumentView` renamed to `NativeDocumentView`
- [ ] No "LiquidGlass" or "Glass" in type names, file names, or comments
- [ ] All references updated throughout codebase
- [ ] `swift build` succeeds

### US-6: Cache + Diff for Block Parsing

**Description:** As a user editing interactive elements, I want the renderer to update efficiently without visible lag.

**Acceptance Criteria:**
- [ ] `NativeDocumentView` caches previous `[MarkdownBlock]` array
- [ ] On content change, re-parses and updates cached blocks
- [ ] `MarkdownBlock` conforms to `Equatable` (or has stable identity for SwiftUI diffing)
- [ ] Toggling a checkbox in a 500-line document does not cause full view re-render (verify with Instruments or `Self._printChanges()`)
- [ ] Unit test: parse same content twice → identical block arrays

### US-7: Stub API Surface for Future Features

**Description:** As a developer working on later specs, I want the NativeDocumentView API surface ready for bookmarks, gutter, scroll, and Add Comment.

**Acceptance Criteria:**
- [ ] `NativeDocumentView` accepts optional callbacks: `onScrollPositionChanged`, `onToggleBookmark`, `onGutterAction`, `onAddComment`
- [ ] All callbacks are no-ops (not wired to UI yet)
- [ ] `MarkdownView` passes these callbacks from coordinator (same wiring as MarkdownEditor)
- [ ] Reading progress badge overlay added to NativeDocumentView container (hardcoded 0% until scroll tracking is implemented)

---

## Implementation Phases

### Phase 1: SyntaxPalette Rewrite

- [ ] Rewrite `SyntaxPalette` to use SwiftUI `Color`
- [ ] Add `NSColor` computed accessors
- [ ] Update `SwiftUITheme` in aimdRenderer package
- [ ] Update all tests
- **Verification:** `cd AIMDReader && swift build && swift test`

### Phase 2: Flat Scroll Renderer

- [ ] Remove GlassSectionView
- [ ] Rewrite LiquidGlassDocumentView as flat LazyVStack with palette styling
- [ ] Update ContentBlockView to use palette colors
- [ ] Add cache + diff logic
- [ ] Add Equatable to MarkdownBlock
- [ ] Verify all interactive controls work
- **Verification:** `swift build` + manual: open a markdown file in Enhanced mode, toggle checkboxes, verify theme colors

### Phase 3: Delete Enhanced + Collapse Enum

- [ ] Delete enhanced=true code paths from InteractiveAnnotator
- [ ] Aggressive cleanup of MarkdownEditor (hover, popovers, SF symbols)
- [ ] Collapse InteractiveMode to 2 cases
- [ ] Update MarkdownView routing
- [ ] Update settings UI
- [ ] Add UserDefaults migration
- [ ] Delete dead tests, update remaining tests
- **Verification:** `swift build && swift test` + manual: toggle between Plain and Enhanced, verify both work

### Phase 4: Rename + Stubs + Polish

- [ ] Rename LiquidGlass → NativeRenderer (directory + types)
- [ ] Add stub API surface for future features
- [ ] Add reading progress badge overlay
- [ ] Final dead code sweep
- [ ] Update CLAUDE.md key files section
- **Verification:** `swift build && swift test` + `grep -r "LiquidGlass\|liquidGlass" Sources/` returns nothing

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-7 pass
- [ ] All implementation phases verified
- [ ] Tests pass: `cd AIMDReader && swift test`
- [ ] Build succeeds: `cd AIMDReader && swift build`
- [ ] No "LiquidGlass" references in source
- [ ] InteractiveMode has exactly 2 cases
- [ ] Enhanced mode shows flat monospace document with palette colors
- [ ] Plain mode unchanged
- [ ] All 10 syntax themes render correctly in Enhanced mode

---

## Technical Notes

### Files Deleted
- `GlassSectionView.swift`
- Enhanced branches of `InteractiveAnnotator.swift` (methods: `annotateInteractiveElements` enhanced=true, `replaceWithNativeIndicators`, `makeSFSymbolAttachment`, `replaceBracketArea`)
- Enhanced-only infrastructure in `MarkdownEditor.swift` and `MarkdownNSTextView`

### Files Modified
- `SyntaxPalette` / `SyntaxTheme` (aimdRenderer package) — Color rewrite
- `LiquidGlassDocumentView.swift` → `NativeDocumentView.swift` — flat scroll + palette
- `ContentBlockView.swift` — palette colors instead of hardcoded
- `NativeControlView.swift` — inherit palette environment
- `MarkdownView.swift` — routing update
- `SettingsRepository.swift` — enum collapse + migration
- `ContentView.swift` — availableModes update
- `SettingsView.swift` — picker update
- `InteractiveAnnotator.swift` — delete enhanced paths, keep plain
- `MarkdownEditor.swift` — aggressive cleanup
- `MarkdownBlock.swift` — Equatable conformance

### Files Renamed
- `Views/LiquidGlass/` → `Views/NativeRenderer/`
- `LiquidGlassDocumentView` → `NativeDocumentView`

### Migration
- UserDefaults `interactiveMode`: "Hybrid" or "Liquid Glass" → "Enhanced"
- No data migration needed (renderer is stateless)
