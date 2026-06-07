import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // Left: filename + dirty dot
            HStack(spacing: 5) {
                if let url = model.selectedFile {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(model.parseError != nil ? Color.red : JVColor.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if model.isDirty {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }
                } else {
                    Text("No file open")
                        .font(.system(size: 11.5))
                        .foregroundStyle(JVColor.tertiary)
                }
            }
            .padding(.leading, 12)

            Spacer()

            // Center: parse error message
            if let err = model.parseError {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Line \(err.line):\(err.col)  \(err.message)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.red)
            }

            Spacer()

            // Right: stats
            HStack(spacing: 12) {
                if !model.treeNodes.isEmpty {
                    statChip("\(model.treeNodes.count)", "nodes", JVColor.secondary)
                }
                if !model.jsonPathMatches.isEmpty {
                    statChip("\(model.jsonPathMatches.count)", "matches", .accentColor)
                }
                if !model.smells.isEmpty {
                    statChip("\(model.smells.count)", "smells", .orange)
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 24)
        .background(JVColor.elevated)
        .overlay(alignment: .top) { HairlineDivider() }
    }

    private func statChip(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(JVColor.tertiary)
        }
    }
}
