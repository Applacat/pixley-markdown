# What's New Since v2.2

Baseline: **v2.2** (App Store, Mar 2 2026) — folder watching with change indicators.

---

## Per-Turn Transcript Condensation
_Commit 8968b08 — Mar 3_

Replaced the hard 3-turn AI session reset with per-turn transcript condensation. After each Q&A exchange, an AI summarizer compresses the conversation so context carries forward indefinitely. Summaries persist in SwiftData per document (LRU cap 50), survive app restarts. Includes heuristic fallback if AI summarizer fails.

## Multi-Window Support
_Commit e592e37 — Mar 4_

Each browser window now creates its own `AppCoordinator` with independent NavigationState, UIState, and DocumentState. Added `CoordinatorRegistry` for bulk operations and `@FocusedValue(\.activeCoordinator)` for menu targeting. Navigate-up button in sidebar.

## Interactive Markdown Protocol (Phases 1–4)
_Commits 5ed4d3c → 589476e — Mar 4–5_

The core feature: detect and interact with AI-generated markdown patterns directly in the document.

- **Phase 1 — Foundation:** `InteractiveElementDetector`, `InteractionHandler` write-back engine, sandbox entitlement
- **Phase 2 — Core Patterns:** Checkbox toggle, choice (radio in blockquote), fill-in-the-blank, feedback
- **Phase 3 — Advanced Patterns:** Reviews (approvals + QA), CriticMarkup accept/reject, status state machines, confidence indicators, progress bars
- **Phase 4 — AI Integration:** FM context optimization, voice commands via `EditInteractiveElementsTool`, starter document

9 interactive patterns total. All with atomic read-modify-write and FileWatcher suppression.

## Voice Commands for Interactive Elements
_Commit cd0367e — Mar 5_

AI chat can now modify interactive elements via natural language ("mark all Section 3 tasks as done"). Uses Foundation Models tool-calling with `EditInteractiveElementsTool`.

## CriticMarkup Accept/Reject Sheet
_Commit 255d5e7 — Mar 5_

Native sheet UI for reviewing CriticMarkup suggestions (insertions, deletions, replacements) with Accept/Reject actions.

## Native Date Picker
_Commit 7a4e0ec — Mar 5_

`[[pick date]]` fill-in placeholders now show a native macOS date picker popover.

## Interactive Elements UX Deep Pass (Prose Mode)
_Commits 2ea9bd2, 9953f4b, 62b853a — Mar 6_

Made interactive elements visually discoverable for non-coders:
- Hover states with tooltips on all interactive elements
- Expanded click targets beyond just the text
- CriticMarkup delimiter dimming (gray out `{++` / `--}` noise)
- Status badge color coding
- Enhanced visual affordances throughout

## Interactive Mode Toggle
_Commit 20a8ec7 — Mar 6_

Added Enhanced/Plain mode toggle in toolbar and Settings. Plain mode shows raw markdown; Enhanced mode shows visual affordances and click interaction.

## Premium Gate (Pixley Pro — $9.99)
_Commit f54a59f — Mar 7_

One-time StoreKit 2 purchase gating all interactive elements except checkboxes:
- `StoreService` with transaction listener, purchase/restore, refund handling
- Upgrade popover when free users click Pro elements
- Settings Pro tab, app menu item
- AI tool gating (EditInteractiveElementsTool returns explanation for free users)
- `SelfDescribingElement` protocol + `SectionResolver` for structured AI interaction

## Liquid Glass Rendering Engine
_Commit 5fc40cb — Mar 7_

Full SwiftUI rendering mode with glass material sections:
- `LiquidGlassDocumentView` with collapsible heading sections
- Native SwiftUI controls for all interactive element types
- Cmd+F find bar with yellow highlight and match navigation
- Code blocks as glass cards with copy button
- Pro-gated (requires Pixley Pro)

## Code Extractions
_Commit 9974a3a — Mar 7_

Extracted `PopoverControllers.swift` from MarkdownEditor and `InteractiveAnnotator.swift` from MarkdownHighlighter for maintainability.

## Hybrid Interactive Mode + ViewModePicker Redesign
_Commit e1dfa56 — Mar 8_

Added Hybrid mode (NSTextView + native control overlays). Redesigned ViewModePicker as a compact menu instead of segmented control.

## Line Number Gutter
_Commits 64aa3c5 — Mar 9_

Rebuilt line number gutter as a sibling view alongside the text view (previous approach via text container insets broke rendering). Added mascot direction setting.

## Folder Watcher Optimization
_Commit f1f5df2 — Mar 9_

Skip folder watcher reload when the file tree hasn't actually changed. Reduces unnecessary UI updates.

## Fill-In Re-Edit Popover + MarkdownEditor Extraction
_Commit 5376b79 — Mar 10_

Fixed fill-in re-edit popover positioning. Extracted `MarkdownEditor` as standalone NSViewRepresentable. Renamed app to "Pixley" throughout.
