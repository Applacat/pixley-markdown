# iOS Controls Pass — Touch Targets, Control Sizes, Button Styles, Liquid Glass

**Issue:** #74
**Date:** 2026-04-15
**Status:** Spec complete, ready for implementation
**Epic:** #23 (Multiplatform) — Phase 3.5

---

## Problem Statement

The iOS app's controls layer is macOS code running on iPhone. Interactive controls have 22pt touch targets (HIG minimum is 44pt), buttons rely on hover feedback that doesn't exist on touch, materials use pre-Liquid Glass APIs, and headings/code blocks ignore Dynamic Type. 77 findings from 4 Axiom audits (UX Flow, Accessibility, SwiftUI Layout, Liquid Glass).

## Key Decisions

| # | Decision |
|---|---|
| 1 | **Full sweep** — all 77 audit findings in one pass |
| 2 | **Native iOS form style** — system fonts, full-width rows, 44pt+ targets for controls |
| 3 | **Controls as cards** — document stays monospace, controls break out with system font + rounded card background |
| 4 | **Liquid Glass buttons** on StartView — `.glassBackgroundEffect()` with `.interactive()` |
| 5 | **Inline where possible** — fill-ins expand inline, date picker uses `.compact`. Only complex inputs (review, feedback, suggestion) use sheets |
| 6 | **Gutter narrower on iPhone** — ~30pt with smaller font instead of 44pt |
| 7 | **Dynamic Type on both platforms** — semantic fonts (`.largeTitle`, `.title2`, etc.) that scale with system settings |
| 8 | **3 phases** — functional → visual → compliance |

## Scope

### In Scope

**Touch & Controls (Critical/High — 15 items):**
- `.controlSize(.small)` → default on iOS (44pt minimum touch targets)
- Full-row tap for checkboxes, choices, reviews (not just the radio circle)
- Controls rendered as cards: system font, rounded background, visual break from monospace
- Slider `.frame(width: 160)` → `.frame(maxWidth: .infinity)` on iOS
- Fill-in text field inline expansion (no popover)
- Date picker `.graphical` → `.compact` on iOS
- InteractiveSheets: `.frame(maxWidth: .infinity)` on iOS + `.presentationDetents` for complex inputs
- LauncherButtonStyle: Liquid Glass with `.interactive()` press feedback
- MascotButtonStyle: guard `.onHover` behind `#if os(macOS)`
- Filter bar icon buttons: 44pt touch targets
- iOSNavigateUpButton: 44pt minimum height + error feedback on access denied
- `NSHomeDirectory()` guard in FilePathBadge
- ChatView "System Settings" → "Settings" on iOS

**Liquid Glass (High — 14 items):**
- 9 `.ultraThinMaterial` / `.regularMaterial` → `.glassBackgroundEffect()`
- ChatToolbarButton `.borderedProminent` + `.tint()`
- Toolbar grouping on macOS
- Forget button `.bordered` + `.tint(.red)`
- Assistant chat bubbles → glass background
- Suggested prompt chips → glass background

**Accessibility & Dynamic Type (High — 12 items):**
- VoiceOver labels on all NativeControlView control types
- `accessibilityAction` on GutterLineView (bookmark + comment)
- Headings: fixed 14-24pt → semantic `.largeTitle`/`.title2`/`.title3`/`.headline`/`.subheadline` (BOTH platforms)
- Code blocks: fixed 10-12pt → `.caption`/`.caption2` semantic styles
- Code block `height: 16` → `@ScaledMetric`
- `ToggleControl` empty label → surface element label
- `ColorPickerControl` → `accessibilityLabel`
- `MessageBubble` → combined role+content label
- `ReadingProgressBadge` → `.accessibilityHidden(true)`
- `SettingsView` mascot direction buttons → labels + `.isSelected` trait
- iOS `FileRow` → `.accessibilityElement(children: .ignore)` + combined label
- Gutter font: `max(9, fontSize * 0.78)` → `@ScaledMetric` or `.caption2`

**Layout (Medium — 8 items):**
- Gutter: 44pt → ~30pt on iPhone
- `QuickSwitcher` gate behind `#if os(macOS)` (dead on iOS)
- `ViewModePicker` gate behind `#if os(macOS)`
- `FillInTextField` `.frame(maxWidth: 300)` → `.infinity` on iOS
- `StatusPicker` `.frame(maxWidth: 200)` → remove on iOS
- Comment popover 280pt → `minWidth: 280` flexible
- StartView recents: add max height on iOS
- Reduce Motion check on NativeDocumentView scroll-to-line animation

