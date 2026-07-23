# NOW — Current Focus

Work is tracked in GitHub Issues: `gh issue list --state open`

## Active: Editor Epic (#107, milestone "v5: The Editor")
Spec: `docs/specs/editor-epic.md` · Progress: `docs/specs/editor-epic-progress.txt`

- [x] G0 — TextKit 2 spike (exit tests green 2026-07-23; awaiting Jose's
      feel-check of the TextKit2Spike scheme + formal GO)
- [ ] G1 — Document model + detector fixes (#86–#89, #75, #87, #106, #102)
- [ ] G2 — Plain mode editable (kills #91)
- [ ] G3 — Conflict engine
- [ ] G4 — Enhanced WYSIWYG surface (folds in #82, #83, #94, #104, #105)
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
- #91 blocked (dies in G2) · Ralph 3 rendering fixes folded into G4/G5
- Old sprints (1–3) complete; v4 milestone absorbed into v5 plan
