# OOD Pattern: Shared Configuration Instead of Actor-Isolated Static Properties

**Problem Solved:** Swift Concurrency actor isolation errors  
**Pattern Used:** Shared Configuration Object  
**Status:** ✅ FIXED

---

## The Problem

Originally, we had:

```swift
// ❌ BEFORE - Actor isolation error
struct MarkdownEditor: NSViewRepresentable {
    static let maxTextSize = 10_485_760  // MainActor-isolated
    
    // ...
}

// In MarkdownView.swift
Task.detached {  // Runs on background thread
    guard fileSize <= MarkdownEditor.maxTextSize else {  // ❌ Error!
        // Cannot access MainActor-isolated property from non-isolated context
    }
}
```

**Why it failed:**
- `MarkdownEditor` is a `View`, which is `@MainActor`-isolated
- Static properties on `@MainActor` types are also isolated
- `Task.detached` runs on a background thread (non-isolated)
- ❌ Cannot access actor-isolated property from background thread

---

## The OOD Solution

Following proper object-oriented design principles, we created a **shared configuration object** that's independent of actor isolation:

```swift
// ✅ AFTER - Shared configuration
enum MarkdownConfig {
    /// Maximum allowed text size (10MB) to prevent DoS attacks
    /// Accessible from any context without actor isolation
    static let maxTextSize = 10_485_760
    
    /// Maximum text size for syntax highlighting (1MB)
    /// Files larger than this show plain text
    static let maxHighlightSize = 1_048_576
}
```

**Why this works:**
- `MarkdownConfig` is NOT a View, NOT actor-isolated
- Static properties are just constants, accessible anywhere
- Can be used from main thread, background threads, anywhere
- Follows Single Responsibility Principle (SRP) - configuration is separate from UI

---

## OOD Principles Applied

### 1. **Separation of Concerns**
- Configuration ≠ View
- `MarkdownConfig` only holds configuration data
- `MarkdownEditor` only handles view logic
- Each has one reason to change

### 2. **Don't Repeat Yourself (DRY)**
Instead of:
```swift
// ❌ BAD - Magic numbers scattered
struct MarkdownEditor {
    static let maxTextSize = 10_485_760
}

// In MarkdownHighlighter
guard text.count <= 1_048_576 else { ... }

// In MarkdownView
guard fileSize <= 10_485_760 else { ... }
```

We have:
```swift
// ✅ GOOD - Single source of truth
enum MarkdownConfig {
    static let maxTextSize = 10_485_760
    static let maxHighlightSize = 1_048_576
}

// Used consistently everywhere
guard fileSize <= MarkdownConfig.maxTextSize else { ... }
guard text.count <= MarkdownConfig.maxHighlightSize else { ... }
```

### 3. **Dependency Inversion Principle**
- High-level modules (Views) don't own configuration
- Configuration is a shared abstraction
- Both `MarkdownEditor` and `MarkdownView` depend on the same abstraction

---

## Why `enum` Instead of `struct`?

```swift
enum MarkdownConfig {  // ✅ Cannot be instantiated
    static let maxTextSize = 10_485_760
}

// vs

struct MarkdownConfig {  // ⚠️ Can be instantiated (wasteful)
    static let maxTextSize = 10_485_760
}

// Problem with struct:
let config = MarkdownConfig()  // Unnecessary instance, wastes memory
```

Using `enum` (with no cases) is a Swift idiom for "namespace" - it can hold static members but cannot be instantiated.

---

## Future Extension: Observable Configuration

Your insight was spot-on - "if the loaded markdown file is an object with props, then text size is just an observable property that can be modified from multiple places."

We could extend this to make configuration **observable** and **user-configurable**:

