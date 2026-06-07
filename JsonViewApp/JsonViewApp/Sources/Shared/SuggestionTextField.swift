import SwiftUI

struct SuggestionTextField: View {
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]

    @FocusState private var focused: Bool

    private var matches: [String] {
        let q = text.lowercased()
        if q.isEmpty { return suggestions }
        return suggestions.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .focused($focused)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            focused ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor),
                            lineWidth: focused ? 1.5 : 0.5
                        )
                )

            if focused && !matches.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(matches, id: \.self) { s in
                            Button {
                                text = s
                                focused = false
                            } label: {
                                Text(s)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                }
                .frame(maxHeight: 110)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }
}
