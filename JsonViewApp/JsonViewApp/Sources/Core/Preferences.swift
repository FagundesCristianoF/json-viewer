import Foundation
import Combine

/// Single source of truth for all persisted app preferences.
/// All UserDefaults access goes through here.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    // MARK: - Keys

    private enum Key {
        static let darkMode            = "darkMode"
        static let autoSave            = "autoSave"
        static let indentSize          = "indentSize"
        static let workspaceRoot       = "workspaceRoot"
        static let devKitMode          = "devKitMode"
        static let historyDirectory    = "historyDirectory"
    }

    // MARK: - Editor

    @Published var darkMode: Bool {
        didSet { UserDefaults.standard.set(darkMode, forKey: Key.darkMode) }
    }

    @Published var autoSave: Bool {
        didSet { UserDefaults.standard.set(autoSave, forKey: Key.autoSave) }
    }

    @Published var indentSize: Int {
        didSet { UserDefaults.standard.set(indentSize, forKey: Key.indentSize) }
    }

    // MARK: - History / Collection folder

    /// Default: ~/Library/Application Support/DevKit/
    static var defaultHistoryDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent("DevKit", isDirectory: true)
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
        // darkMode — default false
        darkMode = UserDefaults.standard.bool(forKey: Key.darkMode)

        // autoSave — default true
        let savedAutoSave = UserDefaults.standard.object(forKey: Key.autoSave)
        autoSave = savedAutoSave != nil ? UserDefaults.standard.bool(forKey: Key.autoSave) : true

        // indentSize — default 2
        let savedIndent = UserDefaults.standard.integer(forKey: Key.indentSize)
        indentSize = savedIndent > 0 ? savedIndent : 2

        // historyDirectory — default to ~/Library/Application Support/DevKit/
        if let saved = UserDefaults.standard.string(forKey: Key.historyDirectory) {
            historyDirectory = URL(fileURLWithPath: saved)
        } else {
            historyDirectory = Self.defaultHistoryDirectory
        }

        ensureHistoryDirectoryExists()
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
}