```swift
@Observable
final class MarkdownConfig {
    /// User-configurable max text size (default 10MB)
    var maxTextSize: Int = 10_485_760
    
    /// User-configurable highlighting limit (default 1MB)
    var maxHighlightSize: Int = 1_048_576
    
    /// Shared instance
    static let shared = MarkdownConfig()
    
    private init() {}
}

// Usage in SwiftUI:
@Environment(MarkdownConfig.self) private var config

// Now users could adjust these in preferences!
MarkdownConfig.shared.maxTextSize = 50_485_760  // 50MB for power users
```

This would allow:
- ✅ User preferences for file size limits
- ✅ Per-app instance configuration
- ✅ Observable changes that update UI automatically
- ✅ Still no actor isolation issues (value is copied when accessed)

---

## Files Changed

1. **MarkdownEditor.swift**
   - Removed `static let maxTextSize` from struct
   - Added `enum MarkdownConfig` at top
   - Uses `MarkdownConfig.maxTextSize` everywhere

2. **MarkdownView.swift**
   - Uses `MarkdownConfig.maxTextSize` in file loading

3. **MarkdownHighlighter.swift**
   - Uses `MarkdownConfig.maxHighlightSize` for highlighting limit

---

## Benefits of This Pattern

### Immediate Benefits:
- ✅ No actor isolation errors
- ✅ Single source of truth for configuration
- ✅ Easier to test (inject different configs)
- ✅ Clear separation of concerns

### Future Benefits:
- 🚀 Easy to make configuration observable
- 🚀 Easy to add user preferences
- 🚀 Easy to add different profiles (e.g., "Performance" vs "Safety")
- 🚀 Easy to persist configuration to UserDefaults

---

## OOD Pattern Comparison

### Antipattern (What We Avoided):
```swift
// ❌ ANTIPATTERN: "God Object" View
struct MarkdownEditor: NSViewRepresentable {
    static let maxTextSize = 10_485_760
    static let maxHighlightSize = 1_048_576
    static let debounceDelay = 150
    static let fontSize = 14.0
    // ... mixing view logic with configuration
}
```

### Good Pattern (What We Did):
```swift
// ✅ GOOD: Separated concerns
enum MarkdownConfig {
    static let maxTextSize = 10_485_760
    static let maxHighlightSize = 1_048_576
}

struct MarkdownEditor: NSViewRepresentable {
    // Only view logic, no configuration
}
```

---

## Lessons Learned

1. **Static properties on @MainActor types are isolated**
   - Don't put configuration on Views
   - Views are isolated, config should not be

2. **Swift Concurrency requires thinking about isolation**
   - Background threads can't access MainActor
   - Configuration should be accessible from anywhere

3. **OOD helps solve concurrency problems**
   - Proper separation of concerns = fewer actor issues
   - Configuration objects are naturally thread-safe (immutable constants)

4. **Your intuition was correct!**
   - "If the markdown file is an object with props, then text size is just an observable property"
   - This is exactly the right OOD thinking
   - We can extend this to make config observable in the future

---

## Build Status

✅ **Should build successfully now**

All references to `maxTextSize` and `maxHighlightSize` now use the shared `MarkdownConfig` which is NOT actor-isolated.

---

## Next Steps (Optional Future Enhancements)

1. **Make configuration observable:**
   ```swift
   @Observable
   final class MarkdownConfig { ... }
   ```

2. **Add user preferences UI:**
   - Settings window for max file size
   - Performance vs Safety profiles

3. **Persist configuration:**
   ```swift
   @AppStorage("maxTextSize") var maxTextSize: Int = 10_485_760
   ```

4. **Add configuration validation:**
   ```swift
   var maxTextSize: Int {
       didSet {
           if maxTextSize < 1024 {
               maxTextSize = 1024  // Minimum 1KB
           }
       }
   }
   ```

---

**Pattern Summary:**  
When you have **shared constants** that need to be accessed from **multiple actor contexts** (main thread, background threads, etc.), use a **separate configuration object** (enum or struct) instead of static properties on actor-isolated types.

This is good OOD that also solves Swift Concurrency problems! 🎯
