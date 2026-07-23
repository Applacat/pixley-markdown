# Editor Epic — Specification

**Version:** 1.0
**Date:** 2026-07-23
**Status:** Spec (finalized from Lisa interview)
**Epic:** #107 · **Milestone:** v5: The Editor
**Parent BRD:** `docs/specs/pixley-editor-migration-brd.md` (binding except where overridden below)

---

## Overview

Pixley Markdown migrates from read-only relay to a full markdown editor.
Enhanced mode becomes a continuous Typora-style WYSIWYG surface where
interactive elements behave as atomic objects; Plain mode becomes the
editable raw-source escape hatch. Everything lands as **one release (v5)** —
no public betas, no intermediate App Store versions.

## Binding Decisions (interview, 2026-07-23)

| # | Decision |
|---|----------|
| D1 | **Full WYSIWYG or bust** — launch = continuous Enhanced editing; per-block-only is not an acceptable end state |
| D2 | **Nothing ships until complete** — no App Store release between v3.x and v5; phases are internal gates only (overrides BRD "independently shippable"); reader-only main stays releasable for emergencies |
| D3 | **Typora-style reveal** for text markdown — styled render; syntax markers appear around the caret's current element, melt on leave |
| D4 | **Interactive elements are objects (OOD)** — PowerPoint-style: click inside to edit parts (structured, never raw syntax), select the object to move/delete/copy; atomic to the caret; created via an Insert palette. File stays plain markdown — objects are a UI concept ("just pipes" preserved). Resolves structure protection |
| D5 | **Plain mode = editable raw-source escape hatch** (Typora source-mode analog); element syntax edited there, never inline in Enhanced |
| D6 | **Debounced autosave** (~1–2 s after typing pauses); ⌘S forces immediate; save timing == when the AI sees edits |
| D7 | **Auto-merge, pill on clash** — non-overlapping external/AI changes 3-way-merge silently into the model; same-region clashes raise keep-mine/take-theirs |
| D8 | **Undo = my actions only** — keystrokes + control interactions; never AI merges; session-scoped |
| D9 | **TextKit 2 + attachment view providers spiked first** — 4-week kill box (BRD guardrail); block-stack is the fallback |
| D10 | **Insert palette v1 = core four** — checkbox, fill-in, date, status machine; other elements stay AI-authored |
| D11 | **Ralph 3 folded into the rebuild** — view-layer rendering bugs (#82, #83, #94, #103–#105) become requirements/tests of the new surface, not fixes to the old one. Detector-level bugs (#86–#89, #75/#87, #106 type-preservation) survive any surface and are fixed in G1 |
| D12 | **Done bar** — all gates green + dogfood checklist passes in both modes + automated round-trip corpus keystroke-exact + 2 weeks daily personal use with zero data-loss incidents |

## Scope

### In Scope
- `MarkdownDocument` in-memory model (single source of truth), `SaveCoordinator` (debounced atomic saves), `ExternalChangeArbiter` (3-way merge + clash pill)
- Editable Plain mode (raw source, syntax highlighting preserved, display mutations deleted)
- Enhanced WYSIWYG surface on TextKit 2 (pending spike): Typora reveal for text, elements as atomic object attachments with part-editing
- Insert palette (core four) + object selection/move/delete/copy
- Undo (mine-only, session-scoped) spanning keystrokes and control interactions
- Detector-level bug fixes that survive the surface (#86–#89, #75, #87, #106)
- Round-trip fidelity corpus + corruption-class regression gates

### Out of Scope (v5)
- Everything in BRD §3 non-goals (no vaults, plugins, wikilinks, sync, export)
- Insertion authoring for reviews, choices, CriticMarkup, sliders/steppers/toggles/color (AI-authored only in v5)
- Undo across relaunch; unified human+AI undo timeline
- Find/replace across files, autocomplete, vim bindings
- iOS branch (multiplatform/ios) — untouched
- ASO/App Store copy changes (decided: build first, reposition after v5 ships and holds)

## Architecture (target)

Per BRD §4: keystroke → `MarkdownDocument` → debounced disk. Components:
- **MarkdownDocument** (`@MainActor @Observable`): canonical string, revision counter, undo manager, on-disk baseline (content + hash) for merge
- **SaveCoordinator**: absorbs the serialized per-URL funnel; coalesced atomic writes; FileWatcher `selfWriteCompleted`/`selfWriteFailed` unchanged
- **ExternalChangeArbiter**: clean doc → silent reload; dirty doc → 3-way merge against baseline; clash → pill. `ElementRelocator` demotes to merge re-anchoring
- **Detector** reads the model; `InteractionHandler` methods become thin model range-edits
- **Enhanced surface**: single TextKit 2 NSTextView; text styled via attributes with caret-proximity syntax reveal; interactive elements as `NSTextAttachment` + view provider hosting the existing SwiftUI controls (NativeControlView is reused; NativeDocumentView's LazyVStack shell retires)

## User Stories

### Gate G0 — Spike (kill box: 4 weeks)
- **US-0.1** TextKit 2 proof: one NSTextView renders a doc with styled markdown text + one embedded checkbox attachment (SwiftUI view). Type around it, save, reload, undo — loop survives FileWatcher.
  *AC:* type-save-reload-undo demo runs 100× scripted without corruption; checkbox toggles and writes through the model; caret traverses the attachment as one unit.
- **US-0.2** Typora reveal proof: `**bold**` markers appear when caret enters the span, melt when it leaves, with no reflow-jitter beyond the markers themselves.
  *AC:* screen-recorded demo; attribute updates ≤ 16 ms for a 5k-line doc (measure with signposts).
- **Kill criterion:** exit tests not green in 4 weeks → stop, re-choose block-stack (BRD guardrail).

### Gate G1 — Document Model (the risky refactor; no UI change)
- **US-1.1** `MarkdownDocument` + `SaveCoordinator` exist; `InteractionHandler`'s 15 write methods become model range-edits; ChatTools mutates the model.
  *AC:* zero behavior change — full app suite (320+) green unmodified; grep: no `Data(contentsOf:)` reads in interaction paths; corruption-class suite green.
- **US-1.2** Detector reads the model; relocation off the hot path.
  *AC:* interaction latency test: checkbox toggle completes without disk read (verified by instrumentation/log assertion).
- **US-1.3** Detector-level fixes: #86 same-line choices, #87 multi-word states, #88/#106 explicit filled-value syntax (`[[date: …]]` pattern), #89 sanitization unified, #75 closed by #87.
  *AC:* per-issue regression tests in aimdRendererTests; issues closed with commit refs.
- **US-1.4** Package hygiene: #102 — package suite green and wired into the loop.
  *AC:* `swift test` 0 failures; test command documented in CLAUDE.md.

### Gate G2 — Plain Mode Editable
- **US-2.1** Display mutations deleted (#91 dies); rendered string == model string.
  *AC:* NSTextView string equals model string byte-for-byte in tests; #91 closed as obsolete.
- **US-2.2** `isEditable = true`; typing flows through the model; debounced re-highlight rewritten to preserve selection and never fight the typist.
  *AC:* scripted typing test (500 chars with markdown syntax) — highlight correct, selection stable, no dropped keystrokes.
- **US-2.3** Autosave (1–2 s debounce) + ⌘S; undo-mine-only via NSUndoManager bridged to the model.
  *AC:* type → wait 2 s → file on disk matches; ⌘Z reverts typing but never an AI merge (test with simulated external write).
- **US-2.4** Round-trip corpus: open → single-word edit → save produces exactly that diff for a corpus of gnarly docs (tables, CriticMarkup, all element types, emoji, CRLF).
  *AC:* corpus test target green; corpus documented and extensible.

### Gate G3 — Conflict Engine
- **US-3.1** 3-way merge on `MarkdownDocument` (baseline vs mine vs theirs).
  *AC:* merge test matrix — disjoint edits both survive; adjacent-line edits both survive; same-region clash detected, never silently resolved.
- **US-3.2** Clash pill UX (keep mine / take theirs); AI edits validate against revision counter (apply-if-current, else merge path).
  *AC:* simulated AI-write-during-typing scenarios: no data loss on either side in 100-iteration fuzz.

### Gate G4 — Enhanced WYSIWYG Surface
- **US-4.1** TextKit 2 surface replaces NativeDocumentView as Enhanced's renderer: styled text, Typora reveal, gutter (line numbers, bookmarks, comments) preserved.
  *AC:* rendering parity checklist vs current Enhanced for text markdown; #104 alignment correct by construction; scroll restore (#84 behavior) preserved.
- **US-4.2** Elements render as atomic object attachments reusing NativeControlView controls; caret treats each as one unit; no line-text swallowing.
  *AC:* `Enable logging: [[toggle]]` renders label + control on one line (#82 test); elements inside collapsibles work (#83 test); status renders once (#105 test).
- **US-4.3** Object selection model: click inside → part-editing (existing control interactions); click border/⌘-click → object selected (move via drag or cut/paste, delete, copy); Plain mode remains syntax access (D5).
  *AC:* each verb has a UI test or scripted xcui check; deleting an object produces a clean markdown diff (element lines only).
- **US-4.4** Editing text around/adjacent to objects never corrupts element syntax.
  *AC:* fuzz: random keystrokes at element boundaries × 1000 — detector still finds every element; round-trip corpus stays green.

### Gate G5 — Insert Palette + Polish
- **US-5.1** Insert palette (toolbar + menu + ⌘-shortcut) authoring the core four: checkbox, fill-in, date, status machine (with state-list mini-editor).
  *AC:* each inserted element round-trips: insert → appears as object → detector recognizes it → AI tool can edit it.
- **US-5.2** QA-batch behaviors on the new surface: #103 comment popover works; #85/#106 commit-on-close semantics for spec-4/date controls.
  *AC:* per-issue tests; issues closed.
- **US-5.3** Welcome docs + smoke-test checklist rewritten for the editor era.
  *AC:* docs/smoke-test-v5.md exists and passes.

### Gate G6 — Done Bar (D12)
- Full dogfood checklist green in both modes; round-trip corpus green in CI loop; **2 weeks daily personal use, zero data-loss incidents** (log kept in docs/specs/editor-epic-soak-log.md); reader smoke tests unchanged-green.

## Non-Functional Requirements
- NFR-1: Typing latency — keystroke-to-glyph < 16 ms on a 5k-line document (signpost-measured)
- NFR-2: Round-trip fidelity — corpus diffs keystroke-exact, zero normalization
- NFR-3: Zero data loss — guardrail #1; any loss bug is a stop-ship at any severity
- NFR-4: Reader regression — existing smoke checklist passes at every gate
- NFR-5: One write path — no file writes outside SaveCoordinator (grep-gated)

## Verification (every gate)
```
xcodegen generate   # only if project.yml changed
xcodebuild test -project AIMDReader.xcodeproj -scheme AIMDReader -configuration Debug
cd Packages/aimdRenderer && swift test
```
Plus per-gate ACs above. Corruption-class + round-trip corpus suites are merge gates from G1 onward (BRD guardrail 5).

## Ralph Loop Command

One mission per gate; spec-file pattern (short prompt, instructions live here):

```bash
/ralph-loop "Read docs/specs/editor-epic.md in ./pixley-markdown and execute Gate G<N> only. Track state in docs/specs/editor-epic-progress.txt." --completion-promise "GATE G<N> COMPLETE" --max-iterations 25
```

Escape hatch: 20 iterations without a green AC → document blockage under
Implementation Notes in this file, list attempted approaches, stop for human
guidance. G0 additionally obeys the 4-week kill criterion.

## Open Questions (deferred, non-blocking)
- Object drag-reorder UX details (v5 may ship cut/paste-only movement)
- Status-machine mini-editor design (states list authoring)
- Whether Versions/NSDocument adoption is revisited post-v5

## Implementation Notes
(accumulates during execution)
