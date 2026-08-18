> **SUPERSEDED by the swift-markdown-engine port (Gate G4, 2026-08-18).**
> This checklist validated fixes to the OLD Enhanced native renderer, which
> was deleted in G4-P2. On the engine, an interactive element **is** its
> source text (storage == source), so the whole class of identity bugs #81
> describes cannot occur — an edit above a control only shifts offsets, it
> can't transplant the control's state to a neighbor.
>
> **Automated coverage now standing in for the human checks:**
> - Tests 1/2/5 (identity across reparse/insertion) → `EngineStressHarness`
>   "US-P4.4 identity": a filled value survives a comment inserted ABOVE it,
>   stays itself, and the checkbox count is unchanged. Plus the round-trip
>   corpus + relocation suites (element survives edits elsewhere) and the
>   500-keystroke stress harness.
> - Test 3 (scroll restore across in-session file switches) → engine-native,
>   exercised by the P2 surface-swap switching checks.
> - Test 4 (scroll survives quit) → wired via the engine's
>   onPersistScrollOffset/restoreScrollOffset → file metadata (G4-P4);
>   full quit/relaunch confirmation folds into the G6 soak.
>
> #81 and #84 are closed. Kept for history; a human feel-check of the live
> editor is still welcome but no longer gates G4.

# Manual Verification: Renderer Identity + Scroll Restoration (#81, #84)

Run in **Enhanced mode** (Settings > Behavior > Interactive Mode). Use a
document with several interactive elements — `docs/dogfood-v4.md` or any
welcome doc works, or paste:

```markdown
# Identity Test

Intro paragraph.

- [ ] Task alpha
- [ ] Task beta

Name: [[enter your name]]

Feedback here:
<!-- feedback:  -->

Long filler section — add ~40 lines of prose so the document scrolls.

Closing paragraph.
```

## Test 1 — Draft survives an insertion above (#81)

1. Type a few characters into the `[[enter your name]]` fill-in but do NOT
   press Enter (leave it as an uncommitted draft).
2. Right-click the gutter next to "Intro paragraph." and add a comment
   ("test") — this inserts a line ABOVE the fill-in and triggers a reparse.
3. **PASS if:** your draft text is still in the SAME fill-in field, no other
   control shows it, and the view did not visibly jump.

## Test 2 — Checkbox toggle keeps neighbors stable (#81)

1. Scroll so both checkboxes and the fill-in are visible. Type a draft into
   the fill-in again.
2. Click "Task alpha"'s checkbox.
3. **PASS if:** the checkbox toggles, the draft stays put, nothing collapses
   or flashes below the toggled row.

## Test 3 — Scroll restores across file switches (#84)

1. Scroll to roughly the middle of the long document. Wait ~2 seconds (the
   save is debounced).
2. Switch to another file in the sidebar, then switch back.
3. **PASS if:** the view lands near where you left it (block-level accuracy,
   not pixel-perfect).

## Test 4 — Scroll survives quitting (#84)

1. With a mid-document scroll position saved (as in Test 3), quit the app.
2. Relaunch, reopen the folder, select the same file.
3. **PASS if:** the view restores near the saved position.

## Test 5 — Place kept across an interactive write (#84 + #81)

1. Scroll so a checkbox in the LOWER half of the document is at the top of
   the viewport.
2. Toggle it (this rewrites the file and reparses).
3. **PASS if:** the same block stays at the top — no jump to the start.

## Result

- [ ] PASS — close #81 and #84
- [ ] FAIL — note which test failed and reopen the mission

Notes: [[fill-in: text | observations]]
