# Pre-Release Audit Fixes

**Feature:** Fix audit blockers and recommended issues before first public release
**App:** AI.md Reader
**Created:** 2026-02-04
**Status:** Ready for Implementation

---

## Overview

Following comprehensive pre-release audits (security, storage, concurrency, memory, energy, swift-performance), this spec addresses the identified blockers and recommended fixes required before shipping v1.0.

### Audit Summary

| Audit | CRITICAL | HIGH | MEDIUM | LOW | Action |
|-------|----------|------|--------|-----|--------|
| Security | 1 | 2 | 2 | 1 | **FIX** |
| Storage | 2 | 3 | 3 | 2 | **FIX** |
| Concurrency | 0 | 0 | 1 | 2 | **FIX** |
| Memory | 0 | 0 | 0 | 1 | **FIX** |
| Swift Performance | 0 | 3 | 4 | 2 | Ship as-is |
| Energy | 0 | 0 | 0 | 5 | Ship as-is |

---

## Scope

### In Scope (5 fixes)

1. **Privacy Manifest** (CRITICAL) - App Store submission blocker
2. **Welcome folder storage** (CRITICAL) - Data loss risk
3. **Debouncer weak self** (MEDIUM) - Potential retain cycle
4. **Sendable conformances** (LOW) - Swift 6 clarity
5. **Cache backup exclusion** (HIGH) - Backup bloat prevention

### Out of Scope

- Swift performance HIGH issues (all background-threaded or tiny data)
- Energy LOW issues (app rated "exemplary")
- Any UI/UX changes
- Feature additions

---

## User Stories

### US-1: Create Privacy Manifest

**Priority:** CRITICAL (App Store blocker)
**Effort:** 5 minutes

Create `PrivacyInfo.xcprivacy` declaring required reason APIs.

**Background:**
The app uses `UserDefaults` (9 usages) and `FileManager.contentsOfDirectory` which require privacy declarations per Apple's Required Reason API policy.

**Implementation:**

Create file at `Resources/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Update `Package.swift` to include in resources.

**Acceptance Criteria:**
- [ ] File exists at `Resources/PrivacyInfo.xcprivacy`
- [ ] Declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`
- [ ] Declares `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`
- [ ] Package.swift includes file in resources
- [ ] Xcode build succeeds

---

### US-2: Move Welcome Folder to Application Support

**Priority:** CRITICAL (Data loss risk)
**Effort:** 15 minutes

Move Welcome folder from `tmp/` to `Application Support` to prevent system purging.

**Background:**
Currently, Welcome folder is copied to `FileManager.temporaryDirectory`. iOS/macOS can purge `tmp/` at any time, causing users to lose the tutorial unexpectedly.

**Design Decisions:**
- **Location:** `~/Library/Application Support/AIMDReader/Welcome/`
- **Copy strategy:** Copy once, check exists (faster launch, preserves user modifications)
- **Error handling:** Silent fallback with alert - don't crash, user can still use app

**Files to Modify:**
1. `Sources/AIMDReaderApp.swift` - `performFirstLaunch()`, cleanup logic
2. `Sources/Views/Screens/StartView.swift` - `openWelcomeFolder()`, `openWelcomeFolderWithPrompt()`

**Implementation Pattern:**

```swift
private var welcomeFolderURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("AIMDReader")
        .appendingPathComponent("Welcome")
}

private func ensureWelcomeFolder() -> URL? {
    guard let targetURL = welcomeFolderURL else { return nil }

    // Already exists - use it
    if FileManager.default.fileExists(atPath: targetURL.path) {
        return targetURL
    }

    // Copy from bundle
    guard let bundleURL = Bundle.main.url(forResource: "Welcome", withExtension: nil) else {
        return nil
    }

    do {
        let parentDir = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundleURL, to: targetURL)
        return targetURL
    } catch {
        return nil  // Silent fallback
    }
}
```

**Acceptance Criteria:**
- [ ] Welcome folder copied to `~/Library/Application Support/AIMDReader/Welcome/`
- [ ] Copy happens only if folder doesn't already exist
- [ ] First launch uses new location
- [ ] Mascot click (easter egg) uses new location
- [ ] Old tmp/ cleanup code removed or updated
- [ ] Error shows alert, doesn't crash app
- [ ] App launches successfully even if Welcome setup fails

---

### US-3: Fix Memory Safety Issues

**Priority:** MEDIUM
**Effort:** 5 minutes

Add `[weak self]` to debouncer Task and explicit Sendable conformances.

**Files to Modify:**
1. `Sources/MarkdownHighlighter.swift:196` - Add weak self
2. `Sources/Models/FolderItem.swift` - Add Sendable
3. `Sources/Models/ChatMessage.swift` - Add Sendable

