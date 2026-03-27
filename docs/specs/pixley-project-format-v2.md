# Pixley Project Format (.pixley) — v2 Vision

**Date:** 2026-03-10
**Status:** Early direction, not yet spec'd for implementation

---

## The Problem

Dragging a folder into an app is counter-intuitive for normal people. The current folder-first model is a power-user gesture. Pixley needs a document you can double-click.

## The Solution

A `.pixley` file is a lightweight bookmark manifest — it points at folders and files on disk, and owns only the metadata (chat history, AI context, element states). The markdown files stay where they are.

### Key properties:
- **Multi-root**: A single .pixley can bookmark multiple, disparate folders at the top level. API docs in one place, design notes in another, shared specs on a mounted drive — one sidebar.
- **Lightweight**: The .pixley file is small. It's bookmarks + metadata, not a copy of the files.
- **The door, not the room**: The folder is the source of truth for markdown. The .pixley is what you double-click to get there.
- **Finder-native**: Shows up in Recents, Spotlight, Open Recent. Double-click to open. Has a UTI and icon.
- **Same folder, multiple projects**: The same folder can appear in different .pixley files with different chat histories and AI context.

## StartView Redesign

Three entry points:
1. **Browse a Folder** — existing power-user path, opens a tree
2. **Open a File** — single .md file, own window (already works)
3. **Create a Project** — new path: creates a .pixley, bookmarks one or more folders

Recents below shows a mix of recent folders, files, and .pixley projects. Projects naturally bubble up because that's the persistent artifact people keep opening.

## What a .pixley file contains

```
MyProject.pixley  (document bundle or flat plist/JSON — TBD)
├── manifest        (bookmarked folder/file paths)
├── chat/           (per-document AI conversation logs, as markdown)
├── context/        (AI memory/orientation across sessions)
└── state/          (interactive element states, if needed)
```

Markdown files are NOT copied into the bundle. They live on disk. The .pixley only stores bookmarks to them.

## Open Questions

- Flat file (plist/JSON) vs document bundle (directory)?
  - Bundle: can hold chat logs as .md files (dogfooding), visible in Finder as single file
  - Flat: simpler, smaller, but then where do chat logs live?
- How does adding/removing folders work in the sidebar? Drag? Menu?
- Should the manifest also bookmark individual files, or only folders?
- What happens if a bookmarked folder moves or is deleted? (Stale bookmark UX)
- Does this replace the current folder-browser entirely, or coexist?

## Relationship to Existing Specs

The original `pixley-bundle-format.md` (now in `docs/specs/`) assumed a project that *copies* files and is developer-focused. This v2 direction is different:
- Files stay on disk (bookmarks, not copies)
- Multi-root (not single folder)
- Aimed at everyone, not just developers
- The .pixley is the primary way to open the app, not a power feature

The original spec should be superseded by this direction once implementation is planned.

## Priority

Not yet prioritized against v4 native rendering / missing controls. Needs product decision on sequencing.
