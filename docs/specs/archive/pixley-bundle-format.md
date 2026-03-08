# Spec 4: .pixley Bundle Format

**Version:** 1.0
**Date:** 2026-03-07
**Status:** Approved
**Depends on:** Spec 1 (Premium Gate + Self-Describing Protocol)

## Overview

Introduce the `.pixley` document bundle format — a macOS document bundle (like .playground) that packages markdown files, AI chat logs, and project context into a single Finder-presentable file. Positions Pixley as a developer tool, not just a markdown reader.

## Problem Statement

Currently Pixley opens loose folders of markdown files. There's no concept of a "project" — no saved state, no chat history persistence beyond SwiftData summaries, no way to share a curated set of documents with context. The .pixley bundle creates a self-contained project format where AI chat history, element states, and project context all live together as markdown files.

## Bundle Structure

```
MyProject.pixley/
  project.md              <- Project manifest/overview (markdown)
  docs/
    spec.md               <- User's markdown documents
    notes.md
    architecture.md
  chat/
    spec-chat.md           <- AI conversation log for spec.md
    notes-chat.md          <- AI conversation log for notes.md
  context/
    summary.md             <- AI orientation/memory across sessions
```

### Design Philosophy: Dogfood Markdown
Everything in the bundle is markdown. Chat logs, context files, project manifests — all `.md`. The AI can read its own history. Users can read and edit everything. The format is transparent, human-readable, and consistent with Pixley's core identity.

### project.md Manifest
```markdown
# MyProject

**Created:** 2026-03-07
**Last Opened:** 2026-03-07

## Documents
- [spec.md](docs/spec.md) — Project specification
- [notes.md](docs/notes.md) — Development notes

## Project Context
This is a SwiftUI app for managing...

## AI Notes
<!-- Persisted AI orientation from previous sessions -->
The user prefers concise responses. Key architectural decisions...
```

## User Stories

### US-1: Bundle Creation
**Description:** As a user, I want to create a new .pixley project from a folder of markdown files.

**Acceptance Criteria:**
- [ ] File > New Pixley Project... menu item
- [ ] User selects a folder — Pixley creates a `.pixley` bundle containing copies of the markdown files
- [ ] project.md auto-generated with document listing
- [ ] chat/ and context/ directories created (empty initially)
- [ ] Bundle appears as a single file in Finder
- [ ] Double-clicking the bundle opens it in Pixley

### US-2: UTI Registration
**Description:** As a user, I want .pixley files to be associated with Pixley in Finder.

**Acceptance Criteria:**
- [ ] Custom UTI declared: `com.pixley.project`
- [ ] Info.plist registers UTI as document bundle
- [ ] Finder shows Pixley icon for .pixley bundles
- [ ] Double-click opens in Pixley
- [ ] Quick Look preview shows project.md content (if feasible)
- [ ] Drag-and-drop .pixley onto Pixley opens it

### US-3: Opening and Browsing Bundles
**Description:** As a user, I want to open a .pixley bundle and browse its contents like a folder.

**Acceptance Criteria:**
- [ ] Opening a .pixley bundle shows its docs/ contents in the sidebar
- [ ] project.md shown at the top of the tree or as a header
- [ ] chat/ and context/ directories hidden from sidebar (internal files)
- [ ] Security-scoped bookmark saved for the bundle path
- [ ] Recent files/folders tracking works with .pixley bundles
- [ ] File watching works inside the bundle (changes detected, reload pill shown)

### US-4: Chat Log Persistence
**Description:** As a user, I want my AI chat history saved as markdown in the .pixley bundle.

**Acceptance Criteria:**
- [ ] When chatting about `spec.md`, conversation appended to `chat/spec-chat.md`
- [ ] Chat log format: markdown with `## User` and `## AI` headers per turn
- [ ] Pixley Modal proposals and outcomes logged
- [ ] Chat log readable as a standalone markdown document
- [ ] Opening the project loads previous chat context for each document
- [ ] Chat log used as context for AI orientation (injected into session instructions)

### US-5: AI Context/Memory
**Description:** As the AI, I want persistent orientation context so I can resume conversations intelligently.

**Acceptance Criteria:**
- [ ] `context/summary.md` contains AI-generated orientation notes
- [ ] Updated at end of each chat session (or every N turns)
- [ ] Includes: key decisions, user preferences, document summaries
- [ ] Injected into LanguageModelSession instructions when opening the project
- [ ] Replaces/extends current SwiftData ChatSummary approach for .pixley projects

### US-6: Asset Catalog Carousel (Pro Feature)
**Description:** As a Pro user working in an app project, I want to see app icons from nearby .xcassets in the sidebar.

**Acceptance Criteria:**
- [ ] When a .pixley bundle is created, scan the parent directory + siblings + children for .xcassets
- [ ] If .xcassets found containing AppIcon, extract icon images
- [ ] Show mini carousel at bottom of sidebar with icon variants
- [ ] Carousel cycles through icon sizes/variants
- [ ] FileWatcher detects new .xcassets added to the project tree
- [ ] Pro-only feature (gated behind StoreService.isUnlocked)