### Out of Scope

- iPad-specific layout (inspector panel, size classes) — deferred
- visionOS — Phase 4
- New features beyond iOS parity
- Plain mode on iOS (stays macOS-only)
- `ConflictBanner` NSFileVersion error recovery (working, edge case)

---

## User Stories

### US-1: Touch Targets & Control Sizes

**Description:** As an iPhone user, I want all interactive controls to be easily tappable so I don't have to try 2-3 times to hit a checkbox or radio button.

**Acceptance Criteria:**
- [ ] All interactive controls have minimum 44pt touch target height
- [ ] `.controlSize(.small)` / `.mini` wrapped in `#if os(macOS)` — iOS uses default
- [ ] Checkboxes: full row taps to toggle (not just the toggle control)
- [ ] Choices/radio: full row taps to select option
- [ ] Slider: `.frame(maxWidth: .infinity)` on iOS
- [ ] Filter bar buttons: `.frame(width: 44, height: 44).contentShape(Rectangle())`
- [ ] iOSNavigateUpButton: `.frame(minHeight: 44)`
- [ ] Both targets build

### US-2: Controls as Cards

**Description:** As an iPhone user, I want interactive controls to look distinct from document text so I know what's tappable.

**Acceptance Criteria:**
- [ ] Interactive controls render as cards: system font, rounded background, padding
- [ ] Document text remains monospace
- [ ] Cards have subtle background (glass or `.quaternary`) to signal interactivity
- [ ] Each control type (checkbox, choice, fill-in, status, confidence, review, suggestion, slider, stepper, toggle, color picker, auditable checkbox) gets card treatment on iOS
- [ ] macOS controls unchanged
- [ ] Both targets build

### US-3: Inline Inputs & iOS Sheets

**Description:** As an iPhone user, I want fill-ins and date pickers to work inline, and complex inputs to use proper iOS sheets.

**Acceptance Criteria:**
- [ ] Fill-in text field expands inline below the control (no popover)
- [ ] Date picker uses `.datePickerStyle(.compact)` on iOS (popup, not inline calendar)
- [ ] Feedback, review notes, suggestion sheets: `.presentationDetents([.medium, .large])` on iOS
- [ ] InteractiveSheets: `.frame(maxWidth: .infinity)` on iOS (no fixed 300-400pt widths)
- [ ] Sheet Cancel/Submit: iOS `.toolbar` with `.cancellationAction` / `.confirmationAction`
- [ ] Both targets build

### US-4: StartView Liquid Glass

**Description:** As an iPhone user, I want the StartView to feel native iOS 26 with Liquid Glass buttons.

**Acceptance Criteria:**
- [ ] `LauncherButtonStyle`: `.glassBackgroundEffect()` with `.interactive()` on iOS
- [ ] `MascotButtonStyle`: `.onHover` guarded behind `#if os(macOS)`
- [ ] Press feedback visible on all buttons (no invisible-until-pressed)
- [ ] Both targets build

### US-5: Material → Liquid Glass Migration

**Description:** Migrate all old material backgrounds to Liquid Glass for iOS 26.

**Acceptance Criteria:**
- [ ] `StartView` `.ultraThinMaterial` → `.glassBackgroundEffect()`
- [ ] `MarkdownView` empty/loading/error states → glass
- [ ] `ReloadPill` `.regularMaterial` → `.glassBackgroundEffect(in: .capsule)`
- [ ] `ReadingProgressBadge` → glass
- [ ] `QuickSwitcher` → glass
- [ ] `ErrorBanner` → glass
- [ ] `ConflictBanner` → glass
- [ ] `GoToLineOverlay` → glass on iOS
- [ ] Suggested prompt chips → glass
- [ ] Assistant chat bubbles → glass
- [ ] ChatToolbarButton `.borderedProminent` + `.tint(.accentColor)`
- [ ] Forget button `.bordered` + `.tint(.red)`
- [ ] Both targets build

### US-6: Accessibility Labels & VoiceOver

