# Design System

## Philosophy

- **"Just Pipes"** — Expose native controls. AI writes markdown, user responds inline.
- **Apple Happy Path** — Native SwiftUI patterns, generous padding, proper button styles.
- **Two modes:** Plain (macOS only, NSTextView) + Enhanced (SwiftUI native renderer, both platforms)

## Visual Language

- Monospace-first typography (code editor aesthetic)
- Palette-colored blocks from syntax themes (7 theme families)
- Material backgrounds (`.ultraThinMaterial`, `.regularMaterial`)
- Xcode-welcome-screen style buttons (transparent rest, subtle hover fill)

## Mascot

Pixley — cartoon character on Start screen. Click to open Welcome tour.
Asset: `Assets.xcassets/Pixley`

## App Store

- **Name:** Pixley Markdown
- **Bundle ID (macOS):** com.aimd.reader
- **Bundle ID (iOS):** com.aimd.reader.ios
- **Category:** Productivity
