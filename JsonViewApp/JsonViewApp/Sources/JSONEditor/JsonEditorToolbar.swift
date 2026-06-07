import SwiftUI

struct JsonEditorToolbarItems: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            ThemeToggleButton()
            Button { model.showTree.toggle() } label: {
                Image(systemName: "list.bullet.indent")
            }
            .help("Toggle Tree")
            JsonEditorIssuesToggle()
        }
    }
}

// Separate View so @ObservedObject wiring is stable across toolbar redraws.
private struct ThemeToggleButton: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Button {
            prefs.theme = prefs.theme == .dark ? .light : .dark
        } label: {
            Image(systemName: prefs.theme == .dark ? "sun.max" : "moon")
        }
        .help(prefs.theme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
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
