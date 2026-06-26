import SwiftUI
import AppKit
import Sentry

// Grabs the real NSWindow on first layout and locks down tabbing + minimum size.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Disable tabbing on all existing windows (handles restored state)
            for window in NSApp.windows {
                window.tabbingMode = .disallowed
                window.minSize = NSSize(width: 600, height: 400)
            }
            // Close any stale tabbed windows that aren't the main Brace window
            guard let mainWindow = view.window else { return }
            if let tabs = mainWindow.tabbedWindows {
                for tab in tabs where tab !== mainWindow {
                    tab.close()
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct BraceApp: App {
    @StateObject private var devKit = BraceModel()

    init() {
        Telemetry.start(enabled: true)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Disable macOS "smart" substitutions app-wide. Writing to the app's own
        // defaults domain overrides the system-wide toggle for this app only.
        // Critical for a JSON/curl tool: smart quotes turn " into “ ” and break
        // JSON parsing (e.g. options paths returning 0 results).
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticTextReplacementEnabled")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(devKit)
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowConfigurator())
        }
        .commands {
            AppCommands(devKit: devKit)
        }

        Settings {
            SettingsView()
        }
    }
}
