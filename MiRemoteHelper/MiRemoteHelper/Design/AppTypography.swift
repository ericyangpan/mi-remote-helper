import AppKit
import CoreText
import SwiftUI

/// Slab-serif headings and geometric UI text, with matching Chinese weights.
enum AppTypography {
    enum Face: String, CaseIterable {
        case display = "Arvo-Bold"
        case editorial = "Arvo"
        case regular = "Poppins-Regular"
        case medium = "Poppins-Medium"
        case semibold = "Poppins-SemiBold"

        var resource: String { self == .editorial ? "Arvo-Regular" : rawValue }
        var chineseName: String {
            switch self {
            case .display, .semibold: "PingFangSC-Semibold"
            case .medium: "PingFangSC-Medium"
            case .editorial, .regular: "PingFangSC-Regular"
            }
        }
    }

    static let heading = font(.display, size: 32)
    static let section = font(.editorial, size: 20)
    static let brand = font(.semibold, size: 16)
    static let device = font(.display, size: 16)
    static let body = font(.regular, size: 13)
    static let label = font(.medium, size: 13)
    static let emphasis = font(.semibold, size: 13)
    static let compact = font(.regular, size: 12)
    static let compactMedium = font(.medium, size: 12)
    static let caption = font(.regular, size: 11)
    static let captionMedium = font(.medium, size: 11)
    static let metric = font(.editorial, size: 30)
    static let gain = font(.medium, size: 23)
    // Keyboard symbols use the same native face as macOS shortcut labels.
    static let shortcut = Font.system(size: 13, weight: .medium)
    static let recordedShortcut = Font.system(size: 28, weight: .medium)

    private static let registration: Void = {
        for face in Face.allCases {
            guard let url = Bundle.main.url(forResource: face.resource, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(face.resource)")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func nativeFont(_ face: Face, size: CGFloat) -> NSFont {
        _ = registration
        guard let font = NSFont(name: face.rawValue, size: size) else {
            assertionFailure("Unable to load bundled font: \(face.rawValue)")
            return .systemFont(ofSize: size)
        }
        let chinese = NSFontDescriptor(fontAttributes: [.name: face.chineseName])
        let descriptor = font.fontDescriptor.addingAttributes([.cascadeList: [chinese]])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    private static func font(_ face: Face, size: CGFloat) -> Font {
        Font(nativeFont(face, size: size))
    }
}
