# Ralph Mission: Renderer Identity + Scroll Restoration

**Issues:** #81 (sequential block index as ForEach identity), #84 (Enhanced mode has no scroll restoration)
**Progress file:** `docs/specs/ralph-renderer-identity-progress.txt` — read it FIRST every
iteration; create it on iteration 1 with a task checklist derived from
`gh issue view 81` and `gh issue view 84`. Update it before you stop. It is
your memory between iterations.

## Mission

Enhanced mode (Sources/Views/NativeRenderer/) identifies blocks by sequential
parse index (`MarkdownBlock.id = blocks.count`), so any insertion/removal
shifts every downstream block's identity: SwiftUI destroys or transplants
control state (drafts vanish, values appear in the wrong control), and scroll
anchors point at the wrong block. Separately, Enhanced mode never restores
scroll position — every reparse, reload, and file switch re-estimates the
LazyVStack from scratch. Fix both.

## Requirements

1. **Stable block identity (#81):** derive `MarkdownBlock.id` from content-
   stable facts (kind + source position/signature, or persistent ids carried
   across reparses via diffing) so an insertion above a block does not change
   the identity of blocks below it. `ListItemBlock.id = UUID()` per parse is
   also churn — fix it the same way.
2. **State refresh:** controls in NativeControlView that seed `@State` from
   their element only in `init` (FillInTextField, FeedbackTextEditor,
   ReviewControlView, SliderControl) must refresh when the element's value
   changes for the SAME identity (onChange on the element value), so external
   /AI edits show through.
3. **Scroll restoration (#84):** save a block-anchored position (topmost
   visible block's stable id + offset, or document progress) via the existing
   `coordinator.saveScrollPosition` path, and restore it in NativeDocumentView
   after file open, external reload, and interactive-write reparse. Plain mode
   already does this via `restoreScrollPosition` — mirror the contract.
4. **Tests:** parser identity tests in `Packages/aimdRenderer/Tests/aimdRendererTests/`
   (insert a block mid-document → all downstream block ids unchanged; same doc
   parsed twice → identical ids). App-side mirror tests for the scroll-anchor
   save/restore math if it has pure logic worth pinning.

## Guardrails

- NEVER change Release ARCHS (arm64+x86_64, App Store requirement); Debug
  stays arm64-only via project.yml (already encoded there).
- Do NOT touch InteractionHandler's serialized funnel or ElementRelocator
  (write-back integrity work, shipped in f4eab3a) except to consume their
  APIs.
- Do NOT weaken FileWatcher's selfWriteCompleted/selfWriteFailed settlement.
- Build + test every iteration:
  `xcodegen generate` (only if project.yml changed), then
  `xcodebuild test -project AIMDReader.xcodeproj -scheme AIMDReader -configuration Debug`
  and `swift test` in Packages/aimdRenderer (my new tests must pass; the 12
  pre-existing failures tracked in #102 are not yours to fix).
- Commit each working increment referencing its issue.

## Exit criteria (ALL must hold)

(a) grep confirms no `id: blocks.count`-style sequential identity remains in
    MarkdownBlock parsing and no `UUID()` per-parse ids;
(b) full app suite passes with 0 failures, new parser identity tests pass;
(c) progress file shows every task DONE;
(d) a manual-verification test document exists at
    `docs/specs/ralph-renderer-identity-manual-test.md` with steps: type into
    a fill-in, add a gutter comment above it, confirm the draft stays in the
    same control and the view does not jump; switch files and back, confirm
    scroll position restores.

Then: comment progress on #81 and #84 with the commit ref (do NOT close them —
they close after the human runs the manual test), and output the completion
promise EXACTLY: RENDERER IDENTITY COMPLETE
