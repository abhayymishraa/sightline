import SwiftUI

/// Design tokens, taken from the accretion frontend palette (globals.css): one sky-blue brand colour, light and dark.
enum Theme {
    static let brand = dynamic(light: 0x1E9DF1, dark: 0x1C9CF0)
    /// Text and glyphs drawn on a brand fill.
    static let onBrand = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let brandTint = dynamic(light: 0xE3ECF6, dark: 0x061622)
    static let caution = dynamic(light: 0xB42318, dark: 0xF97066)
    static let cautionTint = dynamic(light: 0xB42318, dark: 0xF97066, alpha: 0.12)
    static let backdrop = dynamic(light: 0xF7F8F8, dark: 0x000000)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x17181C)
    static let hairline = dynamic(light: 0xE1EAEF, dark: 0x242628)
    static let text = dynamic(light: 0x0F1419, dark: 0xE7E9EA)
    static let textMuted = dynamic(light: 0x52585D, dark: 0x72767A)
    static let textFaint = dynamic(light: 0x8B9196, dark: 0x55595D)

    /// Strong ease-out for UI that responds to the user; under 250 ms everywhere.
    static let snap = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    static let spring = Animation.spring(duration: 0.35, bounce: 0.12)

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        })
    }
}

// MARK: - Shared components

struct Tile<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Primary and secondary buttons share one 8 pt radius and a 0.97 press scale.
struct FilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var active
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onBrand)
            .padding(.horizontal, 16).frame(height: 32)
            .background(Theme.brand.opacity(active ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Badge: View {
    enum Kind { case good, warn, idle }
    let text: String
    let kind: Kind

    var body: some View {
        let tint: Color = switch kind { case .good: Theme.brand; case .warn: Theme.caution; case .idle: Theme.textMuted }
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).frame(height: 20)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct KeyGlyphs: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                    .background(Theme.backdrop, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }
}

/// The app icon, as drawn in the Dock. The icon art fills 824/1024 of its canvas, so the canvas is scaled up to match `size`.
struct AppMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size * 1024 / 824, height: size * 1024 / 824)
            .frame(width: size, height: size)
    }
}
