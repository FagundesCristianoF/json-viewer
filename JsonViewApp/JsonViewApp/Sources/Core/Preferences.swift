import Foundation
import Combine
import AppKit

enum AppTheme: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// Single source of truth for all persisted app preferences.
/// All UserDefaults access goes through here.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    // MARK: - Editor defaults

    static let defaultIndentSize = 2
    static let defaultEditorFontSize: Double = 13
    static let defaultUIFontSize: Double = 12

    // MARK: - Keys

    private enum Key {
        static let theme               = "appTheme"
        static let autoSave            = "autoSave"
        static let indentSize          = "indentSize"
        static let editorFontSize      = "editorFontSize"
        static let uiFontSize          = "uiFontSize"
        static let workspaceRoot       = "workspaceRoot"
        static let devKitMode          = "devKitMode"
        static let historyDirectory    = "historyDirectory"
        static let analytics           = "analytics"
        static let formatOnSave        = "formatOnSave"
        static let formatOnPaste       = "formatOnPaste"
    }

    // MARK: - Appearance

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Key.theme)
            applyAppearance()
        }
    }

    /// Drives the whole-app NSAppearance so the window chrome (toolbar +
    /// titlebar) switches with the theme. `.preferredColorScheme` only repaints
    /// the SwiftUI content — without this the toolbar keeps the old appearance
    /// and icons go low-contrast after an in-app theme switch.
    func applyAppearance() {
        let appearance: NSAppearance?
        switch theme {
        case .system: appearance = nil
        case .light:  appearance = NSAppearance(named: .aqua)
        case .dark:   appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
    }

    // MARK: - Editor

    @Published var autoSave: Bool {
        didSet { UserDefaults.standard.set(autoSave, forKey: Key.autoSave) }
    }

    @Published var formatOnSave: Bool {
        didSet { UserDefaults.standard.set(formatOnSave, forKey: Key.formatOnSave) }
    }

    @Published var formatOnPaste: Bool {
        didSet { UserDefaults.standard.set(formatOnPaste, forKey: Key.formatOnPaste) }
    }

    @Published var indentSize: Int {
        didSet { UserDefaults.standard.set(indentSize, forKey: Key.indentSize) }
    }

    @Published var editorFontSize: Double {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: Key.editorFontSize) }
    }

    @Published var uiFontSize: Double {
        didSet { UserDefaults.standard.set(uiFontSize, forKey: Key.uiFontSize) }
    }

    // MARK: - Privacy

    @Published var analytics: Bool {
        didSet { UserDefaults.standard.set(analytics, forKey: Key.analytics) }
    }

    // MARK: - History / Collection folder

    /// Default: ~/Library/Application Support/Brace/
    static var defaultHistoryDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent("Brace", isDirectory: true)
    }

    @Published var historyDirectory: URL {
        didSet {
            UserDefaults.standard.set(
                historyDirectory.path, forKey: Key.historyDirectory
            )
            ensureHistoryDirectoryExists()
        }
    }

    // MARK: - Init

    private init() {
        // theme — migrate legacy darkMode bool if present, default .system
        if let raw = UserDefaults.standard.string(forKey: Key.theme),
           let saved = AppTheme(rawValue: raw) {
            theme = saved
        } else if UserDefaults.standard.object(forKey: "darkMode") != nil {
            theme = UserDefaults.standard.bool(forKey: "darkMode") ? .dark : .light
        } else {
            theme = .system
        }

        // autoSave — default true
        let savedAutoSave = UserDefaults.standard.object(forKey: Key.autoSave)
        autoSave = savedAutoSave != nil ? UserDefaults.standard.bool(forKey: Key.autoSave) : true

        // formatOnSave — default false
        let savedFormatOnSave = UserDefaults.standard.object(forKey: Key.formatOnSave)
        formatOnSave = savedFormatOnSave != nil ? UserDefaults.standard.bool(forKey: Key.formatOnSave) : false

        // formatOnPaste — default false
        let savedFormatOnPaste = UserDefaults.standard.object(forKey: Key.formatOnPaste)
        formatOnPaste = savedFormatOnPaste != nil ? UserDefaults.standard.bool(forKey: Key.formatOnPaste) : false

        // indentSize — default 2
        let savedIndent = UserDefaults.standard.integer(forKey: Key.indentSize)
        indentSize = savedIndent > 0 ? savedIndent : Self.defaultIndentSize

        // editorFontSize — default 13
        let savedEditor = UserDefaults.standard.double(forKey: Key.editorFontSize)
        editorFontSize = savedEditor > 0 ? savedEditor : Self.defaultEditorFontSize

        // uiFontSize — default 12
        let savedUI = UserDefaults.standard.double(forKey: Key.uiFontSize)
        uiFontSize = savedUI > 0 ? savedUI : Self.defaultUIFontSize

        // analytics — default true
        let savedAnalytics = UserDefaults.standard.object(forKey: Key.analytics)
        analytics = savedAnalytics != nil ? UserDefaults.standard.bool(forKey: Key.analytics) : true

        // historyDirectory — default to ~/Library/Application Support/Brace/
        if let saved = UserDefaults.standard.string(forKey: Key.historyDirectory) {
            historyDirectory = URL(fileURLWithPath: saved)
        } else {
            historyDirectory = Self.defaultHistoryDirectory
        }

        ensureHistoryDirectoryExists()
        applyAppearance()
    }

    // MARK: - Helpers

    /// Creates the history directory if it doesn't exist.
    func ensureHistoryDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: historyDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Full path to history.json inside the history directory.
    var historyFileURL: URL {
        historyDirectory.appendingPathComponent("history.json")
    }

    /// Resets historyDirectory to the default path.
    func resetHistoryDirectoryToDefault() {
        historyDirectory = Self.defaultHistoryDirectory
    }

    /// Resets indent + font sizes to their defaults.
    func resetEditorDefaults() {
        indentSize = Self.defaultIndentSize
        editorFontSize = Self.defaultEditorFontSize
        uiFontSize = Self.defaultUIFontSize
    }

    /// True when indent + font sizes already match their defaults.
    var editorDefaultsAreDefault: Bool {
        indentSize == Self.defaultIndentSize &&
        editorFontSize == Self.defaultEditorFontSize &&
        uiFontSize == Self.defaultUIFontSize
    }
}
