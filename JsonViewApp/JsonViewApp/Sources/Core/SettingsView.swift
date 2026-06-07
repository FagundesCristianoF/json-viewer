import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            StorageSettingsTab()
                .tabItem { Label("Storage", systemImage: "folder") }
                .tag(1)
        }
        .frame(width: 480, height: 320)
        .padding()
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Dark mode", isOn: $prefs.darkMode)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Auto-save on format / transform", isOn: $prefs.autoSave)

                HStack {
                    Text("Indent size")
                    Spacer()
                    Stepper("\(prefs.indentSize) spaces", value: $prefs.indentSize, in: 1...8)
                        .fixedSize()
                }
            } header: {
                Text("Editor")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Storage tab

private struct StorageSettingsTab: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text(prefs.historyDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Button("Choose Folder…") {
                            showFolderPicker = true
                        }

                        Button("Reset to Default") {
                            prefs.resetHistoryDirectoryToDefault()
                        }
                        .foregroundStyle(.secondary)
                        .disabled(prefs.historyDirectory == Preferences.defaultHistoryDirectory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            } header: {
                Text("History & Collection Folder")
            } footer: {
                Text("Scan history and saved collections are stored in this folder. Default: ~/Library/Application Support/DevKit/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                // Security-scoped bookmark for sandboxed apps
                _ = url.startAccessingSecurityScopedResource()
                prefs.historyDirectory = url
            }
        }
    }
}
