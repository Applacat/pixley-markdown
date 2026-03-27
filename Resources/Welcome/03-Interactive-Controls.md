# Interactive Controls

Pixley turns markdown patterns into clickable controls. Try each one below.

## Checkboxes

Click to toggle. Each is independent (multi-select):

- [ ] I clicked this checkbox
- [ ] And this one too
- [ ] Checkboxes save back to the file

## Choices (Radio Buttons)

Inside a blockquote, checkboxes become single-select. Only one can be active:

> - [ ] Option A
> - [ ] Option B
> - [ ] Option C

## Fill-in-the-Blank

Click the placeholder to enter a value:

- **Name:** [[your name]]
- **Date:** [[pick a date]]
- **Project:** [[project name]]

## Status Dropdown

Click the status label to cycle through states:

<!-- status: draft / in progress / review / done -->
**Status:** draft

## Reviews

Review blocks use keywords. Some prompt for notes:

> - [ ] APPROVED
> - [ ] PASS
> - [ ] FAIL
> - [ ] N/A

## Inline Comments

Select text and click "Add Comment" to attach a note. Click highlighted text to read it:

{==This sentence has a comment attached==}{>>This is an example comment. Click the highlighted text to see this.<<}

## Gutter Comments

Click any line number in the gutter to open the bookmark and comment popover. When a line has a comment, a speech bubble icon appears:

<!-- feedback -->

## CriticMarkup (Suggested Edits)

AI can propose inline changes. Click to accept or reject:

- Addition: {++new text to add++}
- Deletion: {--text to remove--}
- Substitution: {~~old text~>new text~~}
