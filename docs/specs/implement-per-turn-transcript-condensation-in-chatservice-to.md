# Per-Turn Transcript Condensation with Multi-Document Context

*Spec finalized: 2026-03-03*
*Implementation completed: 2026-03-03*

## Overview

Replace the hard 3-turn session reset in ChatService with per-turn transcript condensation. After each Q&A exchange, an AI summarizer compresses the conversation into an attributed summary, then a fresh LanguageModelSession is created with the original document instructions + condensed summary. Summaries are persisted via SwiftData, enabling multi-document chat where the AI can recall context from previously viewed documents using Foundation Models tool-calling.

## Problem Statement

The current ChatService resets the LanguageModelSession after 3 Q&A turns to avoid exceeding the 4096-token context window. This means:
- Users lose all conversation context after 3 questions
- Switching documents destroys all previous context
- No memory persists across app launches
- The "reset" is jarring and breaks conversational flow

## Scope

### In Scope
- Per-turn AI summarization with heuristic fallback
- Attributed summaries (track which document each Q&A was about)
- SwiftData persistence of summaries (one record per document, LRU cap of 50)
- Two Foundation Models tools: `listDocuments` and `getDocumentHistory`
- Multi-document chat (switch documents, retain cross-document context)
- "Organizing thoughts..." subtle indicator during compression
- "Forget" clears both live session AND persisted summaries for current document
- Retry-with-backoff for failed summarizations

### Out of Scope
- Streaming responses (separate feature)
- Few-shot prompting improvements (separate feature)
- @Generable structured output for chat responses
- Search across persisted summaries
- Export/import of chat history

## User Stories

### US-1: Core Condensation Engine

**Description:** As a user, I want my conversation context preserved beyond 3 turns so I can have longer, more natural conversations about a document.

**Technical Work:**
- Create `TranscriptCondenser` service with two strategies:
  1. **AI strategy**: Dedicated `LanguageModelSession` with summarizer instructions
  2. **Heuristic strategy**: Keep last 2 Q&A pairs verbatim, drop older ones
- Summarizer instructions: "Summarize this conversation preserving key facts learned, the document name, and user questions. Drop exact wording, greetings, and failed queries."
- After each successful `respond(to:)`, run condensation
- Create new session with instructions containing: document content + condensed summary
- Implement retry-with-backoff: after FM summarizer failure, skip 2 turns on heuristic, then retry FM
- Remove `maxTurnsBeforeReset` logic from ChatService
- Remove `turnCount` tracking (no longer needed for reset, but keep for analytics/logging)

**Acceptance Criteria:**
- [x] User can ask 5+ questions in a row without session reset
- [x] After turn 4, the AI still references facts from turn 1
- [x] If FM summarizer times out, heuristic fallback kicks in silently
- [x] After 2 heuristic turns following failure, FM summarizer is retried
- [x] No `exceededContextWindowSize` errors during normal conversation
- [x] Build succeeds with `swift build`

### US-2: SwiftData Summary Persistence

**Description:** As a user, I want my conversation context to survive app restarts so I can continue where I left off.

**Technical Work:**
- Create `ChatSummary` SwiftData `@Model`:
  - `documentPath: String` (unique key)
  - `documentName: String` (display name)
  - `summary: String` (condensed text, ~200-400 chars)
  - `lastUpdated: Date`
- Create `ChatSummaryRepository` (protocol + SwiftData implementation)
- After each condensation, persist/update the summary for the current document
- On session start, check for existing summary and inject into instructions
- LRU eviction: when count > 50, delete oldest by `lastUpdated`
- "Forget" deletes the `ChatSummary` record for the current document

**Acceptance Criteria:**
- [x] Quit and relaunch app, open same document, AI remembers previous conversation context
- [x] After Forget, AI has no memory of previous conversation for that document
- [x] With 51+ document summaries, oldest is evicted
- [x] `ChatSummary` model integrates with existing SwiftData schema versioning
- [x] Build succeeds with `swift build`

