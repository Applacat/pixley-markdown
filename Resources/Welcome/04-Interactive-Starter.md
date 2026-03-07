# Interactive Markdown Starter

This document demonstrates all 9 interactive patterns. Click on any element to try it.

## Setup Checklist

Use checkboxes to track progress — click to toggle:

- [ ] Read this document
- [ ] Try toggling a checkbox
- [ ] Try selecting a choice
- [ ] Fill in your name below
- [ ] Leave feedback

## Your Info

Fill in the blanks — click the placeholders:

- **Name:** [[your name]]
- **Project:** [[project name]]
- **Start Date:** [[choose a date]]

## Choose Your Focus

Choices use radio selection — only one can be selected at a time:

> - [ ] Design
> - [ ] Engineering
> - [ ] Product Management

## Review Gate

Review blocks let you approve or reject work. Some statuses prompt for notes:

> - [ ] APPROVED
> - [ ] PASS
> - [ ] FAIL
> - [ ] PASS WITH NOTES
> - [ ] N/A

## Suggested Edits

CriticMarkup lets AI suggest inline changes. Click to accept:

This project uses {++a modern ++}architecture with {--legacy --}components.

The timeline is {~~6 months~>3 months~~} for completion.

{==Key decision point==}{>>Consider alternatives before committing<<}

## Project Status

<!-- status: draft | review | approved | shipped -->
**Status:** draft

Click the status label above to advance it through the pipeline.

## AI Confidence

AI can express confidence levels on recommendations:

> [confidence: high] Use SwiftUI for the interface layer.

> [confidence: low] WebSocket might be needed for real-time updates.

Click high-confidence to confirm, low-confidence to challenge.

## Feedback

Leave feedback on this section — click the comment below:

<!-- feedback -->

---

## AI Prompt Template

Copy this prompt when asking an AI to generate interactive markdown for you:

```
Generate a markdown document using Pixley Interactive Markdown patterns:

1. Checkboxes: - [ ] item (multi-select, toggleable)
2. Choices (in blockquote): > - [ ] option (radio, single-select)
3. Fill-in: [[placeholder text]] (click to enter value)
4. Reviews (in blockquote): > - [ ] APPROVED / PASS / FAIL / PASS WITH NOTES / BLOCKED / N/A
5. CriticMarkup: {++addition++} {--deletion--} {~~old~>new~~} {==highlight==}{>>comment<<}
6. Status: <!-- status: state1 | state2 | state3 --> then **Status:** state1
7. Confidence: > [confidence: high|medium|low] recommendation text
8. Feedback: <!-- feedback --> or <!-- feedback: existing text -->
9. Conditional: <!-- if: key = value -->content<!-- endif -->

Rules:
- Checkboxes OUTSIDE blockquotes = multi-select (independent toggles)
- Checkboxes INSIDE blockquotes = single-select (radio behavior)
- Review keywords: APPROVED, PASS, FAIL, PASS WITH NOTES, BLOCKED, N/A
- Status uses forward-only transitions; last state is terminal
```
