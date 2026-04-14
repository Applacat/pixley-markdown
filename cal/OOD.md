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

## Platform Conditionals

- `#if os(macOS)` / `#if os(iOS)` for behavioral differences
- `#if canImport(AppKit)` / `#if canImport(UIKit)` for API-level differences
- Source exclusions in `project.yml` for entirely macOS-only files
- iOS is Enhanced-only (no Plain mode)
