import AppKit
import SwiftUI

/// Warm neutral surfaces with semantic dark-mode counterparts.
enum AppTheme {
    static let coral = adaptive(0xCF4938, 0xFF8B76)
    static let teal = adaptive(0x367C72, 0x8BD0C3)
    static let canvas = adaptive(0xFFFDFC, 0x222422)
    static let sidebar = adaptive(0xF2EBE1, 0x2B2B27)
    static let mint = adaptive(0xE8F3EF, 0x293E37)
    static let paper = adaptive(0xFFFFFF, 0x343632)
    static let ink = adaptive(0x25251F, 0xF2EFE7)
    static let muted = adaptive(0x716E67, 0xB8B6AE)
    static let rule = adaptive(0xE9E5DE, 0x45463F)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct QuietIconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium))
            .frame(width: 30, height: 30)
            .background(AppTheme.paper.opacity(configuration.isPressed ? 0.5 : 0.95), in: Circle())
            .overlay(Circle().strokeBorder(AppTheme.rule, lineWidth: 1))
    }
}

struct SectionRule: View {
    var body: some View { Rectangle().fill(AppTheme.rule).frame(height: 1).accessibilityHidden(true) }
}
