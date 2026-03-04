# Pixley Markdown Reader — Promo Q&A

## Key Features

- **Folder watching with live reload** — Point it at a folder and it builds a hierarchical file tree in the sidebar (NSOutlineView, like Finder). A `FileWatcher` monitors the selected file with `DispatchSource` — when the file changes on disk (e.g., an AI agent writes to it), a reload pill appears so you can refresh instantly without switching windows.

- **Sidebar file tree** — Full recursive folder tree in the sidebar. Expand/collapse folders, click any `.md` file to view it. Backed by a native `NSOutlineView` for smooth, familiar macOS behavior.

- **Quick Switcher (Cmd+P)** — Spotlight-style fuzzy file search overlay. Type to filter, arrow keys to navigate, Enter to open. Just like VS Code's Cmd+P, but native.

- **Syntax-highlighted markdown rendering** — Custom regex-based syntax highlighter with multiple themes (light + dark variants). Configurable font family (System, Serif, Sans-Serif, Monospaced), font size, heading scale, and optional line numbers.

- **System / Light / Dark appearance** — Three-way color scheme picker in Settings. Follows system preference or overrides to always-light or always-dark. Themes auto-sync their light/dark variant to match.

- **On-device AI chat** — Ask questions about the current document using Apple Foundation Models (completely on-device, no cloud, no API keys). The AI reads a truncated version of the document and answers questions in a chat panel that slides in as an inspector. Per-turn transcript condensation keeps conversations going indefinitely within the 4096-token context window, with cross-document recall via FM tools. "Forget" to start fresh.

- **Drag-and-drop** — Drop a folder or `.md` file anywhere on the start screen to open it immediately.

- **Pixelmator-style start screen** — Clean launcher with folder shortcuts (Desktop, Documents, Downloads, Choose Folder), plus a "Read Sample Files" button that opens bundled tutorial content with an AI-powered guided tour.

- **Recent folders and files** — Tracks recently opened folders and files with security-scoped bookmarks so sandbox permissions persist across launches.

- **Session restore** — Remembers your last folder/file and reopens it on launch.

- **Settings** — Appearance tab (color scheme, theme, font family, font size, heading scale, line numbers) and Behavior tab (link behavior, underline links).

## What made you build it?

Working with AI coding tools like Claude Code, every session generates a pile of markdown files — specs, changelogs, architecture docs, meeting notes, README updates. Opening them in VS Code means they're buried among source files. Preview pane fights with your actual code. You end up with 15 tabs of `.md` files mixed in with `.swift` files and lose track of what the AI actually wrote.

The moment was realizing I had a `docs/` folder with 30+ markdown files from various Claude Code sessions and no good way to just *read* them. I didn't need to edit them — the AI wrote them. I needed to browse, read, and understand what was in there. That's a different tool than a code editor.

## What makes it different from VS Code's markdown preview?

1. **It's a reader, not an editor.** VS Code's preview is a secondary pane attached to an editor. Pixley is purpose-built for reading. No split view fighting for space, no editor gutter, no "which tab is the preview?" confusion.

2. **Built-in AI Q&A about the document.** Select a file, open the chat panel, ask "what does this spec say about error handling?" and get an answer from Apple's on-device AI. No API keys, no cloud, no config. It just works if you have Apple Intelligence enabled.

3. **Folder-first workflow.** You point it at a folder and browse a tree. VS Code can do this too, but it's optimized for editing code — markdown files are second-class citizens in that context. Pixley treats your markdown folder as the primary content.

4. **File watching that's useful for AI workflows.** When Claude Code or another AI tool writes to a file you're reading, the reload pill tells you something changed. It's designed for the workflow of "AI writes, human reads."

5. **Native macOS app.** Not Electron, not a web view. SwiftUI + AppKit where it matters (NSOutlineView for the tree, NSTextView for rendering). Feels like a Mac app because it is one.

6. **Zero configuration.** No extensions to install, no settings to tweak to get good markdown rendering. Open the app, pick a folder, read.
