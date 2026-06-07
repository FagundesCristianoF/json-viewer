import SwiftUI
import AppKit

// MARK: - Json Viewer Design Tokens
// Dark-first. Apple HIG semantic layers + vivid JSON type palette.

enum JVColor {
    // Backgrounds — 4 depth levels
    static let base        = Color(NSColor.windowBackgroundColor)          // #1C1C1E
    static let elevated    = Color(NSColor.controlBackgroundColor)          // #2C2C2E
    static let sidebar     = Color(NSColor.underPageBackgroundColor)        // #161618
    static let field       = Color(NSColor.textBackgroundColor)             // editor bg

    // Text
    static let label       = Color(NSColor.labelColor)
    static let secondary   = Color(NSColor.secondaryLabelColor)
    static let tertiary    = Color(NSColor.tertiaryLabelColor)

    // Separator
    static let separator   = Color(NSColor.separatorColor)

    // Accent
    static let accent      = Color.accentColor                              // systemBlue

    // JSON type colors — Apple system palette
    static func kind(_ k: NodeKind) -> Color {
        switch k {
        case .object: return Color(NSColor.systemBlue)
        case .array:  return Color(NSColor.systemGreen)
        case .string: return Color(NSColor.systemOrange)
        case .number: return Color(NSColor.systemPurple)
        case .bool:   return Color(NSColor.systemPink)
        case .null:   return Color(NSColor.systemGray)
        }
    }

    static func kindLabel(_ k: NodeKind) -> String {
        switch k {
        case .object: return "{ }"
        case .array:  return "[ ]"
        case .string: return "str"
        case .number: return "num"
        case .bool:   return "bool"
        case .null:   return "null"
        }
    }
}

// MARK: - Type Badge

struct TypeBadge: View {
    let kind: NodeKind
    private var color: Color { JVColor.kind(kind) }
    private var label: String { JVColor.kindLabel(kind) }

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Subtle Divider

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(JVColor.separator)
            .frame(height: 0.5)
    }
}
