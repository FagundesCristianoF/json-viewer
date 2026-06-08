import SwiftUI

@main
struct BraceApp: App {
    @StateObject private var devKit = BraceModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(devKit)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .commands {
            AppCommands(devKit: devKit)
        }

        Settings {
            SettingsView()
        }
    }
}
