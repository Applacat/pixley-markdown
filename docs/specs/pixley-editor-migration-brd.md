# Pixley Editor Migration — BRD

**Version:** 1.0
**Date:** 2026-07-23
**Status:** BRD — input for Lisa spec interview
**Decision:** FINAL — Pixley becomes a markdown editor. This document scopes the migration; it does not relitigate the decision.

---

## 1. Thesis (revised)

Pixley is the native macOS surface where humans and AI collaborate through
markdown — a **full-duplex relay**. The AI writes documents; the human reads
them beautifully, responds through native controls (checkboxes, fill-ins,
status machines, reviews, comments), and now **edits the text itself**.
Editing doesn't dilute the relay — it completes it: a relay where the human
can only flip switches the AI pre-installed is half a conversation. The soul
is unchanged: Pixley is still just pipes. It exposes native controls and now
native text editing, drops no opinions into the file, and writes exactly what
the human meant back to disk. `.md` in, `.md` out, always.

## 2. Product Requirements

- **Edit-in-place, everywhere (end state).** Click into prose and type — no
  mode switch, no source/preview dichotomy. Bar: Notes/Craft, not VS Code.
  Plain mode remains the raw-text escape hatch.
- **Controls and text coexist.** Interactive elements stay controls while
  surrounding prose is editable. Click on a control = interaction; a
  deliberate affordance ("Edit source") exposes its syntax. Interaction vs
  editing must never be ambiguous on the same click.
- **Round-trip fidelity is sacred.** Open → edit one word → save produces a
  diff of exactly that word. No reflow, no marker normalization, no
  whitespace churn. AI agents diff these files; noisy writes poison the relay.
- **Never corrupt AI-authored structure.** Casual keystrokes cannot break a
  status machine, review block, or CriticMarkup span. Structured regions get
  soft protection with a deliberate unlock.
- **One write path.** Keystrokes, controls, and AI edits all flow through the
  same serialized funnel with FileWatcher self-write settlement. External/AI
  writes during a dirty edit surface as a conflict pill — never a silent
  clobber, in either direction.
- **Native macOS text behavior.** NSTextView-grade: dictation, Writing Tools,
  spellcheck, IME, standard shortcuts, document-wide undo spanning both
  edits and control interactions.

## 3. Non-Goals

- No vaults, workspaces, or proprietary libraries — folders on disk remain
  the unit of organization.
- No plugins, extension API, or theme marketplace.
- No wikilinks/backlinks/graph views (not Obsidian). No blocks database,
  publishing, or hosted sync (not Notion). iCloud folders are the user's
  business.
- No export pipeline beyond system print.
- No IDE-grade editing features in v1 (find/replace across files,
  autocomplete, vim bindings) — parking lot, explicit not-doing list.

## 4. Target Architecture (direction, for the spec to detail)

**Core inversion:** today content flows *click → patch → disk → reload*; the
target is *keystroke → model → (debounced) disk*. Disk stops being the
source of truth while a document is open.

- **`MarkdownDocument`** — single in-memory source of truth per open file:
  canonical source string, dirty flag, revision counter, undo manager,
  on-disk baseline (content + mtime hash) for conflict detection. All
  mutations — keystrokes, controls, AI chat — are range edits on the model.
- **`SaveCoordinator`** — absorbs InteractionHandler's serialized per-URL
  write chain as a debounced, coalescing, atomic save queue. FileWatcher
  self-write settlement carries over unchanged.
- **`ExternalChangeArbiter`** — FileWatcher consumer. External change +
  clean doc → silent reload; + dirty doc → conflict UI. `ElementRelocator`
  demotes from every-edit targeting to external-change re-anchoring.
- **Detector re-target** — `InteractiveElementDetector` reads the model, not
  disk. Control actions shrink to thin model range edits; relocation is
  unnecessary when you edit the string you rendered from.

## 5. Migration Phases (each independently shippable)

- **Phase 0 — Document model under the existing app.** No UI change; reroute
  InteractionHandler + ChatTools through `MarkdownDocument`. *The risky
  refactor: budget 30–40% of total effort.* Gate: current behavior fully
  regression-tested (corruption-class suite green).
- **Phase 1 — Plain mode becomes editable.** Precondition: delete Plain
  mode's display mutations (#91 dies by construction — rendered string ==
  model string). `isEditable = true`; rewrite (not patch) the broken
  debounced re-highlight; NSUndoManager bridged to the model; autosave
  default (1–2 s debounce) with ⌘S still honored. Ship behind an opt-in
  "Editing (beta)" toggle.
- **Phase 2 — Conflict handling + AI coexistence.** Conflict pill UX;
  AI edits validate against the model revision counter (apply-if-current,
  else re-anchor or re-ask).
- **Phase 3 — Enhanced per-block editing.** Click a block → inline editor →
  commit on blur re-renders. Builds directly on the just-shipped stable
  block ids + scroll restore.
- **Phase 4 (optional, post-data) — Enhanced full WYSIWYG.** Treated as a
  separate product decision after Phases 0–3 ship and usage data exists.