**Implementation:**

```swift
// MarkdownHighlighter.swift - DebouncedHighlighter.highlightDebounced
debounceTask = Task { @MainActor [weak self] in
    guard self != nil else { return }  // Or just guard let self
    try? await Task.sleep(for: delay)
    guard !Task.isCancelled else { return }

    let result = highlighterRef.highlight(text)
    completion(result)
}

// FolderItem.swift
struct FolderItem: Identifiable, Hashable, Sendable { ... }

// ChatMessage.swift
struct ChatMessage: Identifiable, Sendable { ... }
```

**Acceptance Criteria:**
- [ ] `DebouncedHighlighter.highlightDebounced` uses `[weak self]` in Task
- [ ] `FolderItem` has explicit `Sendable` conformance
- [ ] `ChatMessage` has explicit `Sendable` conformance
- [ ] Build succeeds with no warnings

---

### US-4: Add Cache Backup Exclusion

**Priority:** HIGH
**Effort:** 5 minutes

Set `isExcludedFromBackup` on folder cache to prevent iCloud backup bloat.

**Background:**
The folder cache (`folder_cache.json`) can grow to 5-50MB. It's regenerable data that shouldn't be backed up to iCloud.

**File to Modify:**
`Sources/Services/FolderService.swift` - `saveCacheToDisk()`

**Implementation:**

```swift
private func saveCacheToDisk() {
    guard let url = cacheFileURL else { return }

    // Ensure directory exists
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    if let data = try? JSONEncoder().encode(cache) {
        try? data.write(to: url)

        // Exclude from backup - this is regenerable cache data
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }
}
```

**Acceptance Criteria:**
- [ ] `folder_cache.json` has `isExcludedFromBackup = true` after write
- [ ] Cache functionality unchanged (load/save/invalidate work correctly)
- [ ] Build succeeds

---

## Verification Plan

### Build Verification
1. Open `AIMDReader.xcodeproj` in Xcode
2. Build for macOS (Cmd+B)
3. Verify no errors or warnings

### Manual Testing
1. **First Launch Test:**
   - Delete app data: `rm -rf ~/Library/Application\ Support/AIMDReader`
   - Launch app
   - Verify Welcome folder appears in Application Support
   - Verify tutorial loads correctly

2. **Mascot Click Test:**
   - From launcher, click the mascot image
   - Verify Welcome folder opens
   - Verify 01-Welcome.md loads

3. **Menu Bar Test:**
   - Verify menu bar shows "AI.md Reader"

4. **Cache Test:**
   - Open any folder
   - Check `~/Library/Application Support/AIMDReader/folder_cache.json`
   - Verify `xattr -l` shows backup exclusion

### Grep Verification
```bash
# Verify Privacy Manifest exists
ls Resources/PrivacyInfo.xcprivacy

# Verify no tmp/ Welcome references remain
grep -r "temporaryDirectory.*Welcome" Sources/

# Verify Sendable conformances
grep "struct FolderItem.*Sendable" Sources/
grep "struct ChatMessage.*Sendable" Sources/

# Verify weak self in debouncer
grep -A5 "highlightDebounced" Sources/MarkdownHighlighter.swift | grep "weak self"
```

---

## Implementation Order

1. **US-1: Privacy Manifest** (independent, quick win)
2. **US-4: Cache Backup Exclusion** (independent, quick win)
3. **US-3: Memory Safety** (independent, quick win)
4. **US-2: Welcome Folder Storage** (largest change, do last)

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `Resources/PrivacyInfo.xcprivacy` | NEW - Privacy manifest |
| `Package.swift` | Add PrivacyInfo to resources |
| `Sources/AIMDReaderApp.swift` | Welcome folder location change |
| `Sources/Views/Screens/StartView.swift` | Welcome folder location change |
| `Sources/MarkdownHighlighter.swift` | Add [weak self] |
| `Sources/Models/FolderItem.swift` | Add Sendable |
| `Sources/Models/ChatMessage.swift` | Add Sendable |
| `Sources/Services/FolderService.swift` | Add backup exclusion |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Welcome folder migration breaks existing users | Copy-once strategy means existing installs unaffected |
| Privacy Manifest incorrect | Use exact API reasons from Apple documentation |
| Backup exclusion causes data loss | Cache is regenerable, no user data |

---

## Success Criteria

- [ ] Xcode build succeeds with no errors
- [ ] App launches and shows Welcome tutorial
- [ ] Menu bar shows "AI.md Reader"
- [ ] All grep verifications pass
- [ ] No crash on first launch or mascot click
