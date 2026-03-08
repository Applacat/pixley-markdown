# Quick Reference

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open folder | `⌘⇧O` |
| Close folder | `⌘W` |
| Quick Switcher | `⌘P` |
| Find in document | `⌘F` |
| Next / previous match | `⌘G` / `⌘⇧G` |
| Reload document | `⌘R` |
| Font size | `⌘+` / `⌘-` |
| Toggle AI Chat | `⌘⇧A` |
| Settings | `⌘,` |
| Next / previous element | `Tab` / `⇧Tab` |
| Activate element | `Return` or `Space` |

## Interactive Controls

| You Write | They Get | You Read Back |
|-----------|----------|---------------|
| `- [ ]` / `- [x]` | Checkbox | `[ ]` or `[x]` |
| `> - [ ] Option` | Radio (single select) | `[x]` on chosen |
| `[[enter hint]]` | Text popover | Their text |
| `[[pick date]]` | Date picker | `2026-03-08` |
| `[[choose file]]` | File dialog | `/path/to/file` |
| `[[choose folder]]` | Folder dialog | `/path/to/folder` |
| `<!-- status: a \| b \| c -->` | Status dropdown | Current state |
| `<!-- feedback -->` | Comment popover | `<!-- feedback: text -->` |
| `> - [ ] PASS / FAIL / ...` | Review with date stamp | `[x] PASS — 2026-03-08` |
| `{++text++}` | Accept/Reject addition | `text` or removed |
| `{--text--}` | Accept/Reject deletion | removed or `text` |
| `{~~old~>new~~}` | Accept/Reject substitution | `new` or `old` |

## AI Prompt Template

Copy this when asking an AI to generate interactive markdown:

```
Write a markdown document using these interactive patterns. My user
opens it in Pixley Markdown, which makes them clickable:

- Checkboxes: - [ ] item (click to toggle)
- Choices: put checkboxes in a blockquote for radio/single-select
- Fill-in: [[placeholder text]] (click to type)
- Date: [[pick date]] (native date picker)
- File: [[choose file]] or [[choose folder]] (native file dialog)
- Status: <!-- status: state1 | state2 | state3 --> then **Status:** state1
- Feedback: <!-- feedback --> (click to leave a comment)
- Review: > - [ ] PASS / FAIL / APPROVED (date-stamped on click)
- Inline edits: {++add++} {--delete--} {~~old~>new~~} (accept/reject)

Rules:
- Checkboxes outside blockquotes = multi-select (independent)
- Checkboxes inside blockquotes = single-select (radio)
- FAIL, PASS WITH NOTES, and BLOCKED prompt for a reason
- Status advances forward only; last state is terminal
- Everything saves back to the .md file so you can read responses
```

## Privacy

All AI processing happens on-device via Apple Intelligence. No data leaves your Mac.

## This Tour

Click the app mascot on the Start screen to come back here anytime.