**Description:** As a VoiceOver user, I want all interactive controls to announce what they are and what they do.

**Acceptance Criteria:**
- [ ] Every NativeControlView control type has `.accessibilityLabel` using the element's label/text
- [ ] `GutterLineView`: `.accessibilityAction` for bookmark toggle + add comment
- [ ] `ToggleControl`: surface element label (not empty string)
- [ ] `ColorPickerControl`: `.accessibilityLabel`
- [ ] `MessageBubble`: combined "You/Pixley: [content]" label
- [ ] `ReadingProgressBadge`: `.accessibilityHidden(true)`
- [ ] `SettingsView` mascot buttons: label + `.isSelected` trait
- [ ] iOS `FileRow`: `.accessibilityElement(children: .ignore)` + combined label
- [ ] Both targets build

### US-7: Dynamic Type (Both Platforms)

**Description:** As a user with accessibility text size settings, I want all text to scale with my system setting.

**Acceptance Criteria:**
- [ ] Headings: H1→`.largeTitle`, H2→`.title2`, H3→`.title3`, H4→`.headline`, H5+→`.subheadline` (with `.design(.monospaced)`)
- [ ] Code block text: `.caption` semantic style
- [ ] Code block line numbers: `.caption2` semantic style
- [ ] Code block row height: `@ScaledMetric(relativeTo: .caption)` instead of fixed 16pt
- [ ] Gutter line numbers: `.caption2` semantic style or `@ScaledMetric`
- [ ] Changes apply to BOTH macOS and iOS
- [ ] Both targets build

### US-8: Platform Fixes & Cleanup

**Description:** Fix remaining platform-specific issues and dead code.

**Acceptance Criteria:**
- [ ] ChatView `fmUnavailableView`: "System Settings" → "Settings" on iOS
- [ ] `FilePathBadge.abbreviatedParent`: guard `NSHomeDirectory()` behind `#if os(macOS)`
- [ ] `ViewModePicker`: wrap in `#if os(macOS)`
- [ ] `QuickSwitcher` / `.quickSwitcherOverlay`: gate behind `#if os(macOS)`
- [ ] `StatusPicker` `.frame(maxWidth: 200)` → remove on iOS
- [ ] Comment popover: `.frame(minWidth: 280, maxWidth: 340)` instead of fixed 280
- [ ] StartView iOS recents: add `.frame(maxHeight: 300)` cap
- [ ] Gutter: ~30pt width on iPhone (compact size class)
- [ ] NativeDocumentView scroll-to-line: check Reduce Motion
- [ ] Both targets build

---

## Implementation Phases

### Phase 1: Functional — Makes the App Usable
Touch targets, control sizes, button feedback, inline inputs, platform fixes.

- [ ] US-1: Touch targets & control sizes
- [ ] US-3: Inline inputs & iOS sheets
- [ ] US-4: StartView Liquid Glass buttons
- [ ] US-8: Platform fixes & cleanup
- **Verification:** `xcodebuild -scheme AIMDReader-iOS build && xcodebuild -scheme AIMDReader build` + manual test on iPhone: tap every control type, verify responsive

### Phase 2: Visual — Makes It Beautiful
Liquid Glass materials, controls as cards, chat styling.

- [ ] US-2: Controls as cards
- [ ] US-5: Material → Liquid Glass migration
- **Verification:** Both targets build + manual test: controls look distinct from text, materials are glass, buttons have depth

### Phase 3: Compliance — Makes It Correct
Accessibility labels, Dynamic Type, VoiceOver.

- [ ] US-6: Accessibility labels & VoiceOver
- [ ] US-7: Dynamic Type (both platforms)
- **Verification:** Both targets build + VoiceOver test: navigate through a document with interactive elements, verify all controls announce correctly. Dynamic Type test at AX5 size.

---

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-8 pass
- [ ] All 3 phases verified
- [ ] Both targets build: `xcodebuild -scheme AIMDReader -configuration Debug build && xcodebuild -scheme AIMDReader-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- [ ] Manual smoke test on iPhone: every interactive control type tappable and responsive
- [ ] VoiceOver test: all controls announce correctly
- [ ] Dynamic Type test at AX5: headings and code blocks scale
- [ ] macOS behavior unchanged

---

## Implementation Notes
*(To be filled during implementation)*
