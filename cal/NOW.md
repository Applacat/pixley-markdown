# NOW — Current Focus

Work is tracked in GitHub Issues: `gh issue list --state open`

## Active: Multiplatform Epic (#23)

**Branch:** `multiplatform/ios`
**Status:** Phase 3 wrapping up, Phase 3.5 next.

| Phase | Status | Tickets |
|-------|--------|---------|
| Phase 1: Target + Build | DONE | #56, #62, #63 (closed) |
| Phase 2: iCloud Drive | DONE | #57, #58, #64, #65, #66, #67 (closed) |
| Phase 3: iOS UI | IN PROGRESS | #59, #60, #68, #69 (closed), #70, #71, #72 |
| Phase 3.5: iOS Controls Pass | PENDING | #74 (epic) |
| Phase 4: visionOS | PENDING | #61 |

## Phase 3 — Remaining

- **#70:** Spurious reload pill (fix landed, needs device verification)
- **#71:** Chat auto-opens on iOS first launch (bug — not yet fixed)
- **#72:** iOS chat UX — toolbar button + full-screen push (implemented, needs device test)

## Phase 3.5 — iOS Controls Pass (#74)

5 critical, 10 high, 9 medium findings from Axiom audit.
Core issue: controls layer is macOS, needs iOS adaptation.
Feature stories to be broken out from the epic.

## Backlog

- #1 Table rendering
- #2 Image rendering
- #3 Code block rendering
- #4 Collapsible section rendering
- #25 Fix progress bar rendering
- #34-39 Architecture cleanup

## Shelved

- #19 .pixley project format
- #24 Public ecosystem repo
