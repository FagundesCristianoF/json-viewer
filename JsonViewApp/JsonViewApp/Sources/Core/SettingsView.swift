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

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(2)
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                ThemePicker(theme: $prefs.theme)
            } header: {
                Text("Appearance")
            }

            Section {
                LabeledContent("Language") {
                    HStack(spacing: 6) {
                        Text("Follows System")
                            .foregroundStyle(.secondary)
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.langandtext")!)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Language & Region")
            } footer: {
                Text("Change language in System Settings → Language & Region.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Share anonymous usage data", isOn: $prefs.analytics)
            } header: {
                Text("Analytics")
            } footer: {
                Text("Helps improve Brace. No personal data is collected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Auto-save on format / transform", isOn: $prefs.autoSave)

                LabeledContent("Indent size") {
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

// MARK: - Theme Picker

private struct ThemePicker: View {
    @Binding var theme: AppTheme

    var body: some View {
        LabeledContent("Theme") {
            Picker("", selection: $theme) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Label(t.label, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()
        }
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
                Text("Scan history and saved collections are stored in this folder. Default: ~/Library/Application Support/Brace/")
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
                _ = url.startAccessingSecurityScopedResource()
                prefs.historyDirectory = url
            }
        }
    }
}

// MARK: - About tab

private struct AboutSettingsTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            // App identity block
            VStack(spacing: 10) {
                Image(systemName: "curlybraces.square.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)

                Text("Brace")
                    .font(.system(size: 22, weight: .semibold))

                // Version stamp — the memorable moment
                HStack(spacing: 6) {
                    Text("v\(appVersion)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text("(\(buildNumber))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Text("JSON editor and HTTP parameter scanner for macOS")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.horizontal, 32)

            Spacer()

            // Action row
            HStack(spacing: 12) {
                AboutActionButton(
                    icon: "ladybug",
                    label: "Report a Bug",
                    tint: .red
                ) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/FagundesCristianoF/json-viewer/issues")!)
                }

                AboutActionButton(
                    icon: "arrow.down.circle",
                    label: "Check for Updates",
                    tint: .accentColor
                ) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/FagundesCristianoF/json-viewer/releases")!)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }
}

private struct AboutActionButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.regular)
    }
}
