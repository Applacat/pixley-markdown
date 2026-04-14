import SwiftUI
import aimdRenderer

// MARK: - Settings Repository Protocol

/// Protocol defining access to application settings.
///
/// OOD Pattern: Repository abstraction separates setting storage from usage.
/// Views access settings through this protocol, not directly through @AppStorage.
/// This enables:
/// 1. Testability - mock settings in tests
/// 2. Migration - change storage mechanism without updating views
/// 3. Centralized defaults - all defaults defined in one place
@MainActor
public protocol SettingsRepository {
    /// Appearance-related settings
    var appearance: AppearanceSettings { get set }

    /// Markdown rendering settings
    var rendering: RenderingSettings { get set }

    /// Behavior and interaction settings
    var behavior: BehaviorSettings { get set }
}

// MARK: - Settings Containers (Pure Data)

/// Which direction Pixley faces in the app icon
public enum MascotDirection: String, CaseIterable, Identifiable, Sendable {
    case left = "Left"
    case right = "Right"

    public var id: String { rawValue }

    /// Asset catalog image name for this direction
    var assetName: String {
        switch self {
        case .left: return "PixleyLeft"
        case .right: return "PixleyRight"
        }
    }
}

/// Appearance settings (color scheme, theme).
/// Pure observable data — no persistence logic. Repository handles read/write.
@MainActor
@Observable
public final class AppearanceSettings {
    /// Color scheme preference (nil = follow system)
    public var colorScheme: ColorScheme? = nil

    /// Which direction the mascot faces in the Dock icon
    public var mascotDirection: MascotDirection = .left

    public init() {}
}

/// Markdown rendering settings.
/// Pure observable data — no persistence logic. Repository handles read/write.
@MainActor
@Observable
public final class RenderingSettings {
    /// Base font size in points
    public var fontSize: CGFloat = 14.0

    /// Font family name (nil = system default)
    public var fontFamily: String? = nil

    /// Syntax highlighting theme
    public var syntaxTheme: SyntaxThemeSetting = .xcode

    /// Heading size scale
    public var headingScale: HeadingScaleSetting = .normal

    /// Whether to show line numbers
    public var showLineNumbers: Bool = false

    public init() {}
}

/// Behavior settings (link handling, interactions).
/// Pure observable data — no persistence logic. Repository handles read/write.
@MainActor
@Observable
public final class BehaviorSettings {
    /// How to handle clicked links
    public var linkBehavior: LinkBehavior = .browser

    /// Whether to underline links
    public var underlineLinks: Bool = true

    /// Interactive element rendering mode
    public var interactiveMode: InteractiveMode = .enhanced

    public init() {}
}

/// Interactive element rendering mode
public enum InteractiveMode: String, CaseIterable, Identifiable, Sendable {
    /// Plain text rendering with interactive click targets
    case plain = "Plain"
    /// Native SwiftUI renderer with palette-styled blocks and native controls
    case enhanced = "Enhanced"

    public var id: String { rawValue }

    /// Short label for toolbar picker
    public var shortName: String {
        switch self {
        case .plain: return "Plain"
        case .enhanced: return "Enhanced"
        }
    }

    /// Icon for toolbar picker
    public var systemImage: String {
        switch self {
        case .plain: return "doc.plaintext"
        case .enhanced: return "doc.richtext"
        }
    }

    public var displayName: String {
        switch self {
        case .plain: return "Plain — minimal styling"
        case .enhanced: return "Enhanced — native controls, styled blocks"
        }
    }
}

// MARK: - Setting Types

/// Syntax theme family — user picks a family, light/dark variant auto-resolves from appearance.
public enum SyntaxThemeSetting: String, CaseIterable, Identifiable, Sendable {
    case xcode = "Xcode"
    case github = "GitHub"
    case solarized = "Solarized"
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case monokai = "Monokai"
    case nord = "Nord"

    public var id: String { rawValue }

    /// Whether this family has distinct light/dark variants
    public var hasLightVariant: Bool {
        switch self {
        case .xcode, .github, .solarized: return true
        case .oneDark, .dracula, .monokai, .nord: return false
        }
    }

    /// Resolves the concrete aimdRenderer theme based on current appearance.
    /// Dark-only families always return their dark theme regardless of appearance.
    public func rendererTheme(isDark: Bool) -> SyntaxTheme {
        switch self {
        case .xcode:     return isDark ? .xcodeDark : .xcodeLight
        case .github:    return isDark ? .githubDark : .githubLight
        case .solarized: return isDark ? .solarizedDark : .solarizedLight
        case .oneDark:   return .oneDark
        case .dracula:   return .dracula
        case .monokai:   return .monokai
        case .nord:      return .nord
        }
    }

