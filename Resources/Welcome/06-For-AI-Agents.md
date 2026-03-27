# Writing Interactive Markdown for Pixley

This document is a specification for AI agents (Claude, Codex, etc.) to generate markdown that Pixley renders as interactive controls. Copy the relevant sections into your system prompt or CLAUDE.md.

## System Prompt

```
When generating markdown for Pixley Markdown, use these interactive patterns.
The user opens your output in Pixley, which makes them clickable. Their
responses are written back to the .md file for you to read.

PATTERNS:

1. Checkboxes (multi-select, independent toggles):
   - [ ] Item one
   - [ ] Item two

2. Radio choices (single-select — must be inside a blockquote):
   > - [ ] Option A
   > - [ ] Option B
   > - [ ] Option C

3. Fill-in-the-blank (click to enter value):
   - Name: [[enter your name]]
   - Date: [[pick a date]]
   - File: [[choose a file]]
   - Folder: [[choose a folder]]

4. Status pipeline (click to advance):
   <!-- status: draft / review / approved / shipped -->
   **Status:** draft

5. Review gate (single-select with date stamp):
   > - [ ] APPROVED
   > - [ ] PASS
   > - [ ] FAIL
   > - [ ] PASS WITH NOTES
   > - [ ] N/A

6. Inline comments (highlight text with a note):
   {==highlighted text==}{>>your comment here<<}

7. Suggested edits (CriticMarkup — user accepts or rejects):
   {++text to add++}
   {--text to remove--}
   {~~old text~>new text~~}

8. Gutter comments (line-level note):
   <!-- feedback -->
   <!-- feedback: existing comment text -->

RULES:
- Checkboxes OUTSIDE blockquotes = multi-select (independent toggles)
- Checkboxes INSIDE blockquotes = single-select (radio behavior)
- Fill-in hints determine the input type:
  - "date" in hint → date picker
  - "file" in hint → file dialog
  - "folder" in hint → folder dialog
  - anything else → text field
- Review keywords: APPROVED, PASS, FAIL, PASS WITH NOTES, BLOCKED, N/A
- FAIL, PASS WITH NOTES, and BLOCKED prompt the user for notes
- Status states are separated by | in the HTML comment
- Everything the user clicks saves back to the .md file
- You can read their responses by re-reading the file
```

## Tips for Agents

- **Structure for scanning.** Use headings, short paragraphs, and bullet lists. The user is reading in a syntax-highlighted viewer, not a web browser.
- **One interaction per concept.** Don't put a fill-in, a checkbox, and a review on the same line. Give each its own space.
- **Use checkboxes for progress.** Put a checklist at the top of task-oriented documents so the user can track completion.
- **Use reviews for approvals.** When you need sign-off, use the review pattern — it date-stamps automatically.
- **Use fill-ins for input.** When you need the user to provide information, use `[[hint]]` — it's more discoverable than asking them to edit raw text.
- **Use status for workflows.** Define the pipeline in the HTML comment, set the initial state in the label. The user clicks to advance.
- **Blockquote = radio.** Remember: the same `- [ ]` syntax behaves differently inside vs outside blockquotes. This is the most common mistake.

## Claude Code / CLAUDE.md Integration

Add this to your project's `CLAUDE.md` to teach Claude Code to generate Pixley-compatible documents:

```
## Interactive Markdown (Pixley)

When generating .md files the user will open in Pixley:
- Use `- [ ]` for checklists (outside blockquotes = multi-select)
- Use `> - [ ]` for choices (inside blockquotes = radio/single-select)
- Use `[[hint text]]` for fill-in fields
- Use `<!-- status: state1 / state2 -->` + `**Status:** state1` for pipelines
- Use `> - [ ] APPROVED / PASS / FAIL` for review gates
- Use `{==text==}{>>comment<<}` for inline comments
- Use `<!-- feedback -->` for line-level comment slots
```
