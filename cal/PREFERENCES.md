# Preferences — Infrastructure Stack

## Stack

- **Language:** Swift 6.2
- **UI:** SwiftUI (Enhanced mode = native renderer)
- **Platforms:** macOS 15+ (shipping), iOS 26+ (in progress), visionOS (planned)
- **Build:** XcodeGen (`project.yml` → `xcodegen generate`)
- **Dependencies:** swift-markdown (via aimdRenderer local package). No other external deps.
- **Persistence:** SwiftData for file metadata, UserDefaults for settings
- **AI:** Apple Foundation Models (on-device LLM via LanguageModelSession)
- **Tracking:** GitHub Issues + Projects

## Build Commands

```bash
cd AIMDReader && xcodegen generate
xcodebuild -scheme AIMDReader -configuration Debug build          # macOS
xcodebuild -scheme AIMDReader-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build  # iOS
```

## Critical Rules

- **Debug ARCHS:** arm64 only (project.yml per-config)
- **Release ARCHS:** [arm64, x86_64] universal (App Store requirement)
- **Never checkout project.pbxproj** to fix build errors
- **Always `xcodegen generate`** after changing project.yml
