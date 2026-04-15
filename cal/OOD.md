# OOD — Object-Oriented Data Principles

## Architecture Pattern

**Per-window AppCoordinator** with decomposed state containers:
- `NavigationState` — folder/file selection, security-scoped bookmarks
- `UIState` — panel visibility, appearance
- `DocumentState` — document content, loading, conflicts

Views observe state via Environment, mutate through coordinator methods.

## Rules

1. **All observable state:** `@MainActor @Observable`
2. **View bindings:** `@Bindable` for observable objects
3. **File I/O:** `Task.detached` or `CoordinatedFileAccess` (never block main)
4. **Data models:** Value types (structs)
5. **Errors:** Explicit error types, no force unwraps
6. **Multi-window:** Each browser window has independent AppCoordinator
7. **Shared:** ModelContainer, settings (App level)
8. **Per-window:** Coordinator, folder watcher, chat

## The Three Sacred Questions

Every code review must answer these before passing:

1. **"Is this beautiful code?"**
   With vibecoding, writing beautiful code is just as easy as writing shit code — it just depends on how much effort the LLM puts in. There is no excuse for ugly code. Every diff should be something you'd be proud to read.

2. **"Would Apple ship this?"**
   Are we exhausting Apple's Happy Path first before doing any workarounds? We want Apple to acquire us eventually. If there's a native API, use it. If there's a platform convention, follow it. Hacks are a last resort, not a starting point.

3. **"Does this follow or set OOD best practices?"**
   We are building out the OOD philosophy, so we need to be consistent. Every change either follows existing OOD patterns or deliberately evolves them — never contradicts them silently.

4. **"Is the code self-documenting?"**
   With vibecoding, comments are code too — they give you great context without having to reference a bunch of files that pollute your context window. Write comments that explain *why*, not *what*. A well-placed comment saves a future LLM from reading 5 files to understand one decision.

## Platform Conditionals

- `#if os(macOS)` / `#if os(iOS)` for behavioral differences
- `#if canImport(AppKit)` / `#if canImport(UIKit)` for API-level differences
- Source exclusions in `project.yml` for entirely macOS-only files
- iOS is Enhanced-only (no Plain mode)
