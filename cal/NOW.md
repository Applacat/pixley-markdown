# NOW — Current Focus

**Idea:** Pixley 3.0 — Premium Gate + Interactive Protocol
**Phase:** Spec 1 SHIPPED — ready for next spec
**Pipeline:** Spec 1 [DONE] → Spec 2 [PENDING] → Spec 3 [PENDING] → Spec 4 [PENDING]

## Spec 1: Premium Gate + Self-Describing Protocol — COMPLETE

Committed as `f54a59f`. All 8 user stories implemented:
- StoreService (DockPops pattern) with 16 unit tests
- Interaction gate + NSPopover upgrade prompt
- Settings Pro tab + app menu item
- SelfDescribingElement protocol (10 conformances, sacred code)
- SectionResolver for heading-based element grouping
- AI tool entitlement gate

## Remaining Specs

### Spec 2: Classic Rendering Mode
Real NSControls via NSTextAttachmentViewProvider (NSButton, NSPopUpButton, NSTextField inline in NSTextView). Both Classic and Pro modes are free — visual preference only.

### Spec 3: Pixley Modal + AI Interaction
Inline chat component with editable rows, section-aware resolution, [+] add row.

### Spec 4: .pixley Bundle Format
Document bundle with markdown contents, chat logs, context/summary for AI orientation.

## Uncommitted Prior Work (3 files)
- ContentView.swift, MarkdownHighlighter.swift, InteractionHandler.swift
- From v1.1 native controls work (pre-Spec 1)

## Deferred Items
- US-12: Conditional/Collapsible (NSTextView layout complexity)
- US-14: Gutter Refactor (significant extension)
- US-18/19: Multiplatform + Ecosystem
