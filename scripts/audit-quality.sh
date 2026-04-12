#!/bin/bash
# Code quality audit script for cross-platform files.
# Checks: line length, commented-out code, raw UserDefaults key strings.
# Exit 0 = all checks pass, non-zero = issues found.

set -euo pipefail
cd "$(dirname "$0")/.."

CROSS_PLATFORM_DIRS=(
    "Sources/Views/NativeRenderer"
    "Sources/Services"
    "Sources/Coordinator"
    "Sources/Settings"
    "Sources/Models"
)

CROSS_PLATFORM_FILES=(
    "Sources/Views/Screens/MarkdownView.swift"
    "Sources/Views/Screens/ChatView.swift"
    "Sources/Views/Screens/StartView.swift"
    "Sources/Views/Screens/SettingsView.swift"
    "Sources/Views/Components/QuickSwitcher.swift"
    "Sources/Views/Components/ErrorBanner.swift"
    "Sources/AIMDReaderApp.swift"
    "Sources/ContentView.swift"
    "Sources/BrowserWindowRoot.swift"
    "Sources/Prompts.swift"
    "Sources/InteractiveAnnotator.swift"
)

FAILURES=0

# Build grep target list
TARGETS=()
for dir in "${CROSS_PLATFORM_DIRS[@]}"; do
    [ -d "$dir" ] && TARGETS+=("$dir")
done
for file in "${CROSS_PLATFORM_FILES[@]}"; do
    [ -f "$file" ] && TARGETS+=("$file")
done

echo "=== Code Quality Audit ==="
echo ""

# Check 1: Lines >150 characters
echo "--- Check 1: Lines >150 characters ---"
LONG_LINES=$(grep -rn '.\{151,\}' "${TARGETS[@]}" --include="*.swift" 2>/dev/null || true)
if [ -n "$LONG_LINES" ]; then
    echo "FAIL: Found lines exceeding 150 characters:"
    echo "$LONG_LINES"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: No lines exceed 150 characters"
fi
echo ""

# Check 2: Commented-out code (heuristic: lines starting with // followed by Swift keywords)
echo "--- Check 2: Commented-out code ---"
COMMENTED_CODE=$(grep -rEn '^\s*//\s*(let |var |func |return |self\.|guard |if let |@State|@Binding|await |\.onChange|\.onAppear|print\()' \
    "${TARGETS[@]}" --include="*.swift" 2>/dev/null \
    | grep -v '/// ' | grep -v '// MARK' || true)
if [ -n "$COMMENTED_CODE" ]; then
    echo "WARN: Possible commented-out code (review manually):"
    echo "$COMMENTED_CODE"
else
    echo "PASS: No commented-out code detected"
fi
echo ""

# Check 3: TODO/FIXME markers
echo "--- Check 3: TODO/FIXME markers ---"
TODOS=$(grep -rEn '// TODO|// FIXME|// HACK|// XXX' "${TARGETS[@]}" --include="*.swift" 2>/dev/null || true)
if [ -n "$TODOS" ]; then
    echo "WARN: Found TODO/FIXME markers:"
    echo "$TODOS"
else
    echo "PASS: No TODO/FIXME markers"
fi
echo ""

# Check 4: Raw UserDefaults key strings in SettingsRepository
echo "--- Check 4: Raw UserDefaults key strings ---"
RAW_KEYS=$(grep -n 'forKey: "' Sources/Settings/SettingsRepository.swift 2>/dev/null || true)
if [ -n "$RAW_KEYS" ]; then
    echo "FAIL: Found raw UserDefaults key strings (should use SettingsKey enum):"
    echo "$RAW_KEYS"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: No raw UserDefaults key strings"
fi
echo ""

# Check 5: Inline triple-quoted prompts in service files
echo "--- Check 5: Inline AI prompts ---"
INLINE_PROMPTS=$(grep -n '"""' Sources/Services/TranscriptCondenser.swift Sources/Services/ChatService.swift 2>/dev/null || true)
if [ -n "$INLINE_PROMPTS" ]; then
    echo "WARN: Found triple-quoted strings in service files (check if prompts):"
    echo "$INLINE_PROMPTS"
else
    echo "PASS: No inline prompts in service files"
fi
echo ""

# Summary
echo "=== Summary ==="
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
else
    echo "ALL CHECKS PASSED"
    exit 0
fi
