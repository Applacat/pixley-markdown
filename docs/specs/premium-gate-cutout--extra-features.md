# Spec 1: Premium Gate + Self-Describing Element Protocol

**Version:** 1.0
**Date:** 2026-03-07
**Status:** Approved
**Price:** $9.99 one-time non-consumable

## Overview

Gate all interactive Pixley Markdown elements (except checkboxes) behind a one-time StoreKit 2 purchase. Implement the Self-Describing Element Protocol so elements expose their own schema, enabling generic AI interaction and future extensibility.

## Problem Statement

Pixley has 9 interactive element types but no monetization. The free tier should be compelling (markdown reading + checkboxes + AI chat) while Pro unlocks the full interactive protocol. The self-describing protocol (inspired by Wanderlust's patterns) ensures new element types work with the AI tool automatically.

## Scope

### In Scope
- StoreService with DockPops architecture pattern
- NSPopover upgrade prompt at click point
- Settings "Pro" tab
- App menu "Upgrade to Pro..." item
- SelfDescribingElement protocol on all interactive element types
- Section-as-object model with SectionResolver
- @Generable structured args for FM tool (sacred code)
- Unlock animation (re-highlight with pulse)
- Documentation updates (CLAUDE.md, protocol docs)

### Out of Scope
- Classic rendering mode (Spec 2)
- Pixley Modal confirmation flow (Spec 3)
- .pixley bundle format (Spec 4)
- Subscription/recurring billing
- Server-side receipt validation
- Family Sharing (future consideration)

## Free vs Pro Breakdown

### Always Free
- Full markdown rendering (syntax highlighting, headings, code blocks, links)
- Folder browsing, file watching, reload pill
- **Checkbox toggling** (`- [x]` / `- [ ]`)
- AI Chat: basic Q&A, cross-document recall, persistent summaries
- Settings (themes, fonts, rendering mode toggle)
- Quick Switcher, favorites, recent files
- Progress bars (section heading completion indicators)
- Collapsible sections
- Both rendering modes (Classic / Pro) — visual preference, not tier gate

### Pro ($9.99 One-Time)
- **Interactive elements**: Choices/radio, fill-in fields, feedback, review, status, confidence, CriticMarkup suggestions
- **AI Chat Pro**: AI can read and modify parsed interactive fields via EditInteractiveElementsTool
- AI tool gate: returns explanation to AI + fires upsell NSPopover for free users

## User Stories

### US-1: StoreService Foundation
**Description:** As a developer, I want a centralized StoreService following the DockPops pattern so all entitlement checks flow through one observable object.

**Acceptance Criteria:**
- [ ] `StoreService` is `@MainActor @Observable` with `isUnlocked: Bool`
- [ ] `StoreBackend` protocol exists as testability seam
- [ ] `LiveStoreBackend` implements real StoreKit 2 calls
- [ ] `isUnlocked` cached in UserDefaults, verified on launch via `Transaction.currentEntitlements`
- [ ] `Transaction.updates` listener started at init, handles verified/unverified/refunds
- [ ] `PurchaseState` enum: idle, purchasing, restoring, failed(String)
- [ ] `verifyOnLaunch()` loads product info + checks entitlement
- [ ] `purchase()` handles success/cancelled/pending
- [ ] `restore()` uses `AppStore.sync()` + re-checks entitlements
- [ ] `.storekit` configuration file created with product "Pixley Pro" at $9.99
- [ ] Product ID: `com.pixley.app.pro` (non-consumable)
- [ ] Unit tests with mock backend verify purchase/restore/refund flows
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`

### US-2: Interaction Gate in Click Handler
**Description:** As a free user, I want locked Pro elements to look native and inviting, but clicking them shows an upgrade prompt instead of performing the interaction.

**Acceptance Criteria:**
- [ ] `MarkdownNSTextView.mouseDown` checks `StoreService.isUnlocked` before dispatching non-checkbox interactions
- [ ] All element types render with full native indicators (SF Symbols, glass fields, etc.) regardless of purchase state
- [ ] Clicking a locked element shows NSPopover at click point
- [ ] NSPopover contains: "Unlock Pixley Pro to use [Element Type Name]", price ($9.99), Purchase button, "Restore Purchase" link
- [ ] Purchase button calls `StoreService.purchase()`
- [ ] Restore link calls `StoreService.restore()`
- [ ] NSPopover dismisses on successful purchase
- [ ] Interactive mode toggle only affects checkboxes for free users

### US-3: Settings Pro Tab
**Description:** As a user, I want to see my Pro status and purchase/restore from Settings.

**Acceptance Criteria:**
- [ ] New "Pro" tab in SettingsView
- [ ] Shows current status: "Free" or "Pro (Unlocked)"
- [ ] When free: shows feature list, price, Purchase button, Restore button
- [ ] When Pro: shows "Thank you" message, date purchased (if available)
- [ ] Purchase/Restore buttons use StoreService

### US-4: App Menu Upgrade Item
**Description:** As a user, I want a menu item to access Pro upgrade.

**Acceptance Criteria:**
- [ ] "Pixley > Upgrade to Pro..." menu item in app menu (when free)
- [ ] Menu item hidden or shows "Pixley Pro" (no ellipsis) when already purchased
- [ ] Clicking opens Settings to Pro tab (or a dedicated purchase sheet)

### US-5: Unlock Animation
**Description:** As a user who just purchased, I want the document to visually respond to my purchase.

**Acceptance Criteria:**
- [ ] After `StoreService.isUnlocked` flips true, trigger re-highlight pass on current document
- [ ] Elements transition with brief animation (opacity pulse or color shift)
- [ ] No manual reload needed — elements become interactive immediately

### US-6: SelfDescribingElement Protocol
**Description:** As a developer, I want each interactive element to describe itself (schema, fields, valid values) so the AI tool can interact with elements generically.

**Acceptance Criteria:**
- [ ] `SelfDescribingElement` protocol defined with:
  - `var elementType: String` — human-readable type name (e.g., "Checkbox", "Status")
  - `var schemaDescription: String` — what this element is and does
  - `var editableFields: [EditableField]` — fields the AI can modify
  - `func apply(field: String, value: String) -> InteractiveEdit?` — produces an edit from field/value
- [ ] `EditableField` struct: `name: String, currentValue: String, validValues: [String]?`
- [ ] All 9 element types conform to `SelfDescribingElement`:
  - CheckboxElement: field "isChecked", values ["true", "false"]
  - ChoiceElement: field "selected", values [option indices]
  - ReviewElement: field "selected", values [option indices], field "notes"
  - FillInElement: field "value", no constrained values
  - FeedbackElement: field "text", no constrained values
  - StatusElement: field "status", values = element's `states` array
  - ConfidenceElement: field "confirmed", values ["true", "false"]
  - SuggestionElement: field "action", values ["accept", "reject"]
  - ConditionalElement, CollapsibleElement: detect-only, no editable fields
- [ ] Sacred code comment on protocol: "UPDATE CONFORMANCES WHEN ADDING ELEMENT TYPES"

### US-7: SectionResolver
**Description:** As the AI tool, I want to query elements by section so I can resolve "mark all in Section 3" without holding every element in context.

**Acceptance Criteria:**
- [ ] `SectionResolver` takes flat `[InteractiveElement]` + document text and groups elements by heading hierarchy
- [ ] Headings parsed by level (H1 > H2 > H3 etc.) — elements belong to the most recent heading at any level
- [ ] `func elements(inSection sectionIndex: Int) -> [InteractiveElement]`
- [ ] `func sections() -> [(index: Int, title: String, level: Int, elementCount: Int)]`
- [ ] Section objects know their children without the AI needing them in context

### US-8: AI Tool Entitlement Gate
**Description:** As a free user asking the AI to modify fields, I want to see the upgrade prompt and the AI to explain the feature.

**Acceptance Criteria:**
- [ ] `EditInteractiveElementsTool.call()` checks `StoreService.isUnlocked`
- [ ] If free: fires upsell NSPopover (or signals chat to show it) + returns ToolOutput: "This feature requires Pixley Pro. The user was shown the upgrade prompt."
- [ ] AI responds conversationally based on the tool's response
- [ ] If Pro: tool executes normally

## Technical Design

### Data Model

```swift
// StoreService (DockPops pattern)
@MainActor @Observable
final class StoreService {
    static let productID = "com.pixley.app.pro"
    private(set) var isUnlocked: Bool
    private(set) var productInfo: StoreProductInfo?
    private(set) var purchaseState: PurchaseState
    // ... (see DockPops StoreService for full pattern)
}

// SelfDescribingElement Protocol
protocol SelfDescribingElement {
    var elementType: String { get }
    var schemaDescription: String { get }
    var editableFields: [EditableField] { get }
    func apply(field: String, value: String) -> InteractiveEdit?
}

struct EditableField {
    let name: String
    let currentValue: String
    let validValues: [String]?
}

// SectionResolver
struct SectionResolver {
    struct Section {
        let index: Int
        let title: String
        let level: Int
        let range: Range<String.Index>
        let elements: [InteractiveElement]
    }

    static func resolve(elements: [InteractiveElement], in text: String) -> [Section]
}
```

### Integration Points
- `StoreService` injected into `AppCoordinator` at launch
- `MarkdownNSTextView` reads `StoreService.isUnlocked` for click gating
- `EditInteractiveElementsTool` reads `StoreService.isUnlocked` for AI gating
- `MarkdownHighlighter` unchanged — renders all elements natively regardless of tier
- `InteractionHandler` unchanged — still handles write-back, gate is in the click/tool layer

### .storekit Configuration
```
File: Products.storekit
Product ID: com.pixley.app.pro
Type: Non-Consumable
Reference Name: Pixley Pro
Price: $9.99
```

## Implementation Phases

### Phase 1: StoreService + .storekit Config (US-1)
- [ ] Create Products.storekit configuration
- [ ] Implement StoreBackend protocol + LiveStoreBackend
- [ ] Implement StoreService (@Observable, cached, listener)
- [ ] Write unit tests with mock backend
- [ ] Wire StoreService into AppCoordinator
- **Verification:** `cd Packages/aimdRenderer && swift test` + `xcodebuild build`

### Phase 2: Interaction Gate + NSPopover (US-2)
- [ ] Add entitlement check to MarkdownNSTextView.mouseDown
- [ ] Build NSPopover with upgrade content
- [ ] Wire Purchase/Restore buttons to StoreService
- [ ] Limit toggle to checkboxes-only for free users
- **Verification:** Manual test: click locked element → popover appears. Click checkbox → works.

### Phase 3: Purchase UI (US-3, US-4, US-5)
- [ ] Settings Pro tab
- [ ] App menu item
- [ ] Unlock animation (re-highlight with pulse)
- **Verification:** Purchase in StoreKit testing → settings shows Pro, menu updates, document re-renders.

### Phase 4: Self-Describing Protocol (US-6, US-7)
- [ ] Define SelfDescribingElement protocol
- [ ] Conform all 9 element types
- [ ] Implement SectionResolver
- [ ] Sacred code comments
- [ ] Unit tests for conformances and section resolution
- **Verification:** `swift test` — all conformances return valid editableFields, SectionResolver groups correctly.

### Phase 5: AI Tool Gate (US-8)
- [ ] Add entitlement check to EditInteractiveElementsTool
- [ ] Return explanation string for free users
- [ ] Signal upsell from tool context
- [ ] Update AI instructions to handle Pro gate response
- **Verification:** Manual test: AI asked to modify field (free) → upsell shown, AI explains. (Pro) → edit executes.

## Definition of Done

This feature is complete when:
- [ ] All acceptance criteria in US-1 through US-8 pass
- [ ] All implementation phases verified
- [ ] Tests pass: `cd Packages/aimdRenderer && swift test`
- [ ] Build succeeds: `xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build`
- [ ] StoreKit testing: purchase, restore, and refund flows work in .storekit config
- [ ] CLAUDE.md and protocol docs updated

## Ralph Loop Command

```bash
/ralph-loop "Implement Premium Gate + Self-Describing Protocol per spec at docs/specs/premium-gate-cutout--extra-features.md

PHASES:
1. StoreService + .storekit config - verify with swift test + xcodebuild build
2. Interaction gate + NSPopover - verify with manual test
3. Purchase UI (Settings, menu, animation) - verify with StoreKit testing
4. Self-Describing Protocol + SectionResolver - verify with swift test
5. AI Tool Gate - verify with manual test

VERIFICATION (run after each phase):
- cd Packages/aimdRenderer && swift test
- xcodebuild -project AIMDReader.xcodeproj -scheme AIMDReader -destination 'platform=macOS' build

ESCAPE HATCH: After 20 iterations without progress:
- Document what's blocking in the spec file under 'Implementation Notes'
- List approaches attempted
- Stop and ask for human guidance

Output <promise>COMPLETE</promise> when all phases pass verification." --max-iterations 30 --completion-promise "COMPLETE"
```

## Open Questions
- Family Sharing support: defer to future iteration?
- Should the popover show a brief demo/animation of the element in action?

## Implementation Notes
*To be filled during implementation*
