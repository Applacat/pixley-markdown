# Specification: Liquid Glass Rendering Engine

*Finalized: 2026-03-07*

## Overview

A premium rendering mode ("Liquid Glass") that replaces the current NSTextView attributed-string approach with a fully native SwiftUI block/canvas renderer. Markdown headings create nested glass-material containers that visually compound (deeper = more opaque). All interactive AIMD elements render as native macOS controls. Available alongside existing Enhanced/Plain modes as a premium (Pro) feature.

## Problem Statement

Current rendering uses NSTextView with attributed strings. Interactive elements (checkboxes, choices, date pickers, sliders, etc.) are faked with SF Symbols and text styling. This limits the UX to "CLI with colors." Users want a native GUI experience where every interactive element is a real macOS control, and the document structure is visually expressed through glass material layering.

## Scope

### In Scope

- Pure SwiftUI document renderer as a new rendering mode
- Glass material nesting driven by heading hierarchy (H1 > H2 > H3 > H4)
- Collapsible sections (click heading to toggle)
- All AIMD interactive elements as native macOS controls
- SF Mono typography throughout
- Code blocks as glass cards with copy button
- Inline markdown formatting (bold, italic, inline code, links, images)
- Tappable links (open in browser)
- Inline image rendering
- Cmd+F search with yellow highlight within glass blocks
- Immediate file write-back on control changes
- LazyVStack for performance
- Premium feature gating (Pro unlock)

### Out of Scope

- Text editing (read-only renderer)
- PDF/HTML export from glass view
- Theme customization for Liquid Glass (one look)
- Custom fonts (SF Mono only)
- Animated transitions between rendering modes

## User Stories

### US-1: Glass Document Structure

**Description:** As a user, I want to see my markdown document rendered with nested glass material blocks based on heading structure, so the visual hierarchy matches the document structure.

**Acceptance Criteria:**
- [ ] Document renders inside a root glass material container
- [ ] Each H1 creates a nested glass block within the root
- [ ] Each H2 creates a nested glass block within its parent H1
- [ ] H3 and H4 continue nesting (cap visual compounding at depth 4)
- [ ] Content before the first heading renders on the root blob
- [ ] Deeper sections appear progressively more opaque due to material compounding
- [ ] SF Mono is used for all text
- [ ] Project builds without errors

### US-2: Collapsible Sections

**Description:** As a user, I want to click a heading to collapse/expand its section, so I can focus on relevant content.

**Acceptance Criteria:**
- [ ] Clicking heading text toggles collapse/expand of that section
- [ ] No disclosure triangle — heading text is the sole affordance
- [ ] Collapsed sections show heading text + line count badge (e.g., "42 lines")
- [ ] Collapse state is per-session (not persisted across app launches)
- [ ] Nested sections collapse with their parent
- [ ] Project builds without errors

### US-3: Native Interactive Controls

**Description:** As a user, I want all AIMD interactive elements to render as native macOS controls, so interactions feel native and immediate.

**Acceptance Criteria:**
- [ ] Checkbox renders as Toggle with `.toggleStyle(.checkbox)`
- [ ] Choice (radio) renders as Picker (segmented or menu depending on option count)
- [ ] Fill-in (text) renders as TextField
- [ ] Fill-in (date) renders as DatePicker (graphical calendar)
- [ ] Fill-in (file/folder) renders as Button that opens NSOpenPanel
- [ ] Feedback renders as TextEditor (multiline)
- [ ] Status renders as Picker (menu style dropdown)
- [ ] Confidence renders as Gauge or custom bar
- [ ] Suggestion renders as diff view with Accept/Reject buttons
- [ ] Review renders as segmented Picker + optional TextEditor for notes
- [ ] Every control change writes back to the .md file immediately
- [ ] Project builds without errors

### US-4: Static Content Rendering

**Description:** As a user, I want all standard markdown elements to render correctly within glass blocks.

**Acceptance Criteria:**
- [ ] Paragraphs render as styled Text views
- [ ] Bold, italic, inline code render with appropriate font traits
- [ ] Links are tappable and open in the default browser
- [ ] Images render inline at natural size
- [ ] Code blocks render as glass cards with a Copy button
- [ ] Blockquotes render with a visual inset/accent
- [ ] Horizontal rules render as dividers
- [ ] Ordered and unordered lists render with proper indentation
- [ ] Tables render as grid layouts
- [ ] Project builds without errors

