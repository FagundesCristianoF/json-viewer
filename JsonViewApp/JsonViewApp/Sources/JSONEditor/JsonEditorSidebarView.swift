import SwiftUI
import AppKit

// MARK: - JsonEditorSidebarView

struct JsonEditorSidebarView: View {
    @EnvironmentObject var model: AppModel
    @State private var searchText = ""

    var filteredFiles: [WorkspaceFile] {
        guard !searchText.isEmpty else { return model.workspaceFiles }
        return model.workspaceFiles.flatMap { filterFiles($0, query: searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — mirrors TREE panel
            HStack(spacing: 6) {
                Text("FILES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)
                Spacer()
                if let root = model.workspaceRoot {
                    Text(root.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 100)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if model.workspaceRoot != nil {
                searchBar
                Divider()
                fileList
            } else {
                emptyState
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipped()
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("Filter files", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - File List

    private var fileList: some View {
        List(filteredFiles, children: \.optionalChildren, selection: .constant(nil as WorkspaceFile?)) { file in
            FileRowView(file: file, isSelected: model.selectedFile == file.url)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !file.isDirectory {
                        model.selectFile(file.url)
                    }
                }
                .contextMenu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.url.path, forType: .string)
                    }
                }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No workspace open")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Button("Open Workspace") {
                openWorkspacePanel()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func openWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            model.openWorkspace(url)
        }
    }

    private func filterFiles(_ file: WorkspaceFile, query: String) -> [WorkspaceFile] {
        if file.isDirectory {
            let filteredChildren = file.children.flatMap { filterFiles($0, query: query) }
            if !filteredChildren.isEmpty {
                return [WorkspaceFile(url: file.url, name: file.name, isDirectory: true, children: filteredChildren)]
            }
            return []
        }
        return file.name.lowercased().contains(query) ? [file] : []
    }
}

// MARK: - WorkspaceFile + OutlineGroup support

extension WorkspaceFile {
    var optionalChildren: [WorkspaceFile]? {
        isDirectory && !children.isEmpty ? children : nil
    }
}

// MARK: - FileRowView

struct FileRowView: View {
    let file: WorkspaceFile
    let isSelected: Bool

    private var isJSON: Bool {
        file.url.pathExtension.lowercased() == "json"
    }

    private var icon: NSImage {
        if file.isDirectory {
            return NSWorkspace.shared.icon(forFileType: "public.folder")
        }
        return NSWorkspace.shared.icon(forFile: file.url.path)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
                .opacity(isJSON || file.isDirectory ? 1.0 : 0.45)

            Text(file.name)
                .font(.system(size: 12))
                .foregroundColor(labelColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }

    private var labelColor: Color {
        if isSelected {
            return Color.accentColor
        }
        if !isJSON && !file.isDirectory {
            return Color.secondary
        }
        return Color(NSColor.labelColor)
    }
}

// MARK: - Preview

#if DEBUG
struct JsonEditorSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        let model = AppModel()
        JsonEditorSidebarView()
            .environmentObject(model)
            .frame(width: 240, height: 500)
    }
}
#endif
