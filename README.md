# Pixley Reader

A native macOS app for reading the markdown files your AI tools generate.

AI coding tools dump specs, docs, and changelogs into your project folders. Pixley Reader gives you a dedicated place to browse and read them — without opening a code editor.

![Pixley Reader — sidebar, markdown viewer, and AI chat](screenshot.png)

## Features

- **Folder tree sidebar** — NSOutlineView-backed file browser, handles large trees without lag
- **Live file watching** — a reload pill appears when the file changes on disk (e.g., when your AI tool writes to it)
- **Quick Switcher (Cmd+P)** — fuzzy file search, like VS Code but native
- **Syntax-highlighted rendering** — 7 theme families with light/dark variants
- **On-device AI chat** — ask questions about the current document using Apple Foundation Models (no cloud, no API keys)
- **Drag-and-drop** — drop a folder or file onto the window to open it
- **Zero external dependencies**

## Requirements

- macOS 15 (Sequoia) or later
- AI chat requires macOS 26 (Tahoe) + Apple Intelligence

## Building

```bash
open AIMDReader.xcodeproj
```

Or with Swift Package Manager:

```bash
swift build
```

## Stack

- Swift 6.2, SwiftUI + AppKit
- Apple Foundation Models (on-device LLM)
- SwiftData for metadata persistence
- No external dependencies

## License

MIT