### US-7: User Manual Bundle
**Description:** As a new user, I want a built-in .pixley project that demonstrates all interactive features with full functionality (even without Pro).

**Acceptance Criteria:**
- [ ] App ships with `Pixley Manual.pixley` in the bundle resources
- [ ] First launch: copied to `~/Documents/Pixley Manual.pixley/`
- [ ] Manual contains example documents demonstrating each interactive element type
- [ ] All interactive features unlocked inside the Manual (bypasses Pro gate)
- [ ] Gate bypass detected by checking if the file's bundle matches the Manual bundle path
- [ ] Manual documents use Pixley Markdown Protocol with clear explanations

### US-8: Adding/Removing Documents
**Description:** As a user, I want to add or remove markdown files from my .pixley project.

**Acceptance Criteria:**
- [ ] Drag-and-drop markdown files into the sidebar to add them to docs/
- [ ] Right-click > Remove from Project to remove (with confirmation)
- [ ] project.md auto-updates when documents are added/removed
- [ ] Creating a new markdown file inside the bundle via File > New Document

## Technical Design

### Bundle Detection

```swift
extension URL {
    var isPixleyBundle: Bool {
        pathExtension == "pixley" && hasDirectoryPath
    }
}
```

### UTI Declaration (Info.plist)

```xml
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.pixley.project</string>
        <key>UTTypeDescription</key>
        <string>Pixley Project</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>com.apple.package</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>pixley</string>
            </array>
        </dict>
    </dict>
</array>
```

### Chat Log Format

```markdown
# Chat Log: spec.md

## 2026-03-07 14:30

### User
Mark all purchase screen tests in Section 3 as done

### AI
I found 3 checkboxes in Section 3. Here's what I'll mark as done:
- Write unit tests for login
- Add error handling to API
- Update documentation

### Pixley Modal
**Action:** Mark as done
**Items:** 3 checkboxes in Section 3
**Result:** Confirmed — 3 items marked as done

---

## 2026-03-07 14:35

### User
What's the status of the review?

### AI
The review element shows "Draft". There are 3 options...
```

### Integration Points
- `FolderService.loadTree()` extended to detect and handle .pixley bundles
- `AppCoordinator.openFolder()` recognizes .pixley bundles
- `ChatService` reads/writes chat logs from bundle's chat/ directory
- `TranscriptCondenser` writes summaries to context/summary.md for .pixley projects
- `FileWatcher` monitors bundle contents
- `StoreService.isUnlocked` checked for asset carousel
- Special case: Pixley Manual bundle bypasses Pro gate

### Scanning for .xcassets

```swift
func findAssetCatalogs(near bundleURL: URL) -> [URL] {
    let parentDir = bundleURL.deletingLastPathComponent()
    // Scan parent + siblings + children recursively
    // Find directories with .xcassets extension
    // Look for AppIcon.appiconset inside
}
```

## Implementation Phases

### Phase 1: Bundle Structure + Creation (US-1, US-2)
- [ ] Define bundle directory layout
- [ ] UTI registration in Info.plist
- [ ] "New Pixley Project" creation flow
- [ ] project.md auto-generation
- **Verification:** Create .pixley → Finder shows as single file → double-click opens in Pixley.

### Phase 2: Open + Browse + Watch (US-3, US-8)
- [ ] Detect and open .pixley bundles
- [ ] Sidebar shows docs/ contents, hides internal directories
- [ ] FileWatcher integration
- [ ] Add/remove documents
- **Verification:** Open .pixley → browse docs → add a file → remove a file → file watching works.

### Phase 3: Chat Logs + AI Context (US-4, US-5)
- [ ] Chat log read/write as markdown in chat/
- [ ] Context summary persistence in context/
- [ ] AI orientation from summary on project open
- [ ] Integration with existing ChatService
- **Verification:** Chat about a doc → close → reopen → AI remembers context from chat log.

### Phase 4: Asset Carousel + User Manual (US-6, US-7)
- [ ] .xcassets scanning
- [ ] Sidebar carousel UI
- [ ] User Manual bundle shipped in app resources
- [ ] First-launch copy to ~/Documents
- [ ] Pro gate bypass for Manual
- **Verification:** Open manual → all features work (free). Open regular project → asset carousel shows icons (Pro).

## Definition of Done

- [ ] All 8 user stories pass acceptance criteria
- [ ] .pixley bundles create, open, and browse correctly
- [ ] Chat history persists as markdown in bundle
- [ ] AI context/memory works across sessions
- [ ] Asset carousel shows icons for app projects (Pro)
- [ ] User Manual works with all features (free)
- [ ] UTI registration: Finder association, double-click, drag-and-drop
- [ ] Tests pass, build succeeds

## Open Questions
- Should .pixley bundles support versioning? (git inside the bundle?)
- Should there be a "Export as Folder" option to extract docs/ back to a regular directory?
- How to handle .pixley bundles on iCloud Drive? (document bundle + iCloud sync can have edge cases)
- Should the User Manual update on app updates? (replace ~/Documents copy or leave user's edits intact?)

## Implementation Notes
*To be filled during implementation*