### US-3: Foundation Models Retrieval Tools

**Description:** As a user, I want the AI to be able to recall what I discussed about other documents, enabling cross-document questions.

**Technical Work:**
- Implement `ListDocumentsTool: Tool` conforming to Foundation Models Tool protocol:
  - Name: `listDocuments`
  - Description: "List documents the user has previously discussed"
  - Returns: document names from persisted `ChatSummary` records
- Implement `GetDocumentHistoryTool: Tool`:
  - Name: `getDocumentHistory`
  - Description: "Retrieve conversation summary for a specific document by name"
  - `@Generable struct Arguments { let documentName: String }`
  - Returns: `ToolOutput` with the summary text (~200-400 chars)
- Attach both tools to the main chat `LanguageModelSession`
- Tools read from `ChatSummaryRepository`

**Acceptance Criteria:**
- [x] AI can answer "what documents have I discussed?" using `listDocuments` tool
- [x] AI can answer "what did I learn from README.md?" using `getDocumentHistory` tool
- [x] Tools return data from SwiftData, not in-memory state
- [x] Tool output stays compact (summary only, ~200-400 chars)
- [x] Build succeeds with `swift build`

### US-4: Multi-Document Context & Document Switching

**Description:** As a user, I want to switch between documents and have the AI maintain context from all documents I've viewed.

**Technical Work:**
- When user switches documents:
  1. Persist current conversation summary (if any)
  2. Load new document content
  3. Create fresh session with: new document instructions + current document summary (if exists from SwiftData) + tools attached
- Attributed summaries: summarizer instruction includes "Include the document name '\(documentName)' in your summary"
- Session instructions format:
  ```
  You are a helpful assistant analyzing markdown documents.
  Answer questions concisely and accurately.
  If the answer is not in the document, say so.
  You have access to tools to recall conversations about other documents.

  Current document ({documentName}):
  ---
  {truncatedContent}
  ---

  Previous conversation context:
  ---
  {condensedSummary}
  ---
  ```

**Acceptance Criteria:**
- [x] Open doc A, ask 3 questions, switch to doc B, ask "what did I learn from doc A?" — AI answers correctly
- [x] Switch back to doc A — AI still has context from earlier questions about doc A
- [x] Summary attribution includes document names
- [x] Document switch does not lose unsaved summary (persisted before switch)
- [x] Build succeeds with `swift build`

### US-5: UX Updates

**Description:** As a user, I want subtle feedback that the AI is organizing context, and I want Forget to fully clear my history.

**Technical Work:**
- Add `isCondensing: Bool` observable property to ChatService
- After response is shown, briefly display "Organizing thoughts..." in ChatView
- Update "Forget" (resetSession) to:
  1. Reset live session (existing behavior)
  2. Delete `ChatSummary` for current document from SwiftData
- Update `ChatResult` enum if needed for condensation state

**Acceptance Criteria:**
- [x] After AI responds, "Organizing thoughts..." appears briefly (~1-2s) then disappears
- [x] Indicator does not block user from typing next question
- [x] After Forget, no persisted summary exists for the current document
- [x] Build succeeds with `swift build`

## Technical Design

### Data Model

```swift
@Model
final class ChatSummary {
    @Attribute(.unique) var documentPath: String
    var documentName: String
    var summary: String
    var lastUpdated: Date

    init(documentPath: String, documentName: String, summary: String) {
        self.documentPath = documentPath
        self.documentName = documentName
        self.summary = summary
        self.lastUpdated = .now
    }
}
```

### Architecture

```
ChatService
  ├── LanguageModelSession (main chat, with tools attached)
  ├── TranscriptCondenser
  │     ├── AI strategy (dedicated LanguageModelSession)
  │     └── Heuristic strategy (keep last 2 Q&A pairs)
  ├── ChatSummaryRepository (SwiftData persistence)
  ├── ListDocumentsTool (FM Tool protocol)
  └── GetDocumentHistoryTool (FM Tool protocol)
```