## 6. Monetization

**Editing is free.** "Free native markdown editor" is the acquisition
funnel; a $9.99 editor loses to free Typora-class tools. Relay Pro remains
the collaboration layer (fill-ins, status machines, reviews, CriticMarkup,
AI field editing) plus one addition: **CriticMarkup authoring** (human
suggest-mode) joins Pro. Pro's pitch: *"Editing is free. Collaborating with
your AI is Pro."*

## 7. Positioning / App Store

- Claim **"AI-native markdown editor"** — category of one. Not "markdown
  editor with AI" (their terms) and no longer "reader".
- Title stays **Pixley Markdown**; subtitle → "The markdown editor built
  for AI workflows" (candidate).
- Keywords add `markdown editor`, `md editor`, `text editor`, `writing`
  (order-of-magnitude more volume than "reader" terms — the largest ASO win
  of the migration). Screenshots lead with edit-in-place beside live
  controls — the shot no competitor can take.
- **DECIDED (Jose, 2026-07-23): repositioning waits for the product.** No
  ASO/copy changes until editing has shipped and stabilized — editing lands
  first as a beta-labeled feature under the current reader-first copy. The
  "editor" claim, subtitle, and keyword switch happen only once Phase 1+2
  are shipped and holding up in reviews.

## 8. Risk Register (abridged — top items)

| Risk | L/I | Mitigation |
|------|-----|------------|
| User text loss during editing | M/H | Everything through the funnel; pre-edit snapshot/versioning before first ship; loss = launch blocker at any severity |
| Three-writer conflicts (undo vs watcher vs AI) | H/H | Single document-authority model owns all mutations; undo registered against the model, not the text view |
| #91 display mutations write garbage back | H/H | Editor edits source only; display mutations deleted before typing is enabled anywhere |
| Re-fighting NSTextView (the old Enhanced mode's death) | H/M | Text-surface architecture decided by a time-boxed spike with exit criteria before UI work |
| Regressing just-shipped v3.x stability | H/H | July-2026 corruption regression suite gates every editor merge |
| Scope creep vs solo capacity | H/M | Written v1 scope + not-doing list; new asks → v2 parking lot |
| Migration stalls half-done | M/H | Every phase independently shippable; reader-only build releasable from main at all times |

**Guardrails (non-negotiable):** (1) never ship a build that can lose a
keystroke; (2) reader stays rock-solid at every phase — existing smoke tests
pass unchanged; (3) one write path, ever; (4) edit the source, render the
display; (5) corruption-class tests gate every merge.

**Kill criteria:** production data-loss bug or corruption recurrence ×2 in
beta → pause and harden. Text-surface spike exceeds 4 weeks without a
type-save-reload loop surviving watcher + undo → wrong architecture, stop
and rechoose. Reader regressions outpace fixes for two releases (or rating
drops below pre-migration) → freeze editor work.

## 9. Backlog Impact

- **Dies by construction:** #91 (display-vs-source drift).
- **Demoted/reshaped:** ElementRelocator hot path, InteractionHandler
  read-relocate-write bodies (~500 lines → thin model edits).
- **Unchanged and load-bearing:** FileWatcher settlement (#78/#79), stable
  block ids + scroll restore (#81/#84), detector fixes (#86–#89, #87, #75),
  rendering correctness (#82, #83, #94, #103–#106), spec-4 commit semantics
  (#85 — policy defined here: debounced/explicit, never per-change).

## 10. Open Questions for the Lisa Interview

1. **Interaction disambiguation:** exact click/keyboard model when a block is
   both interactive and editable — single click, double click, caret-adjacent
   typing on a checkbox line.
2. **Save model:** autosave-always (Notes) vs dirty-dot + ⌘S (BBEdit) vs
   NSDocument autosave-in-place with versions — determines whether we adopt
   NSDocument machinery or stay custom.
3. **Conflict UX:** what the user sees when an external/AI write lands on a
   dirty document (modal choice / last-writer-wins with undo / inline merge),
   and whether AI edits are blocked or queued while the user is mid-keystroke.
4. **Structure protection:** which regions are soft-locked and what the
   deliberate unlock gesture is.
5. **Enhanced-mode ambition:** is per-block editing (Phase 3) an acceptable
   editor end state for launch, or is full WYSIWYG required? (Swings the
   roadmap by months.)
6. **Undo scope:** does undo survive external reloads and AI edits (shared
   stack?), and app relaunch?
7. **Text-surface spike:** TextKit 2 vs SwiftUI TextEditor vs block-local
   fields — spike exit criteria and time box (guardrail: 4 weeks).

*(Resolved pre-interview: repositioning staging — decided 2026-07-23,
editing ships beta-labeled under reader-first copy; ASO switch only after
Phase 1+2 ship and hold. See §7.)*

## 11. Success Metrics

- Zero data-loss reports across beta and first release.
- Round-trip fidelity: automated test corpus diffs are keystroke-exact.
- Downloads inflection after "editor" ASO switch (baseline: current weekly).
- Reader smoke-test pass rate unchanged at every phase gate.
