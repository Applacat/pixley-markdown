# NOW — Current Focus

Work is tracked in GitHub Issues: `gh issue list --state open`

## Active: Editor Epic (#107, milestone "v5: The Editor")
Spec: `docs/specs/editor-epic.md` · Progress: `docs/specs/editor-epic-progress.txt`

- [x] G0 — TextKit 2 spike (exit tests green; GO recorded via G1 launch)
- [x] G1 — Document model + detector fixes (COMPLETE 2026-07-23: closed
      #86, #87, #75, #88, #89, #102; #106 data half; MarkdownDocument +
      SaveCoordinator shipped, interaction path off disk)
- [x] G2 — Plain mode editable (COMPLETE 2026-07-23, 3 iterations: #91
      closed as obsolete; display mutations deleted, editable + attribute-
      only re-highlight, model-routed typing, debounced autosave + ⌘S,
      undo-mine-only D8, round-trip corpus gate; --stress-plain harness:
      500 keystrokes, 0 dropped, 0 selection errors)
- [ ] G3 — Conflict engine
- [ ] G4 — REVISED (2026-08-12): swift-markdown-engine fork & port replaces
      the from-scratch build. Spec: docs/specs/swift-markdown-engine-fork-
      and-port-to-replace-our-internal-.md (supersedes epic §G4; folds in
      #82, #83, #94, #104, #105). Fork: Applacat/swift-markdown-engine,
      vendored Packages/swift-markdown-engine (subtree, branch pixley-fork).
      - [x] P1 Fork & bind — KILL BOX: GO (2026-08-12: corpus byte-exact
            both modes, STRESS-ENGINE PASS, p95 11.9ms/16ms; 2 fork
            patches: D8 undo-clear, undo/redo binding re-sync)
      - [x] P2 Surface swap (2026-08-12: both modes on the engine; old
            editors + native renderer + block parser deleted, swift-markdown
            retired; aimdRenderer dep-free)
      - [x] P3 Interactive core four (2026-08-17: generic glyph/zone seam;
            checkbox/choice/status/fill-in clickable; CriticMarkup styled-
            inert; dogfood polish 08-18: clean fill-in display + date picker,
            status chevron)
      - [x] P4 Gutter parity + polish (CODE COMPLETE 2026-08-18: TextKit 2
            line-number gutter, bookmarks, comment indicators, Add Comment,
            ⌘G, progress badge, scroll persist, internal code highlighter;
            folded issues #81-#84/#92-#94/#104/#105 closed)
      Ralph per phase: promise "G4 PHASE P<N> COMPLETE", max 25.
      REMAINING before G4 fully done: human 5-check manual QA
      (docs/specs/ralph-renderer-identity-manual-test.md) on the engine.
- [ ] G5 — Insert palette + polish (#103, #85)
- [ ] G6 — Done bar: dogfood + round-trip corpus + 2-week zero-loss soak

Ralph per gate:
`/ralph-loop "Read docs/specs/editor-epic.md in ./pixley-markdown and execute Gate G<N> only. Track state in docs/specs/editor-epic-progress.txt." --completion-promise "GATE G<N> COMPLETE" --max-iterations 25`

## Dangling
- [ ] #81/#84 manual QA (5 checks, docs/specs/ralph-renderer-identity-manual-test.md)
      — validates the substrate G4 builds on
- [ ] Formal GO on TextKit 2 (G0 human follow-up)

## Shipped this cycle (main, unreleased — v5 holds everything)
- July sweep fixes: FileWatcher (#78/#79), bookmarks (#96), write-back
  integrity (#77/#80), renderer identity + scroll (#81/#84 impl)
- G0 spike: TextKit 2 + attachment + Typora reveal proven

## Frozen / superseded
- #91 CLOSED (died in G2) · Ralph 3 rendering fixes folded into G4/G5
- Old sprints (1–3) complete; v4 milestone absorbed into v5 plan