    /// Convenience: resolve from a ColorScheme (nil = follow system appearance).
    /// Must be called from MainActor when colorScheme is nil (system detection requires NSApp).
    @MainActor
    public func rendererTheme(for colorScheme: ColorScheme?) -> SyntaxTheme {
        let isDark: Bool
        if let scheme = colorScheme {
            isDark = scheme == .dark
        } else {
            #if os(macOS)
            isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            #else
            // Fallback: assume light if no colorScheme provided (callers should pass one)
            isDark = false
            #endif
        }
        return rendererTheme(isDark: isDark)
    }

    // MARK: - Migration from old per-variant raw values

    /// Initializes from legacy raw values ("Xcode Dark", "GitHub Light", etc.)
    public init(migrating rawValue: String) {
        switch rawValue {
        case "Xcode Light", "Xcode Dark": self = .xcode
        case "GitHub Light", "GitHub Dark": self = .github
        case "Solarized Light", "Solarized Dark": self = .solarized
        case "One Dark": self = .oneDark
        case "Dracula": self = .dracula
        case "Monokai": self = .monokai
        case "Nord": self = .nord
        default: self = Self(rawValue: rawValue) ?? .xcode
        }
    }
}

/// Heading scale options
public enum HeadingScaleSetting: String, CaseIterable, Identifiable, Sendable {
    case compact
    case normal
    case spacious

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .spacious: return "Spacious"
        }
    }

    #if os(macOS)
    /// Converts to the MarkdownHighlighter's HeadingScale enum
    var highlighterScale: MarkdownHighlighter.HeadingScale {
        switch self {
        case .compact: return .compact
        case .normal: return .normal
        case .spacious: return .spacious
        }
    }
    #endif
}

/// Link behavior options
public enum LinkBehavior: String, CaseIterable, Identifiable, Sendable {
    case browser
    case inApp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .browser: return "Open in Browser"
        case .inApp: return "Open in App"
        }
    }
}

// MARK: - Settings Keys

enum SettingsKey: String {
    case colorScheme
    case mascotDirection
    case fontSize
    case fontFamily
    case syntaxTheme
    case headingScale
    case showLineNumbers
    case linkBehavior
    case underlineLinks
    case interactiveMode
}

// MARK: - UserDefaults Implementation

