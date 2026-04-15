# NOW — Current Focus

Work is tracked in GitHub Issues: `gh issue list --state open`

## Active: Multiplatform Epic (#23)

**Branch:** `multiplatform/ios`
**Status:** Phase 3 done. Phase 3.5 in progress.

| Phase | Status | Tickets |
|-------|--------|---------|
| Phase 1: Target + Build | DONE | #56, #62, #63 (closed) |
| Phase 2: iCloud Drive | DONE | #57, #58, #64, #65, #66, #67 (closed) |
| Phase 3: iOS UI | DONE | #59, #60, #68, #69, #70 (closed), #71, #72 |
| Phase 3.5: iOS Controls Pass | IN PROGRESS | #74 (epic) |
| Phase 4: visionOS | PENDING | #61 |

## Phase 3.5 — iOS Controls Pass (#74)

Pipeline:
1. Profile file open with Instruments — find actual bottleneck
2. Fix #71 — skip chat auto-open on iOS
3. Controls sprint — touch targets, control sizes, button styles, Liquid Glass
4. Device test on iPhone

5 critical, 10 high, 9 medium from Axiom audit.
Feature stories to be broken out from epic.

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
