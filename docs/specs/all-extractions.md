# OOD Atomization Extractions

**Status:** Revised after OOD review (2026-03-08)
**Created:** 2026-03-07
**Revised:** 2026-03-08
**Priority:** US-1 and US-2 now; US-3, US-4, US-5 dropped

## Overview

2 independent refactoring stories to decompose files with genuine cohesion problems. Pure behavior-preserving extractions — no user-visible changes. Each story lands independently, fix-forward on any issues.

3 originally proposed stories (US-3, US-4, US-5) were dropped after critical OOD review determined they would fragment cohesive units or constitute cosmetic shuffling.

## Scope

**In scope:** 2 extractions, compilation verification
**Out of scope:** New features, behavior changes, performance optimization, arbitrary line-count thresholds

## User Stories

### US-1: Popover Controllers (MarkdownEditor.swift -> PopoverControllers.swift)

**What:** Move the 5 inline NSViewController subclasses and InputPopoverConfig from MarkdownEditor into their own file. These are autonomous view controllers with their own `loadView()` implementations, layout constraints, and action handlers — they are *used by* MarkdownNSTextView but do not depend on its internal state.

**Design decisions:**
- Keep all 5 controllers as distinct types (no premature unification into a single configurable presenter — a date picker, text input, suggestion diff view, and upgrade prompt are not variations of the same thing)
- Move: `UpgradePopoverController`, `InputPopoverController`, `InputPopoverConfig`, `DatePickerPopoverController`, `SuggestionPopoverController`
- One file: `Sources/PopoverControllers.swift`
- The routing method `showElementPopover` stays in `MarkdownNSTextView` (it uses text view internals like `glyphRect`)

**Acceptance criteria:**
- [ ] `PopoverControllers.swift` exists with all 5 controller types + InputPopoverConfig
- [ ] Popover controllers are independently discoverable in their own file
- [ ] All existing tests pass
- [ ] All popover interactions work identically (checkbox, choice, review, fill-in, feedback, suggestion, upgrade)
- [ ] MarkdownEditor.swift no longer contains NSViewController subclasses (except MarkdownNSTextView itself)

**Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build && cd Packages/aimdRenderer && swift test`

---

### US-2: Interactive Annotator (MarkdownHighlighter.swift -> InteractiveAnnotator.swift)

**What:** Extract interactive element annotation methods from MarkdownHighlighter into a dedicated InteractiveAnnotator. The highlighter knows about markdown syntax (headings, bold, code blocks). The annotator knows about interactive element semantics (checkboxes, choices, reviews, fill-ins). These are genuinely different responsibilities operating on the same NSMutableAttributedString.

**Design decisions:**
- InteractiveAnnotator receives font info as parameters (baseFont, resolveFont reference) — does NOT duplicate MarkdownHighlighter.resolveFont
- Attribute keys as static `NSAttributedString.Key` extensions (AppKit convention)
- Moves: `annotateInteractiveElements`, `annotatePlainClickTargets`, `replaceCheckGlyphs`, `replaceWithNativeIndicators`, `replaceBracketArea`, `makeSFSymbolAttachment`, `annotateProgressBars`, `annotateSectionProgress`, `dimCriticMarkupDelimiters`, `reviewStatusColor`, `CriticDecoration` enum
- One file: `Sources/InteractiveAnnotator.swift`
- MarkdownHighlighter calls InteractiveAnnotator for annotation passes

**Acceptance criteria:**
- [ ] `InteractiveAnnotator.swift` exists with annotation logic
- [ ] Annotation logic is independently testable (can construct annotator without full MarkdownHighlighter)
- [ ] Font dependency is injected, not duplicated
- [ ] All existing tests pass
- [ ] Interactive element highlighting works identically in both Enhanced and Plain modes

**Verification:** `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build && cd Packages/aimdRenderer && swift test`

---

### US-3: Interaction Routing — DROPPED

**Reason:** Would degrade InteractionHandler's cohesion. InteractionHandler is currently a clean file-mutation service that knows nothing about the UI layer. Moving element-type routing into it would force view-level concerns (NSOpenPanel, AppCoordinator, FileWatcher) into a service that currently has none. The switch statements in MarkdownView are inherently view-level routing — they decide which service method to call AND handle view-specific operations like file/folder pickers. The current structure (view routes, handler writes) is already the correct separation.

---

### US-4: Toolbar Extension — DROPPED

**Reason:** ViewModePicker, FontSizeControls, and AIChatModifier are already extracted as separate struct types with their own body properties. The proposed "extraction" would be reorganizing already-well-organized code within the same file for zero testability or discoverability gain. The "body must be 80 lines" criterion is arbitrary numerology, not an OOD principle. The toolbar declaration in BrowserView is 10 lines of ToolbarItem wrappers calling already-extracted views.

---

### US-5: Folder Change Tracker — DROPPED

**Reason:** Folder watching is inherently coordination — it reads navigation state, modifies display items, tracks changed paths, and calls FolderService. Extracting it would either (a) give the tracker direct access to NavigationState, breaking the coordinator's role as mutation gatekeeper, or (b) add a synchronization layer between tracker properties and NavigationState. At 411 lines of coordinator code (not counting co-located state containers), the coordinator is not pathologically large. The folder watcher code is 130 lines with clear MARK sections. If the coordinator grows significantly in the future, this extraction could be revisited.

---

## Implementation Plan

**Phase 1 — Now:** US-1 (Popover Controllers) and US-2 (Interactive Annotator)

**Phase 2 — Dropped:** US-3, US-4, US-5 dropped after OOD review

**Risk strategy:** Fix forward. If an extraction breaks something, fix it in the same work, don't revert.

## Definition of Done

- [ ] All acceptance criteria pass for US-1 and US-2
- [ ] All existing tests pass
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
