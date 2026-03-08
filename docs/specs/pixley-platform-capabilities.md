# Pixley Markdown

Your human uses **Pixley Markdown**, a macOS app that makes `.md` files interactive. When you write certain markdown patterns, your human can respond directly in the document. Their responses save back to the `.md` file so you can read them.

---

## Controls

### Checkbox

```markdown
- [ ] Unchecked
- [x] Checked
```

They click to toggle. You read back `[ ]` or `[x]`.

---

### Auditable Checkbox

A checkbox that auto-appends a timestamp when checked. Write whatever labels you want.

```markdown
- [ ] Deployed to staging
- [ ] Schema migration verified
- [ ] Load test completed
```

When they check, it becomes:
```markdown
- [x] Deployed to staging — 2026-03-08
- [x] Schema migration verified — 2026-03-08: Had to run it twice
- [ ] Load test completed
```

Unchecking removes the timestamp and any notes. You read back `[x] Label — DATE` or `[x] Label — DATE: their note`.

---

### Radio (single select)

Put checkboxes inside a blockquote. Picking one deselects the others.

```markdown
> **Which database?**
> [ ] A. PostgreSQL
> [ ] B. SQLite
> [ ] C. MongoDB
```

Yes/no shorthand:
```markdown
> **Add caching?**
> [ ] YES  [ ] NO
```

You read back which has `[x]`.

---

### Text input

```markdown
Project name: [[enter project name]]
```

They click, type in a popover, and `[[enter project name]]` is replaced with their text.

---

### Date picker

```markdown
Deadline: [[pick date]]
```

They get a native date picker. `[[pick date]]` is replaced with `2026-03-08`.

---

### Slider

```markdown
Priority: [[slide 1-10]]
Satisfaction: [[rate 1-5]]
```

They get a native slider. `[[slide 1-10]]` is replaced with the number they chose (e.g. `7`).

---

### Stepper

```markdown
Server count: [[pick number 1-20]]
Replicas: [[pick number]]
```

They get a native stepper (up/down arrows). `[[pick number 1-20]]` is replaced with the number (e.g. `3`). Without a range, it's unbounded.

---

### Toggle

```markdown
Enable logging: [[toggle]]
Dark mode: [[toggle]]
```

They get a native on/off switch. `[[toggle]]` is replaced with `on` or `off`.

---

### Color picker

```markdown
Brand color: [[pick color]]
```

They get a native color picker. `[[pick color]]` is replaced with a hex value (e.g. `#FF5733`).

---

### File picker

```markdown
Config file: [[choose file]]
```

They get a native file dialog. `[[choose file]]` is replaced with the full path. After filling, the path shows as a clickable badge — they can click it to re-pick a different file.

---

### Folder picker

```markdown
Output directory: [[choose folder]]
```

Same as file picker but for directories. Also re-pickable after filling.

---

### Dropdown (state machine)

```markdown
<!-- status: draft | review | approved | shipped -->
**Status:** draft
```

They click the status to advance it forward through the states. Terminal states get a date stamp: `**Status:** shipped — 2026-03-08`.

---

### Text area (feedback)

```markdown
<!-- feedback -->
```

They click, type in a multiline popover, and it becomes:
```markdown
<!-- feedback: Their comments here. -->
```

---

### Accept / Reject (inline suggestions)

```markdown
The API should {++include rate limiting++} for all endpoints.
The system {--uses polling but--} will switch to WebSockets.
Deploy to {~~staging~>production~~} after QA.
{==No auth here==}{>>Add OAuth?<<}
```

They see additions in green, deletions in red, substitutions as old→new. They click Accept or Reject on each. You read back clean text.

| Accept | Reject |
|--------|--------|
| `{++text++}` → `text` | `{++text++}` → removed |
| `{--text--}` → removed | `{--text--}` → `text` |
| `{~~old~>new~~}` → `new` | `{~~old~>new~~}` → `old` |

---

## Rich Rendering

Pixley renders these markdown constructs as native elements instead of styled text.

### Tables

```markdown
| Feature | Status |
|---------|--------|
| Auth    | Done   |
| Search  | WIP    |
```

Renders as a proper formatted table. Interactive elements inside cells (checkboxes, fill-ins, etc.) work normally.

---

### Images

```markdown
![Architecture diagram](./diagrams/arch.png)
```

Renders the actual image inline. Local file paths only, resolved relative to the document.

---

### Code blocks

````markdown
```python
def hello():
    print("world")
```
````

Renders with syntax highlighting and a copy-to-clipboard button.

---

### Collapsible sections

```markdown
<!-- collapsible: Implementation Details -->
Detailed content here...
<!-- endcollapsible -->
```

Renders as a native expand/collapse section. Click the title to toggle.

---

## Reading Responses

Read the file back. Look for:
- `[x]` — checked
- `[x] Label — DATE` or `[x] Label — DATE: note` — auditable checkbox completed
- `[[...]]` gone, replaced with plain text — filled in
- `<!-- feedback: text -->` — they commented
- CriticMarkup gone — they accepted or rejected

---

## Progress Bars

Pixley auto-shows progress next to section headings based on checked checkboxes in that section. This is display-only — nothing is written to the file.

---

## Opening Files

```bash
open -a "Pixley Markdown" /path/to/file.md
open -a "Pixley Markdown" /path/to/folder/
```

If they already have the file open and you write to it, Pixley detects the change and offers to reload.
