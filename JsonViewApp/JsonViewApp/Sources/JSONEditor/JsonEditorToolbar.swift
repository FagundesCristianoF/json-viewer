import SwiftUI

struct JsonEditorToolbarItems: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.showSidebar.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }

        ToolbarItemGroup(placement: .automatic) {
            Button { model.darkMode.toggle() } label: {
                Image(systemName: model.darkMode ? "sun.max" : "moon")
            }
            .help(model.darkMode ? "Light Mode" : "Dark Mode")

            Button { model.showTree.toggle() } label: {
                Image(systemName: "list.bullet.indent")
            }
            .help("Toggle Tree")

            JsonEditorIssuesToggle()
        }
    }
}

private struct JsonEditorIssuesToggle: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.showIssues.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "exclamationmark.triangle")
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                IssuesBadge(
                    errorCount: model.parseError != nil ? 1 : 0,
                    smellCount: model.smells.count
                )
            }
        }
        .help("Toggle Issues")
    }
}

private struct IssuesBadge: View {
    let errorCount: Int
    let smellCount: Int
    var count: Int { errorCount + smellCount }
    var body: some View {
        if count > 0 {
            Text("\(min(count, 99))")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.red, in: Capsule())
        }
    }
}
