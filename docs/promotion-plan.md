# Pixley Markdown Reader — Promotion Plan

**Version:** 2.0 (shipped, Mac App Store)
**Price:** Free. Open source. No IAP.
**Tagline:** Read what AI writes.

---

## Brand Note

Pixley is the mascot and brand, not just this app. The full product name is **Pixley Markdown Reader** (App Store) or **Pixley Reader** (shorthand). Future products follow the same convention — Pixley Roam, Pixley Biz, etc. In posts, say "Pixley Reader" when referring to this app, not just "Pixley."

---

## Table of Contents

1. [Positioning](#positioning)
2. [Visual Assets](#visual-assets)
3. [Platform Strategy](#platform-strategy)
4. [Post Drafts](#post-drafts)
5. [Prepared Rebuttals](#prepared-rebuttals)
6. [Timing and Sequencing](#timing-and-sequencing)
7. [What Not to Do](#what-not-to-do)
8. [Success Metrics](#success-metrics)

---

## Positioning

The core story is narrow and honest: **AI tools generate a lot of markdown. There's no good dedicated app for reading it.**

VS Code buries markdown among source files. Obsidian is for *your* notes, not AI output. Marked 2 is a previewer paired with an editor — no folder browsing or AI Q&A. Pixley Reader is the first app designed for the "AI writes, you read" workflow.

Don't position as a replacement. Position as a new category: **a reader for AI-generated documentation.**

**One-sentence pitch:**
"A native Mac app for reading the markdown files your AI tools generate — folder tree, live file watching, on-device AI chat, zero config."

**Credibility:** Free + open source, native Swift/SwiftUI, zero dependencies, built by someone with the problem.

**Be upfront about:** macOS only. AI chat needs macOS 26 + Apple Intelligence. Not an editor, never will be. Apple FM only — private but not configurable.

---

## Visual Assets

Create all before posting. Visuals carry 80% of the weight on Reddit and Product Hunt.

1. **Hero screenshot** — Full app: sidebar tree + rendered markdown. Dark theme (Dracula or One Dark). Real AI-generated doc. Primary image everywhere.
2. **Live reload GIF (15-20s)** — File open -> terminal `echo` -> reload pill -> click -> updated. The money shot.
3. **Quick Switcher GIF (8-10s)** — Cmd+P, type, file opens. Instant VS Code recognition.
4. **Theme grid** — 2x4, same file in 7 theme families. Caption: "7 theme families (10 variants with light/dark)."
5. **AI chat screenshot** — Inspector panel with a real Q&A about a document.
6. **Start screen screenshot** — The Pixelmator-style launcher.

**Format:** Screenshots 2x Retina PNG, window-only. GIFs 1280x800 max, 15fps, <10MB (Reddit) / <5MB (inline). MP4 alt for Twitter/Mastodon.

---

## Platform Strategy

### Tier 1: High-value, do first

**r/macapps** — Best subreddit for native Mac apps. "I built..." format is welcome. Visual posts crush text-only. Self-promo OK if transparent. Image/GIF post + first comment with details. Low risk.

**Hacker News (Show HN)** — Loves native apps, open source, developer tools. Skeptical of marketing — state your own flaws first. Title: "Show HN: Name — description" (under 80 chars). Link to App Store or GitHub. Be in comments within 5 min. Post Tuesday/Wednesday 8-9 AM EST. Risk: "yet another markdown app" dies in /new — lead with the AI-reading workflow angle.

**r/vibecoding** — This is the audience. They're generating the markdown you're solving for. Lead with your Lisa/Ralph workflow, not the app. The app is the punchline: "I had so many spec files I built a reader." Process post format. Low risk, high fit.

**r/ClaudeAI** — This community generates more markdown than anyone. Frame as a workflow tool, not a product. GIF post. Low-medium risk.

**Product Hunt** — Weekend launch (lower competition). Tagline: "Read the markdown files your AI tools write" (47 chars). Gallery: hero, reload GIF, switcher GIF, AI chat, theme grid. Maker's first comment with origin story. Prep: create account 2+ weeks early, build profile credibility. Even 50 upvotes = permanent listing.

### Tier 2: Worth doing, lower effort

| Platform | Angle | Format |
|----------|-------|--------|
| r/SideProject | Indie showcase | GIF post, short text |
| Twitter/X | #BuildInPublic thread | 4-5 tweets: hook -> problem -> demo GIF -> details -> links |
| Mastodon (iosdev.space) | Open source, native app | Single post + hero screenshot. Link GitHub, not App Store |
| Dev.to | Technical article: "Why I built a reader instead of using VS Code" | 1000-1500 words. Problem -> reader vs editor -> tech decisions -> links |
| r/swift + r/iOSProgramming | Open-source learning resource | Link to GitHub. Frame as architecture example, not product |

### Tier 3: Directory listings

Batch-submit in one sitting.

| Directory | Notes |
|-----------|-------|
| AlternativeTo | List as alternative to Marked 2, Typora, MacDown |
| awesome-swift-macos-apps | PR to add |
| open-source-mac-os-apps | PR to add |
| awesome-native-macosx-apps | PR to add |
| awesome-markdown-editors | PR to add |
| Markdown Guide Tools | Submit for listing |
| Indie Dev Monday | Submit via form |
| iOS Dev Directory | Submit profile |
| opentosh.com | Submit for listing |

---

## Process Post Angles

The posts that perform on Reddit and HN are not "here's my app." They're "here's how I built this and what I learned." The app link lives at the bottom. Each platform gets a different angle from the same codebase.

| Angle | Best for | Hook |
|-------|----------|------|
| Why NSOutlineView over SwiftUI List | r/macapps, r/swift | "SwiftUI's OutlineGroup couldn't handle 500-file trees without freezing" |
| Zero dependencies by choice | HN, r/macapps | "I wrote my own regex syntax highlighter instead of pulling in a library" |
| Apple Foundation Models in a real app | r/ClaudeAI, r/swift | "The 4096-token context window means you auto-reset after 3 Q&A turns" |
| DispatchSource file watching | HN, Dev.to | "I needed to know when Claude Code wrote to a file — without polling" |
| The deliberate decision not to edit | HN, r/macapps | "A reader and an editor are different tools. I built the wrong one first." |
| Swift 6.2 strict concurrency | r/swift, r/iOSProgramming | "Every delegate callback is nonisolated. MainActor.assumeIsolated saved the app." |
| Security-scoped bookmarks in a sandbox | Dev.to, r/swift | "macOS sandbox means you lose folder access on relaunch. Bookmarks fix that." |

---

## Post Drafts

### r/vibecoding

**Title:** My Claude Code workflow generates so many markdown files that I built an app just to read them

My Claude Code workflow generates a ton of markdown files, so I built an app optimized for reading a project's markdown files.

You can open or drag a folder onto the dock icon or window and it shows the full file tree, filtered to only markdown files, so you can easily browse between them. When your AI tool writes to a file you have open, a reload pill pops up so you see the change without switching windows.

I released 1.0 a couple weeks ago and just shipped a 2.0 update with themes, bookmarks, quick file switcher, search and a bunch of other features. If you're on macOS 26, it has local AI chat with Apple Foundation Models (kinda bad right now, but hoping AFMs improve once the Gemini integration launches).

I'm also making the app open source so you can check out the code here: [GitHub link]

Mac App Store: [link]

---

I'm a product marketer that's studied some code and done technical project management in the past. Using agents and a few Claude plug-ins I've recreated a simple technical project process using agents:

- I made a custom plugin's bash skill that runs a "meeting" between me and appropriate agents (UX/UI experts, software architects, etc). The end product of this is a BRD.md file.
- We use that BRD as a basis for a Lisa interview that generates user stories.
- Then, I use Ralph Loops to actually write the code.

In between each step, I have other plugins and agents: an adversarial reviewer called Bart (to stay on theme) and I use Axiom's amazing iOS/macOS plugins to review the code.

Hope the community finds this useful! Are you struggling with the deluge of markdowns like I am?

[Hero screenshot or live reload GIF]

---

### r/macapps

**Title:** Why I used NSOutlineView instead of SwiftUI List for a file browser — and what I learned building a markdown reader with zero dependencies

I needed a sidebar that could handle a folder tree with hundreds of files — expand, collapse, drag and drop, right-click context menus. SwiftUI's `OutlineGroup` renders the entire tree upfront. At ~500 items it stutters visibly. NSOutlineView lazy-loads and has been battle-tested for 20 years.

So I wrapped it in `NSViewRepresentable` and built the rest of the app in SwiftUI. That pattern — SwiftUI for layout, AppKit where it needs to be fast — ended up defining the whole architecture. The markdown renderer is `NSTextView` with a custom regex-based highlighter (no dependencies). File watching is `DispatchSource` (no polling). Even the syntax themes are hand-rolled — 7 families, light/dark variants.

The app is a markdown reader for AI-generated docs. Every Claude Code / Cursor session dumps specs and changelogs into a `docs/` folder. I needed a way to browse and read them without opening VS Code. So I built one: folder tree sidebar, live file watching (a reload pill when the file changes on disk), Cmd+P quick switcher, on-device AI Q&A via Apple Foundation Models.

It's called Pixley Reader. Free, open source, zero external dependencies.

Mac App Store: [link]
GitHub: [link]

**First comment:** Developer here — happy to talk about the NSOutlineView wrapping, the regex highlighter, or any other architectural choices. Swift 6.2, macOS 15+ (AI chat needs macOS 26 Tahoe).

---

### Hacker News (Show HN)

**Title:** Show HN: Pixley Reader — A macOS markdown reader with zero dependencies (open source)

**URL:** GitHub

**First comment (within 5 min):**

I built this because AI coding tools (Claude Code, Cursor) generate a lot of markdown — specs, docs, changelogs — and there wasn't a good way to just *read* them.

The interesting technical constraint: zero external dependencies. The syntax highlighter is regex-based (7 theme families, light/dark). The file watcher uses `DispatchSource`, not polling. The sidebar is `NSOutlineView` wrapped in SwiftUI because `OutlineGroup` chokes on large trees. The AI Q&A uses Apple Foundation Models, which has a 4096-token context window — so I auto-reset the session after 3 turns and truncate documents to ~2500 chars.

Tradeoffs I'm aware of: regex highlighting breaks on nested constructs (a code block inside a blockquote). NSOutlineView inside NSViewRepresentable means bridging two worlds of state management. The AI integration only works on macOS 26 Tahoe — everything else runs on macOS 15.

Source: [GitHub link]

Happy to discuss architecture. The AppCoordinator pattern (decomposed state containers observed via SwiftUI Environment) might be interesting to anyone wrestling with state management in a multi-window app.

---

### r/ClaudeAI

**Title:** How I handle the `docs/` folder Claude Code generates — built a dedicated reader with live file watching

Every Claude Code session adds to my `docs/` folder — specs, changelogs, architecture docs. After a few weeks I had 30+ markdown files and no good way to browse them. VS Code buries them among source files. Finder's Quick Look doesn't do syntax highlighting.

The specific problem I wanted to solve: when Claude Code writes to a file I'm reading, I want to know immediately without switching windows. So I built a file watcher using `DispatchSource` — a reload pill appears the moment the file changes on disk.

I also added Apple Foundation Models for on-device Q&A. You can ask "what error cases does this spec handle?" about the document you're reading. The catch: Apple FM has a 4096-token context window, so I truncate documents to ~2500 chars and auto-reset the session after 3 turns. It's useful for quick questions, not deep analysis.

The app is called Pixley Reader. Free, open source, native macOS.

Mac App Store: [link]

Curious how other people handle their growing pile of Claude-generated docs — I can't be the only one drowning in specs.

---

### r/CursorAI

**Title:** Built a file watcher that tells me when Cursor writes to a markdown file — turned it into a full reader app

Cursor generates markdown alongside your code — specs, README updates, docs. I kept switching between the editor and various preview panes trying to read what the AI wrote.

The core thing I wanted: know when a file changed on disk without polling. `DispatchSource.makeFileSystemObjectSource` fires the moment the file is modified. I show a reload pill — tap it to refresh.

Built the rest around that: folder tree sidebar, Cmd+P quick switcher, syntax highlighting with 7 themes, on-device AI Q&A (Apple Foundation Models, macOS 26 — the rest works on macOS 15+). Zero external dependencies, everything hand-rolled.

Called it Pixley Reader. Free, open source.

Mac App Store: [link]

---

### Product Hunt

**Tagline:** Read the markdown files your AI tools write

**Description:**

Pixley Reader is a native macOS app for reading markdown files — especially the ones generated by AI coding tools like Claude Code, Cursor, and Copilot.

Point it at a folder and browse a hierarchical file tree. When an AI tool writes to a file you're reading, a reload pill tells you something changed. Quick Switcher (Cmd+P) for fast navigation. 7 syntax themes. On-device AI Q&A powered by Apple Foundation Models.

Not an editor. Not a note-taking app. Just a clean, fast way to read AI-generated documentation.

Free. Open source. Zero external dependencies.

**Maker's first comment:**

Hi — I'm [name], the developer.

AI coding tools generate an enormous amount of markdown, and there was no good way to just read it. I needed a reader, not an editor — so I built one with no external dependencies. The syntax highlighter is regex-based, the file watcher uses DispatchSource, the sidebar wraps NSOutlineView because SwiftUI's OutlineGroup couldn't handle large trees.

AI Q&A runs entirely on-device (Apple Foundation Models, macOS 26 Tahoe). Everything else works on macOS 15+. Free and open source.

How do you handle the growing pile of AI-generated docs in your workflow?

---

### Twitter/X Thread

**Tweet 1 (hook):**
I built a macOS markdown reader with zero external dependencies. Here's what I learned.

[Hero screenshot]

**Tweet 2 (why):**
AI coding tools generate tons of markdown — specs, docs, changelogs. I had 30+ files in a `docs/` folder and no good way to browse them.

VS Code buries them among source files. I needed a reader, not an editor.

**Tweet 3 (interesting decision):**
The sidebar uses NSOutlineView, not SwiftUI List.

SwiftUI's OutlineGroup renders everything upfront. At 500 files it stutters. NSOutlineView lazy-loads. 20 years of battle-testing wins.

Wrapped it in NSViewRepresentable. That pattern defined the whole app.

**Tweet 4 (demo):**
The file watcher uses DispatchSource — fires the moment the file changes on disk.

When Claude Code writes to a file you're reading, a reload pill appears instantly. No polling.

[Live reload GIF]

**Tweet 5 (CTA):**
Pixley Reader. Free, open source, native SwiftUI + AppKit.

Mac App Store: [link]
Source: [GitHub link]

#BuildInPublic #SwiftUI

---

### Mastodon

Built a macOS markdown reader for AI-generated docs with zero external dependencies. Some things I learned:

- NSOutlineView over SwiftUI OutlineGroup (lazy loading matters at 500+ files)
- DispatchSource for file watching — fires instantly, no polling
- Apple Foundation Models has a 4096-token context window — auto-reset after 3 turns
- Regex-based syntax highlighting with 7 theme families

Free, open source, native SwiftUI + AppKit.

Source: [GitHub link]
Mac App Store: [link]

#SwiftUI #macOS #OpenSource #IndieDev #SwiftDev

---

### Dev.to

**Title:** Why I wrote my own syntax highlighter instead of using a library — building a macOS markdown reader with zero dependencies

**Angle:** The technical journey of building a real macOS app without pulling in any SPM packages. Cover: why regex highlighting (and where it breaks), NSOutlineView vs SwiftUI List, DispatchSource file watching, Apple Foundation Models' context limits, security-scoped bookmarks. Honest about tradeoffs. Link to source at the end.

---

### r/swift / r/iOSProgramming

**Title:** Every NSTextViewDelegate method is nonisolated — here's how I handled Swift 6.2 strict concurrency in a real macOS app

The hardest part of building my SwiftUI + AppKit markdown reader wasn't the UI — it was Swift 6.2's strict concurrency checking.

`NSTextViewDelegate` methods are `nonisolated`. But they're always called on the main thread. `MainActor.assumeIsolated` bridges the gap. Same pattern for `NSView.boundsDidChangeNotification` scroll tracking.

Other patterns that came up:
- `AppCoordinator` as `@MainActor @Observable` with decomposed state containers (NavigationState, UIState, DocumentState)
- `Task.detached` for file I/O to avoid blocking the main actor
- `nonisolated(unsafe) let` for capturing `notification.object` before entering `MainActor.assumeIsolated`
- Security-scoped bookmarks — the sandbox forgets folder access on relaunch

The app is Pixley Reader, a markdown reader for AI-generated docs. Open source.

GitHub: [link]

Happy to discuss any of these patterns.

---

## Prepared Rebuttals

### "Why not just use VS Code?"

> VS Code is great for editing code. For reading markdown, it has friction: preview pane competes with your editor, markdown files get buried alongside source files, no folder-browsing mode for docs. Pixley Reader is purpose-built for reading, the way a book reader is different from a word processor. If you're happy with VS Code's preview, you don't need this.

### "Why not Obsidian?"

> Obsidian is for *your* notes — vault model, linking, graph view, plugins. Pixley Reader is for reading *other people's* output (specifically AI output). No vault, no config, no plugins. Open a folder, read. Different jobs.

### "Why not Marked 2?"

> Marked 2 previews a single file alongside your editor. Pixley Reader is a standalone reader with folder browsing, file tree, Quick Switcher, and AI Q&A — built for navigating a collection of documents. Marked 2 is $14; Pixley Reader is free and open source.

### "macOS only? Pass."

> Fair. Native macOS app, no cross-platform plans. I chose to build a great Mac app rather than a mediocre cross-platform one.

### "This is just a markdown previewer with fewer features."

> Fewer features than a general-purpose editor because it's a reader, not an editor. Browse folders, read markdown, watch for changes, ask AI about what you're reading. That's the product. The question isn't "does it have more features than Obsidian" — it's "does it do this one job well."

---

## Timing and Sequencing

One platform per day. Be available to respond to comments.

### Prep (Days -7 to -1)

- [ ] Create all visual assets
- [ ] Confirm GitHub repo live, README clean
- [ ] Verify Mac App Store link
- [ ] Product Hunt: create profile 2+ weeks early, engage authentically
- [ ] Draft Dev.to article
- [ ] Prepare all post texts

### Week 1

| Day | Platform | Notes |
|-----|----------|-------|
| Tue | r/macapps | Warmup. Friendly audience. Respond to every comment. |
| Wed | Hacker News | 8-9 AM EST. Be in comments all day. Highest leverage. |
| Thu | r/vibecoding | Process post. Lead with Lisa/Ralph workflow. |
| Fri | r/ClaudeAI | Ride any HN/vibecoding momentum. |
| Sat | r/CursorAI | |

### Week 2

| Day | Platform | Notes |
|-----|----------|-------|
| Sat/Sun | Product Hunt | 12:01 AM PST. Weekend launch. |
| Mon-Tue | Twitter/X + Mastodon | Can go same day. |
| Wed | r/SideProject | |
| Thu | r/swift + r/iOSProgramming | |

### Week 3

| Day | Platform | Notes |
|-----|----------|-------|
| Day 15 | Dev.to article | |
| Day 15-20 | Tier 3 directories | Batch in one sitting. |
| Day 20+ | Indie Dev Monday, iOS Dev Weekly | |

### Ongoing

- Share discussion links on Twitter/Mastodon if posts gain traction (don't ask for upvotes)
- Ship improvements from feedback, post updates in original threads
- Amplify any external coverage

---

## What Not to Do

- **r/LocalLLaMA** — Apple FM is closed-source and non-configurable. This community values open weights. Framing it as "privacy-first local AI" will backfire.
- **r/apple** — Rule 8 prohibits self-promotion. Post removed, account flagged.
- **Don't overclaim** — No "search within documents" (doesn't exist). No "10+ themes" (7 families, 10 variants). Match the shipped app.
- **Don't bury the macOS 26 requirement** — State in every post: "AI Q&A requires macOS 26 Tahoe; everything else works on macOS 15+."
- **Don't write for beginners** — Your audience are working developers. Peer-to-peer.
- **Don't post if GitHub is broken** — 404 kills credibility. Use App Store link only if repo isn't ready.
- **Don't crosspost identical text** — Each post is tailored to that community.

---

## Success Metrics

Free, niche, macOS-only tool. "Success" is not going viral.

**Good:** r/macapps 50-150 upvotes. HN 20-50 points. r/ClaudeAI 30-80. Product Hunt 50-100, top 10. GitHub 50-200 stars.

**Great:** HN front page 4+ hours. Reddit post crosses 200. PH top 5. Newsletter mention. GitHub 500+ stars.

**Failure is fine.** The app and repo are permanent. They accumulate attention through search and word of mouth.
