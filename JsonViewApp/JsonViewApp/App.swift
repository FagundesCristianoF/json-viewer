import SwiftUI

@main
struct DevKitApp: App {
    @StateObject private var devKit = DevKitModel()

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
