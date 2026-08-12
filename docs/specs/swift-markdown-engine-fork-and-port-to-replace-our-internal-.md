# Gate G4 (revised): swift-markdown-engine Fork & Port

**Version:** 1.0 — 2026-08-12
**Status:** Ready for implementation
**Supersedes:** `docs/specs/editor-epic.md` § "Gate G4 — Enhanced WYSIWYG Surface"
(and the G0 spike's from-scratch architecture GO, which this replaces).
G5 (insert palette) and G6 (done bar / soak) are unchanged and build on top.
**Epic:** #107 · Milestone "v5: The Editor"

---

## 1. Summary

Fork [nodes-app/swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)
(Apache 2.0) and make it Pixley's single editor substrate for **both** view
modes: its TextKit 2 live-styling editor replaces the Enhanced/native
renderer, and its `rawSourceMode` replaces the Plain-mode
`MarkdownEditor`/`MarkdownHighlighter`. Pixley's interactive-element layer
(the product) is built on top of it. The G1–G3 model stack —
`MarkdownDocument`, `SaveCoordinator`, `ExternalChangeArbiter`,
`InteractiveElementDetector` — is untouched and plugs into the engine's
`$text` binding.

### Why (evaluation findings, 2026-08-12)
- **Storage string == markdown source; markers shrink, never removed.**
  Byte-fidelity and the #91 safety property hold *by construction*
  (guardrail 4). Stronger than the G0 spike's remove-and-reconstruct plan.
- **One write path:** engine-internal mutations (checkbox toggle) route
  through `shouldChangeText`/`didChangeText` → the same `$text` binding as
  typing → our model funnel (guardrail 3).
- `rawSourceMode` is our Plain mode, runtime-switchable, undo-dropped on
  flip (mirrors D8's conservatism).
- Caret-aware marker reveal (D3, Typora-style via `hiddenMarkerFontSize`),
  incremental O(edit) restyle, Writing Tools, 323 green tests, shipping
  inside Nodes.app, active upstream (daily commits).
- Gaps to close in the fork: only checkboxes/wiki-links are clickable;
  `[[…]]` collides with our fill-in syntax; no gutter/bookmark/comment UI.

## 2. Binding Decisions

| # | Decision |
|---|----------|
| D-A | Engine replaces **both view surfaces**. `InteractiveElementDetector` stays the write-side truth (AI edits, relocation, corpus). G1–G3 model stack unchanged. |
| D-B | Fork to **Applacat/swift-markdown-engine**, vendored into this repo as a local path package (git submodule or subtree). Upstream releases rebase in; our patches live as small thematic commits. |
| D-C | This port **is** Gate G4. Original G4 section + G0 architecture GO superseded. |
| D-D | Gutter feature parity (line numbers, bookmarks, comment indicators + Add Comment popover, reading progress) is **in scope**, delivered in P4 before the gate closes. |
| D-E | `[[…]]` collision: **repurpose the wiki-link machinery into the fill-in element** — its caret-aware active state, click callback, and two-form storage/display transform become fill-in UX. Wiki-linking is not a Pixley feature. |
| D-F | Interactive mechanism = **generalized hit-test pattern** (the engine's checkbox approach extended): elements stay styled *text*; clicks hit-test attribute ranges → popover/menu → rewrite through the standard funnel. **No NSTextAttachments.** |
| D-G | Gate MVP = **core four interactive** (checkbox, fill-in, choice, status). Review/feedback/CriticMarkup render styled-but-inert until G5. |
| D-H | Code highlighting via an **internal `SyntaxHighlighter` adapter** — zero new dependencies. `MarkdownEngineCodeBlocks`/`MarkdownEngineLatex` products are NOT linked. |
| D-I | **Kill box:** P1 must pass corpus byte-fidelity + harness + perf. A fundamental failure needing >1 week of fork surgery → abandon the port, revert to the original from-scratch G4 plan. Old editors stay in-tree until P2 completes. |
| D-J | **4 phases, one ralph loop each** (below), each with a verifiable exit. |
| D-K | Upstream policy: keep fork commits rebase-able; PR genuinely generic pieces upstream (`wikiLinksEnabled` flag, extension click seam). Pixley element code never goes upstream. |
| D-L | Cleanup is a **full sweep in P2**: delete `MarkdownEditor`, `MarkdownEditorCoordinator`, `MarkdownHighlighter`, `Views/NativeRenderer/`, `MarkdownBlockParser`; retire the swift-markdown dependency. `aimdRenderer` keeps detector / relocator / document / merge / arbiter only. |

## 3. Hard Requirements (carried from G0–G3 — not negotiable)

1. **Guardrails 1–5** (`cal/cal.md`): never lose a keystroke; reader
   rock-solid every phase; one write path; edit the source, render the
   display; corruption-class + round-trip corpus suites gate every merge.
2. **D8 undo:** external/AI merges clear the typed undo stack — post-merge
   ⌘Z is a no-op. The engine keeps per-`documentId` undo stacks; the fork
   needs an explicit clear hook (or a deliberate `documentId` strategy).
   The harness external-write undo check must stay green.
3. **Regression floor at every phase exit:** app suite green, package suite
   green, STRESS-PLAIN harness green (500 keystrokes / 0 dropped /
   0 selection errors, autosave, undo, D8, G3 merge + clash-hold
   scenarios), fork's upstream test suite green.
4. **Perf budgets (from G0):** caret reveal/unreveal ≤ 16 ms frame budget
   (spike measured p95 0.30 ms — the engine must stay in that class);
   per-keystroke restyle p95 ≤ 16 ms on a 5,000-line document.
5. **G3 conflict engine works on the new surface:** silent reload, auto-merge,
   clash pill with save-hold — all verified against the engine editor.
6. **Never touch Release ARCHS** (arm64 + x86_64). Fork package must build
   universal for Release.

## 4. Architecture

```
┌─ Vendor fork: Packages/swift-markdown-engine (Applacat fork, Apache 2.0)
│    NativeTextViewWrapper ($text binding, rawSourceMode flag)
│    + fork patches: wikiLink→fill-in rewire, element hit-test seam,
│      undo-clear hook, gutter ruler hooks
│
├─ Pixley app
│    MarkdownView ──> EngineEditorView (both modes; mode = engine config)
│    handleTextEdited(new, previous)  ──> MarkdownDocument (unchanged G2/G3)
│    ExternalChangeArbiter / ClashPill / SaveCoordinator  (unchanged)
│    InteractionHandler + InteractiveElementDetector      (unchanged;
│      element clicks from the engine's hit-test seam land here)
│    Internal SyntaxHighlighter adapter (D-H)
│
└─ aimdRenderer (slimmed in P2): detector, relocator, MarkdownDocument,
     ThreeWayMerge, ExternalChangeArbiter, corpus tests
```

Element rendering: detector ranges → custom attributes on the engine's
styled text (via the fork's element seam); clicks hit-test those attribute
ranges (checkbox-pattern) and route through today's `InteractionHandler`
methods, so file bytes are identical to the current write paths.

## 5. Phases & User Stories

### P1 — Fork & Bind (kill box)
- **US-P1.1** Fork exists at Applacat/swift-markdown-engine, vendored as a
  local path package; Pixley workspace builds with it; upstream's 323 tests
  pass inside the fork.
  *AC:* `swift test` in the vendored fork: 0 failures. App builds Debug+Release.
- **US-P1.2** An engine-hosted editor (behind a debug flag / hidden window,
  not user-facing) binds `$text` ↔ `MarkdownDocument` through
  `handleTextEdited(new:previous:)` semantics.
  *AC:* automated round-trip test — every corpus document loaded into engine
  storage and read back is **byte-identical**; typing/checkbox edits produce
  exactly the expected diffs (extend `RoundTripCorpusTests` pattern against
  the engine).
- **US-P1.3** STRESS-PLAIN harness re-targeted to the engine in
  `rawSourceMode`: 500 keystrokes / 0 dropped / 0 selection errors,
  autosave-on-disk, undo, D8 external-write clear (fork hook), G3 merge +
  clash-hold scenarios.
  *AC:* `--stress-plain` PASS; keystroke restyle p95 ≤ 16 ms on 5,000-line doc
  (measured, printed in harness report).
- **EXIT / KILL:** all three green → GO. Fundamental failure estimated
  >1 week of fork surgery → output NO-GO in the progress file and stop
  (revert plan: original G4 spec).

### P2 — Surface Swap (full sweep)
- **US-P2.1** Plain mode = engine `rawSourceMode`; Enhanced mode = engine
  live styling. `ViewModePicker` flips engine configuration at runtime.
  *AC:* mode flip preserves content byte-exactly and drops undo (engine
  contract); file switching, scroll restore, reading progress work.
- **US-P2.2** Delete `MarkdownEditor.swift`, `MarkdownEditorCoordinator.swift`,
  `MarkdownHighlighter.swift`, `Views/NativeRenderer/` (all files),
  `MarkdownBlockParser`; retire the swift-markdown dependency from
  `Packages/aimdRenderer/Package.swift`.
  *AC:* grep gate — no references to deleted types; package builds dep-free;
  both suites green (delete obsolete tests, keep count documented).
- **US-P2.3** G3 conflict UX verified on the engine surface: silent reload,
  auto-merge during typing, clash pill keep-mine/take-theirs with save-hold.
  *AC:* harness G3 scenarios green against the live engine editor; manual
  smoke: AI chat edit while typing lands without a reload pill.
- Known temporary regression (accepted per D2, restored in P4): gutter,
  bookmarks, comment indicators, Add Comment.

### P3 — Interactive Core Four
- **US-P3.1** Fork gains a generic element seam: Pixley supplies attribute
  ranges + click handler; engine does hit-testing, hover cursor, and
  invalidation (generalization of `NativeTextView+TaskCheckbox`). Candidate
  upstream PR (D-K).
  *AC:* seam is data-driven (no Pixley types inside the fork); fork tests
  cover hit-test geometry.
- **US-P3.2** Core four interactive on the engine, writes anchored by the
  detector and routed through `InteractionHandler`:
  checkbox (engine-native toggle — verify byte diff), fill-in (repurposed
  wiki-link machinery per D-E: click → edit popover; typed-prefix values
  `[[text: …]]`/`[[date: …]]` display cleanly), choice (click option →
  selection written), status (click → next-state menu → written with
  `**Status:**` prefix preserved).
  *AC:* corpus assertions — each interaction produces the same bytes as
  today's write paths (1-char diff for checkbox, grammar-conformant writes
  for fill-in/choice/status); detector re-detects every element after each
  write; app + package suites green.
- **US-P3.3** AI edits land and render live: ChatTools → InteractionHandler
  path unchanged; engine restyles the merged/AI-written region without a
  reload.
  *AC:* harness scenario — AI-style external write to a checkbox while the
  engine editor is open updates the rendered control in place.
- **US-P3.4** Review / feedback / CriticMarkup / comments render
  styled-but-inert (extensions: `{==…==}`, `{>>…<<}`, `{++…++}` etc. as
  `InlineSyntax`; interactivity explicitly deferred to G5).
  *AC:* corpus docs with CriticMarkup style correctly; no dead interactive
  affordances (no hover cursor on inert elements).

### P4 — Gutter Parity & Polish
- **US-P4.1** Line-number gutter on the engine text view (both modes),
  vertically aligned with wrapped lines.
- **US-P4.2** Bookmarks (stars, toggle), comment indicators, Add Comment
  popover (selection + gutter), reading-progress badge, ⌘G go-to-line,
  scroll restoration per document.
  *AC:* the 5-check manual QA list (`docs/specs/ralph-renderer-identity-manual-test.md`)
  re-run against the engine, plus: add bookmark → indicator on correct line
  after edits above it; add comment → `<!-- feedback -->` written, indicator
  appears; progress badge tracks scroll.
- **US-P4.3** Internal `SyntaxHighlighter` adapter (D-H) styles fenced code
  (reuse the fence-highlighting rules deleted with MarkdownHighlighter).
  *AC:* code fence in corpus doc renders with keyword coloring; no new deps.
- **US-P4.4** Gate close-out: progress file updated, epic #107 comment,
  issues folded into this gate closed (#81, #82, #83, #84, #92, #93, #94,
  #104, #105 — each verified or re-scoped with a comment), G5 unblocked.
  *AC:* manual QA pass recorded; both suites + harness + fork suite green;
  `cal/NOW.md` updated.

## 6. Verification Commands (every phase, every iteration)

```bash
xcodegen generate                          # only after project.yml changes
xcodebuild test -project AIMDReader.xcodeproj -scheme AIMDReader -configuration Debug
cd Packages/aimdRenderer && swift test     # slims to ~detector/model/merge suites in P2
cd <vendored fork> && swift test           # upstream 323 + our seam tests
"$APP/Contents/MacOS/Pixley Markdown" --stress-plain   # exit 0 + STRESS-PLAIN PASS
```

Success = all green. The harness prints perf numbers; p95 restyle ≤ 16 ms is
part of PASS from P1 on.

## 7. Ralph Execution Plan

One loop per phase, spec-file pattern:

```
/ralph-loop "Read docs/specs/swift-markdown-engine-fork-and-port-to-replace-our-internal-.md in ./pixley-markdown and execute Phase P<N> only. Track state in docs/specs/swift-markdown-engine-fork-and-port-to-replace-our-internal--progress.txt." --completion-promise "G4 PHASE P<N> COMPLETE" --max-iterations 25
```

Phase exits are the ACs above. P1's loop may alternatively end with a
truthful `NO-GO` recorded in the progress file (kill box, D-I) — in that
case do NOT output the completion promise; report to the user instead.

## 8. Out of Scope (Ralph: ignore even if adjacent)

- G5 material: insert palette, review/feedback/CriticMarkup interactivity,
  new element types (#103, #85 UI, #106 UI half).
- G6 material: soak, dogfood checklist, App Store prep, version bump.
- LaTeX rendering, image embeds, wiki-linking as a user feature, tables
  editing UX beyond what the engine ships.
- iOS/visionOS, .pixley bundle format.
- Any change to detector grammar, write-back formats, or the G1–G3 model
  stack beyond wiring.
