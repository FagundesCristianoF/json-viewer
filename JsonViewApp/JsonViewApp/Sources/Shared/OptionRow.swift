import SwiftUI

struct OptionRow: View {
    let result: OptionResult
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: result.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.displayName ?? result.id)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                if result.displayName != nil {
                    Text(result.id)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(labelColor.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
    }

    private var labelColor: Color {
        switch result.status {
        case .pending, .running: return .primary
        case .matched:
            if let code = result.statusCode { return badgeColor(for: code) }
            return .green
        case .notMatched: return .secondary
        case .error: return .red
        case .skipped: return .orange
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let code = result.statusCode {
            Text("\(code)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeColor(for: code).opacity(0.15))
                .foregroundStyle(badgeColor(for: code))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else if case .error(let msg) = result.status {
            Text(shortError(msg))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help(msg)
        } else if case .skipped(let reason) = result.status {
            Text("SKIP")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help(reason)
        } else if case .running = result.status {
            EmptyView()
        }
    }

    private func badgeColor(for code: Int) -> Color {
        switch code {
        case 200...299: return .green
        case 400...499: return .orange
        case 500...599: return .red
        default: return .secondary
        }
    }

    private func shortError(_ msg: String) -> String {
        if msg.contains("timed out") || msg.contains("timeout") { return "TIMEOUT" }
        if msg.contains("cancelled") { return "CANCEL" }
        if msg.contains("connection") || msg.contains("network") { return "NET ERR" }
        if msg.contains("certificate") || msg.contains("SSL") || msg.contains("TLS") { return "TLS ERR" }
        return "ERR"
    }
}

struct StatusDot: View {
    let status: ResultStatus

    var color: Color {
        switch status {
        case .pending: return .secondary.opacity(0.4)
        case .running: return .accentColor
        case .matched: return .green
        case .notMatched: return Color(nsColor: .systemGray)
        case .error: return .red
        case .skipped: return .orange
        }
    }

    var body: some View {
        if case .running = status {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.45)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .frame(width: 14, height: 14)
        }
    }
}
