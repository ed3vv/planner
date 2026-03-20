/// Minimal design system — Notion-inspired
import SwiftUI

enum DS {
    // MARK: - Colors
    enum C {
        static let bg0         = Color(white: 0.10)   // deepest bg
        static let bg1         = Color(white: 0.13)   // surface
        static let bg2         = Color(white: 0.17)   // raised surface
        static let border      = Color(white: 1, opacity: 0.07)
        static let textPrimary = Color(white: 1, opacity: 0.88)
        static let textMuted   = Color(white: 1, opacity: 0.40)
        static let textFaint   = Color(white: 1, opacity: 0.22)
        static let accent      = Color(red: 0.36, green: 0.56, blue: 1.00) // blue
        static let green       = Color(red: 0.30, green: 0.80, blue: 0.50)
        static let orange      = Color(red: 0.95, green: 0.60, blue: 0.25)
        static let red         = Color(red: 0.95, green: 0.38, blue: 0.38)
    }

    // MARK: - Typography
    enum T {
        static func heading(_ s: CGFloat = 13) -> Font {
            .system(size: s, weight: .semibold)
        }
        static func body(_ s: CGFloat = 13) -> Font {
            .system(size: s, weight: .regular)
        }
        static func mono(_ s: CGFloat = 13) -> Font {
            .system(size: s, weight: .light, design: .monospaced)
        }
        static func label(_ s: CGFloat = 11) -> Font {
            .system(size: s, weight: .medium)
        }
        static func caption(_ s: CGFloat = 10) -> Font {
            .system(size: s, weight: .regular)
        }
    }

    // MARK: - Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// MARK: - Shared components

struct DSButton: View {
    let label: String
    var style: Style = .primary
    var size: ControlSize = .regular
    let action: () -> Void

    enum Style { case primary, secondary, ghost }

    var body: some View {
        Button(label, action: action)
            .font(DS.T.label(size == .large ? 13 : 12))
            .foregroundStyle(fgColor)
            .padding(.horizontal, size == .large ? 20 : 14)
            .padding(.vertical,   size == .large ? 9  : 6)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    private var fgColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return DS.C.textPrimary
        case .ghost:     return DS.C.textMuted
        }
    }
    private var bgColor: Color {
        switch style {
        case .primary:   return DS.C.accent
        case .secondary: return DS.C.bg2
        case .ghost:     return .clear
        }
    }
    private var borderColor: Color {
        switch style {
        case .primary:   return .clear
        case .secondary: return DS.C.border
        case .ghost:     return .clear
        }
    }
}

struct DSDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.C.border)
            .frame(height: 1)
    }
}

struct DSCheckbox: View {
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(checked ? DS.C.accent : DS.C.textFaint, lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(checked ? DS.C.accent.opacity(0.25) : .clear)
                )
                .overlay {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.C.accent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