/// Default implementation using UserDefaults for persistence.
/// This is the only type that touches UserDefaults for settings.
/// It loads saved values on init and persists changes via didSet observers.
@MainActor
@Observable
public final class UserDefaultsSettingsRepository: SettingsRepository {
    public var appearance: AppearanceSettings {
        didSet { persistAppearance() }
    }
    public var rendering: RenderingSettings {
        didSet { persistRendering() }
    }
    public var behavior: BehaviorSettings {
        didSet { persistBehavior() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Create pure-data containers
        let appearance = AppearanceSettings()
        let rendering = RenderingSettings()
        let behavior = BehaviorSettings()

        // Load persisted values into containers
        if let raw = defaults.string(forKey: SettingsKey.colorScheme.rawValue) {
            appearance.colorScheme = raw == "dark" ? .dark : .light
        }
        let directionRaw = defaults.string(forKey: SettingsKey.mascotDirection.rawValue) ?? MascotDirection.left.rawValue
        appearance.mascotDirection = MascotDirection(rawValue: directionRaw) ?? .left

        rendering.fontSize = defaults.object(forKey: SettingsKey.fontSize.rawValue) as? CGFloat ?? 14.0
        rendering.fontFamily = defaults.string(forKey: SettingsKey.fontFamily.rawValue)
        let themeRaw = defaults.string(forKey: SettingsKey.syntaxTheme.rawValue) ?? SyntaxThemeSetting.xcode.rawValue
        rendering.syntaxTheme = SyntaxThemeSetting(rawValue: themeRaw) ?? SyntaxThemeSetting(migrating: themeRaw)
        let scaleRaw = defaults.string(forKey: SettingsKey.headingScale.rawValue) ?? HeadingScaleSetting.normal.rawValue
        rendering.headingScale = HeadingScaleSetting(rawValue: scaleRaw) ?? .normal
        rendering.showLineNumbers = defaults.bool(forKey: SettingsKey.showLineNumbers.rawValue)

        let linkRaw = defaults.string(forKey: SettingsKey.linkBehavior.rawValue) ?? LinkBehavior.browser.rawValue
        behavior.linkBehavior = LinkBehavior(rawValue: linkRaw) ?? .browser
        if defaults.object(forKey: SettingsKey.underlineLinks.rawValue) == nil {
            behavior.underlineLinks = true
        } else {
            behavior.underlineLinks = defaults.bool(forKey: SettingsKey.underlineLinks.rawValue)
        }
        let modeRaw = defaults.string(forKey: SettingsKey.interactiveMode.rawValue) ?? InteractiveMode.enhanced.rawValue
        // Migration: "Hybrid" and "Liquid Glass" resolve to Enhanced
        behavior.interactiveMode = InteractiveMode(rawValue: modeRaw) ?? .enhanced

        self.appearance = appearance
        self.rendering = rendering
        self.behavior = behavior

        // Start observing changes for persistence
        startObserving()
    }

    /// Shared instance for convenience
    public static let shared = UserDefaultsSettingsRepository()

    // MARK: - Persistence

    private func persistAppearance() {
        if let scheme = appearance.colorScheme {
            defaults.set(scheme == .dark ? "dark" : "light", forKey: SettingsKey.colorScheme.rawValue)
        } else {
            defaults.removeObject(forKey: SettingsKey.colorScheme.rawValue)
        }
        defaults.set(appearance.mascotDirection.rawValue, forKey: SettingsKey.mascotDirection.rawValue)
    }

    private func persistRendering() {
        defaults.set(rendering.fontSize, forKey: SettingsKey.fontSize.rawValue)
        if let family = rendering.fontFamily {
            defaults.set(family, forKey: SettingsKey.fontFamily.rawValue)
        } else {
            defaults.removeObject(forKey: SettingsKey.fontFamily.rawValue)
        }
        defaults.set(rendering.syntaxTheme.rawValue, forKey: SettingsKey.syntaxTheme.rawValue)
        defaults.set(rendering.headingScale.rawValue, forKey: SettingsKey.headingScale.rawValue)
        defaults.set(rendering.showLineNumbers, forKey: SettingsKey.showLineNumbers.rawValue)
    }

    private func persistBehavior() {
        defaults.set(behavior.linkBehavior.rawValue, forKey: SettingsKey.linkBehavior.rawValue)
        defaults.set(behavior.underlineLinks, forKey: SettingsKey.underlineLinks.rawValue)
        defaults.set(behavior.interactiveMode.rawValue, forKey: SettingsKey.interactiveMode.rawValue)
    }

    /// Debounced persist task — coalesces rapid settings changes (e.g., font-size stepper)
    private var settingsPersistTask: Task<Void, Never>?

    private func schedulePersist(_ work: @escaping @MainActor () -> Void) {
        settingsPersistTask?.cancel()
        settingsPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, self != nil else { return }
            work()
        }
    }

    /// Observes property changes on settings containers and persists them.
    /// Uses withObservationTracking to re-arm after each change.
    private func startObserving() {
        observeAppearance()
        observeRendering()
        observeBehavior()
    }

    private func observeAppearance() {
        withObservationTracking {
            _ = appearance.colorScheme
            _ = appearance.mascotDirection
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.schedulePersist { self.persistAppearance() }
                self.observeAppearance()
            }
        }
    }

    private func observeRendering() {
        withObservationTracking {
            _ = rendering.fontSize
            _ = rendering.fontFamily
            _ = rendering.syntaxTheme
            _ = rendering.headingScale
            _ = rendering.showLineNumbers
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.schedulePersist { self.persistRendering() }
                self.observeRendering()
            }
        }
    }

    private func observeBehavior() {
        withObservationTracking {
            _ = behavior.linkBehavior
            _ = behavior.underlineLinks
            _ = behavior.interactiveMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.schedulePersist { self.persistBehavior() }
                self.observeBehavior()
            }
        }
    }

}

// MARK: - Environment Key

/// Environment key for accessing settings repository
/// Note: Returns concrete type for SwiftUI Environment compatibility
// @preconcurrency required: EnvironmentKey.defaultValue lacks @MainActor annotation.
// Safe because SwiftUI accesses this on @MainActor view update path.
private struct SettingsRepositoryKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = UserDefaultsSettingsRepository.shared
}

extension EnvironmentValues {
    @MainActor
    public var settings: UserDefaultsSettingsRepository {
        get { self[SettingsRepositoryKey.self] }
        set { self[SettingsRepositoryKey.self] = newValue }
    }
}