### US-5: In-Document Search

**Description:** As a user, I want Cmd+F search within the glass-rendered document, so I can find content quickly.

**Acceptance Criteria:**
- [ ] Cmd+F opens a find bar at the top of the document view
- [ ] Typing highlights all matches with a yellow glow within their glass blocks
- [ ] Arrow keys / Enter jump between matches with scroll-to
- [ ] Match count displayed (e.g., "3 of 12")
- [ ] Escape or click-away dismisses the find bar
- [ ] Project builds without errors

### US-6: Mode Selection & Premium Gate

**Description:** As a user, I want to select Liquid Glass as my rendering mode, gated behind Pro.

**Acceptance Criteria:**
- [ ] Liquid Glass appears as a rendering mode option in Settings
- [ ] Selecting it when not Pro shows the purchase prompt
- [ ] Pro users can freely switch between Enhanced, Plain, and Liquid Glass
- [ ] Mode preference persists across app launches
- [ ] Project builds without errors

## Technical Design

### Data Model

No new data models required. Reuses:

- **`DocumentStructure` / `Section`** from `MarkdownStructureParser` — provides the heading tree that drives glass block nesting
- **`InteractiveElementDetector`** — detects AIMD interactive elements within each section's content
- **`InteractionHandler`** — handles write-back for all control changes
- **`FileWatcher`** — pause/resume during write-back to avoid reload loops

### New Types

```swift
/// The top-level pure SwiftUI view for Liquid Glass rendering
struct LiquidGlassDocumentView: View {
    let structure: DocumentStructure
    let content: String
    // ... callbacks for interactive element changes
}

/// Renders a single Section as a glass block with its children
struct GlassSectionView: View {
    let section: Section
    let depth: Int  // 0 = root, caps visual effect at 4
    @State private var isCollapsed: Bool = false
}

/// Renders a block of markdown content (text, code, lists, etc.)
struct ContentBlockView: View {
    let markdownBlock: MarkdownBlock  // parsed block enum
}

/// Renders a single AIMD interactive element as a native control
struct NativeControlView: View {
    let element: InteractiveElement
    let onChange: (InteractiveElement, String) -> Void
}
```

### Integration Points

- **MarkdownView** dispatches to `LiquidGlassDocumentView` when rendering mode is Liquid Glass
- **SettingsRepository** gains a new `RenderingMode.liquidGlass` case
- **StoreService** gates Liquid Glass behind Pro
- **AppCoordinator** passes content + structure to the renderer

### API Endpoints

N/A — pure client-side rendering, no server interaction.

## User Experience

### User Flows

1. **First encounter:** User opens Settings > Rendering > sees "Liquid Glass" option marked as Pro. Taps it, gets purchase prompt. After purchase, mode activates.
2. **Normal use:** User opens a .md file. Document renders as nested glass blocks. Headings are tappable to collapse. Interactive elements are native controls.
3. **Interaction:** User checks a checkbox (Toggle). File writes immediately. FileWatcher pauses during write, resumes after.
4. **Search:** User presses Cmd+F, types query. Matches glow yellow within their glass blocks. Arrow keys jump between.
5. **Mode switch:** User goes to Settings, switches back to Enhanced. Document re-renders in the old NSTextView mode.

### Edge Cases

- **Empty document:** Root glass blob with no content
- **No headings:** Entire content renders on root blob (flat, no nesting)
- **Deeply nested (H5, H6):** Treated same as H4 visually (depth cap at 4)
- **Very large documents (1000+ lines):** LazyVStack ensures only visible blocks are rendered
- **Rapid control changes:** Debounce write-back if user toggles multiple checkboxes quickly
- **Missing interactive element data:** Graceful fallback — render raw markdown text for unrecognized elements

## Requirements

### Functional Requirements

