# NOW — Current Focus

**Idea:** Pixley Interactive Markdown Protocol (v3.0)
**Phase:** Phase 3 complete → commit gate → Phase 4
**Pipeline:** Spec [DONE] -> Foundation [DONE] -> Core Patterns [DONE] -> Advanced Patterns [DONE] -> **AI Integration** -> Multiplatform

## Phase 3 Complete

All advanced interactive patterns wired:
- Reviews: click for date stamp, notes sheet for FAIL/BLOCKED/PASS WITH NOTES
- CriticMarkup: accept on click (additions, deletions, substitutions, highlights)
- Status state machines: single-step auto-advance, multi-step picker sheet
- Confidence: confirm high → confirmed, challenge low → feedback sheet
- Progress bars: auto-calculated per section heading (rendered-only)
- Status labels: styled as clickable badge with indigo background
- 19 write-back tests (including 9 new Phase 3 tests), all passing
- Build succeeds clean

**Deferred:** US-12 (Conditional/Collapsible — needs NSTextView layout work), US-14 (Gutter Refactor — significant extension)

## Phase 4 Scope

| Story | Description | Status |
|-------|-------------|--------|
| US-15 | FM Context Optimization — DocumentStructure.summary() for AI context | PENDING |
| US-16 | Voice Commands via AI Chat — natural language interaction | PENDING |
| US-17 | Setup Files + Starter Document | PENDING |