### Flow: Single Turn

1. User asks question
2. `ChatService.ask()` sends to main session via `respond(to:)`
3. Response returned to user, displayed in ChatView
4. `isCondensing = true` — "Organizing thoughts..." shown
5. `TranscriptCondenser` runs:
   - Try AI summarization (dedicated session)
   - On failure: fall back to heuristic, increment backoff counter
   - On success: reset backoff counter
6. Persist summary to SwiftData via `ChatSummaryRepository`
7. Create fresh main session with: document + summary + tools
8. `isCondensing = false` — indicator hidden

### Flow: Document Switch

1. User selects new document
2. Persist current summary (already done per-turn, but ensure latest)
3. Load new document content
4. Check SwiftData for existing summary of new document
5. Create fresh session with new document + existing summary (if any) + tools

### Summarizer Instructions

```
Summarize this conversation about the document "{documentName}".
Preserve: key facts the user learned, specific questions asked, important conclusions.
Include the document name in your summary.
Drop: exact wording, greetings, pleasantries, failed or error queries.
Keep the summary under 400 characters.
```

### Retry-with-Backoff Logic

```
failureCount = 0
skipsRemaining = 0

on condense():
  if skipsRemaining > 0:
    skipsRemaining -= 1
    use heuristic
    return

  try AI summarization
  on success: failureCount = 0
  on failure:
    failureCount += 1
    skipsRemaining = 2
    use heuristic
```

## Requirements

### Functional Requirements
- FR-1: Per-turn condensation replaces 3-turn hard reset
- FR-2: AI summarizer with heuristic fallback (retry after 2 heuristic turns)
- FR-3: Summaries persisted in SwiftData, one record per document path
- FR-4: LRU eviction at 50 document summaries
- FR-5: Two FM tools: `listDocuments` and `getDocumentHistory`
- FR-6: Document switching preserves and loads summaries
- FR-7: "Forget" clears live session + persisted summary
- FR-8: Summaries attributed with document name

### Non-Functional Requirements
- NFR-1: Condensation adds < 3 seconds after each response
- NFR-2: Heuristic fallback adds < 100ms
- NFR-3: No `exceededContextWindowSize` during normal 10+ turn conversations
- NFR-4: Summary text stays under 400 characters

## Implementation Phases

### Phase 1: Core Condensation (US-1)
- [x] Create `TranscriptCondenser` with AI + heuristic strategies
- [x] Modify `ChatService.ask()` to condense after each turn
- [x] Remove `maxTurnsBeforeReset` logic
- [x] Implement retry-with-backoff
- **Verification:** `swift build` + manual test: 5+ turns without reset

### Phase 2: Persistence (US-2)
- [x] Create `ChatSummary` SwiftData model
- [x] Create `ChatSummaryRepository` protocol + implementation
- [x] Persist summaries after condensation
- [x] Load existing summary on session start
- [x] LRU eviction
- **Verification:** `swift build` + manual test: quit/relaunch preserves context

### Phase 3: Retrieval Tools (US-3)
- [x] Implement `ListDocumentsTool`
- [x] Implement `GetDocumentHistoryTool`
- [x] Attach tools to main chat session
- **Verification:** `swift build` + manual test: cross-document queries work

### Phase 4: Multi-Doc + UX (US-4 + US-5)
- [x] Wire document switching with summary persistence/loading
- [x] Add `isCondensing` indicator
- [x] Update Forget to clear persisted data
- [x] Update session instructions format
- **Verification:** `swift build` + manual test: full multi-document flow

## Definition of Done

This feature is complete when:
- [x] All acceptance criteria in US-1 through US-5 pass
- [x] All implementation phases verified
- [x] Build succeeds: `swift build`
- [x] No regressions in existing chat functionality
- [x] "Organizing thoughts..." indicator visible during condensation
- [x] Cross-document queries return correct summaries