- FR-1: Document renders as nested glass material blocks based on heading hierarchy
- FR-2: Glass material compounds visually, capped at depth 4
- FR-3: Sections collapse/expand on heading click, showing line count when collapsed
- FR-4: All AIMD interactive elements render as native macOS controls
- FR-5: Control changes write back to .md file immediately
- FR-6: SF Mono used for all text rendering
- FR-7: Code blocks render as glass cards with Copy button
- FR-8: Links are tappable, images render inline
- FR-9: Cmd+F search with yellow highlight and match navigation
- FR-10: Liquid Glass mode gated behind Pro purchase
- FR-11: LazyVStack used for document body

### Non-Functional Requirements

- NFR-1: Document with 500 lines renders initial content within 1 second
- NFR-2: Scrolling maintains 60fps (no dropped frames in normal use)
- NFR-3: Control interaction to file write-back completes within 200ms
- NFR-4: Memory usage stays under 100MB for documents up to 2000 lines

## Implementation Phases

### Phase 1: Glass Structure + Static Content

- [ ] Create `LiquidGlassDocumentView` that takes `DocumentStructure` and renders nested glass blocks
- [ ] Create `GlassSectionView` with material compounding (capped at depth 4)
- [ ] Implement collapse/expand on heading click with line count badge
- [ ] Render paragraphs, bold, italic, inline code, links, images
- [ ] Render code blocks as glass cards with Copy button
- [ ] Render blockquotes, horizontal rules, lists, tables
- [ ] Use LazyVStack for document body
- [ ] SF Mono typography throughout
- [ ] Wire into MarkdownView as alternative renderer based on mode setting
- **Verification:** `swift build` succeeds. Toggle to Liquid Glass mode, open a sample .md file, verify glass blocks render with correct nesting.

### Phase 2: Native Interactive Controls

- [ ] Create `NativeControlView` mapping each `InteractiveElement` to its native control
- [ ] Wire control changes through `InteractionHandler` for immediate file write-back
- [ ] Pause/resume `FileWatcher` during writes
- [ ] Handle all element types: checkbox, choice, fill-in (text/date/file/folder), feedback, status, confidence, suggestion, review
- **Verification:** `swift build` succeeds. Open AIMD test file with interactive elements, verify each renders as native control and changes persist to file.

### Phase 3: Search + Premium Gate + Polish

- [ ] Implement Cmd+F find bar with yellow highlight within glass blocks
- [ ] Match navigation (arrow keys, match count)
- [ ] Add `RenderingMode.liquidGlass` to settings with Pro gate
- [ ] Handle edge cases (empty doc, no headings, deep nesting, large files)
- [ ] Performance tuning (lazy loading, debounced writes)
- **Verification:** `swift build` succeeds. Cmd+F finds and highlights text. Non-Pro users see purchase prompt when selecting Liquid Glass.

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in user stories US-1 through US-6 pass
- [ ] All implementation phases verified
- [ ] Build succeeds: `swift build`
- [ ] Manual visual check: glass blocks nest correctly, controls work, search highlights

## Ralph Loop Command

```bash
/ralph-loop "Implement Liquid Glass rendering engine per spec at docs/specs/liquid-glass-rendering-engine--swiftui-blockcanvas-renderer-.md

PHASES:
1. Glass Structure + Static Content: Create LiquidGlassDocumentView, GlassSectionView with material compounding capped at depth 4, collapse/expand with line count badge, render all static markdown elements, code blocks as glass cards with copy button, LazyVStack, SF Mono, wire into MarkdownView - verify with swift build + visual check
2. Native Interactive Controls: Create NativeControlView mapping all InteractiveElement types to native macOS controls, wire through InteractionHandler for immediate file write-back with FileWatcher pause/resume - verify with swift build + interactive element test
3. Search + Premium Gate + Polish: Cmd+F find bar with yellow highlight in glass blocks, match navigation, RenderingMode.liquidGlass in settings with Pro gate, edge cases, performance tuning - verify with swift build + search test + premium gate test

VERIFICATION (run after each phase):
- swift build
- Manual visual verification of rendered output

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```

## Open Questions

- What animation (if any) should play when collapsing/expanding sections? (Spring? Fade? Respect reduceMotion?)
- Should the copy button on code blocks show a "Copied!" confirmation tooltip?
- Should the find bar float over glass or push content down?

## Implementation Notes

*To be filled during implementation*
