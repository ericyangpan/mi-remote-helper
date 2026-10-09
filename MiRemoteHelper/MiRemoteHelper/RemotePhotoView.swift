import SwiftUI

/// Hotspots use the original product photo's pixel coordinates, so the image and
/// outlines stay registered at every display scale. The bundled photo is unmodified.
struct RemotePhotoView: View {
    let pressed: Set<RemoteButton>
    var shortPressed: Set<RemoteButton> = []
    var longPressed: Set<RemoteButton> = []
    var doublePressed: Set<RemoteButton> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: Set<RemoteButton> { pressed.union(shortPressed).union(longPressed).union(doublePressed) }

    private var pressedNames: String {
        RemoteButton.allCases.filter { highlighted.contains($0) }.map { button in
            doublePressed.contains(button)
                ? String(localized: "Double Press: \(button.displayName)")
                : longPressed.contains(button)
                ? String(localized: "Long Press: \(button.displayName)")
                : shortPressed.contains(button)
                ? String(localized: "Short Press: \(button.displayName)")
                : button.displayName
        }.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geometry in
            let ratio = RemotePhotoOutline.crop.width / RemotePhotoOutline.crop.height
            let imageWidth = min(164, max(0, geometry.size.width - 40), max(0, geometry.size.height - 112) * ratio)
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                photograph.frame(width: imageWidth, height: imageWidth / ratio)
                Spacer(minLength: 20)
                SectionRule().padding(.horizontal, 20)
                Label(highlighted.isEmpty ? "RC003" : pressedNames,
                      systemImage: highlighted.isEmpty ? "circle" : (!doublePressed.isEmpty ? "hand.tap.fill" : (longPressed.isEmpty ? "circle.inset.filled" : "hand.tap.fill")))
                    .font(AppTypography.compact)
                    .foregroundStyle(highlighted.isEmpty ? AppTheme.muted : (!doublePressed.isEmpty ? Color.purple : (longPressed.isEmpty ? Color.blue : Color.orange)))
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 63)
                    .accessibilityIdentifier("remotePressedButtons")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(AppTheme.sidebar.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
        // The cropped source image extends beyond this display-only view's bounds.
        // Clipping hides those pixels but does not exclude them from hit testing.
        .allowsHitTesting(false)
    }

    private var photograph: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / RemotePhotoOutline.crop.width
            ZStack(alignment: .topLeading) {
                Image("RemoteProductPhoto")
                    .resizable()
                    .frame(width: 1571 * scale, height: 1112 * scale)
                    .offset(x: -RemotePhotoOutline.crop.minX * scale, y: -RemotePhotoOutline.crop.minY * scale)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
                ForEach(RemoteButton.allCases) { button in
                    let active = highlighted.contains(button)
                    let doubled = doublePressed.contains(button)
                    let held = active && longPressed.contains(button)
                    let highlight = doubled ? Color.purple : (held ? Color.orange : Color.blue)
                    let emphasized = held || doubled
                    RemotePhotoOutline(button: button)
                        .fill((emphasized ? highlight : Color.cyan).opacity(active ? (emphasized ? 0.32 : 0.22) : 0))
                    RemotePhotoOutline(button: button)
                        .stroke(.white.opacity(active ? 1 : 0), lineWidth: emphasized ? 4 : 3)
                    RemotePhotoOutline(button: button)
                        .stroke(highlight.opacity(active ? 1 : 0), style: StrokeStyle(lineWidth: emphasized ? 3 : 2, lineCap: .round, lineJoin: .round))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: longPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: doublePressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: shortPressed)
        }
        .aspectRatio(RemotePhotoOutline.crop.width / RemotePhotoOutline.crop.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Remote button activity"))
        .accessibilityValue(highlighted.isEmpty ? String(localized: "No buttons pressed") : pressedNames)
        .accessibilityIdentifier("remoteButtonActivity")
    }

}

struct RemotePhotoOutline: Shape {
    let button: RemoteButton
    static let crop = CGRect(x: 920, y: 490, width: 260, height: 622)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch button {
        case .up: path = ringSegment(start: 225)
        case .right: path = ringSegment(start: 315)
        case .down: path = ringSegment(start: 45)
        case .left: path = ringSegment(start: 135)
        case .ok: path.addEllipse(in: CGRect(x: 1015, y: 613, width: 68, height: 68))
        case .power: path.addEllipse(in: CGRect(x: 994, y: 536, width: 34, height: 34))
        case .microphone: path.addEllipse(in: CGRect(x: 1073, y: 536, width: 34, height: 34))
        case .back: path.addEllipse(in: CGRect(x: 993, y: 717, width: 50, height: 50))
        case .home: path.addEllipse(in: CGRect(x: 993, y: 774, width: 50, height: 50))
        case .menu: path.addEllipse(in: CGRect(x: 993, y: 831, width: 50, height: 50))
        case .volumeUp: path.addEllipse(in: CGRect(x: 1057, y: 717, width: 48, height: 49))
        case .volumeDown: path.addEllipse(in: CGRect(x: 1057, y: 774, width: 48, height: 50))
        case .tv: path.addEllipse(in: CGRect(x: 1057, y: 831, width: 48, height: 50))
        }
        let sx = rect.width / Self.crop.width
        let sy = rect.height / Self.crop.height
        let horizontalAdjustment: CGFloat = button == .ok ? 2 : (button == .microphone ? 0 : 1)
        return path.applying(CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
            tx: rect.minX + (horizontalAdjustment - Self.crop.minX) * sx,
            ty: rect.minY - Self.crop.minY * sy))
    }

    private func ringSegment(start: Double) -> Path {
        var path = Path()
        let center = CGPoint(x: 1049, y: 647)
        path.addArc(center: center, radius: 62, startAngle: .degrees(start + 4), endAngle: .degrees(start + 86), clockwise: false)
        path.addArc(center: center, radius: 37, startAngle: .degrees(start + 86), endAngle: .degrees(start + 4), clockwise: true)
        path.closeSubpath()
        return path
    }
}

#Preview("Idle") { RemotePhotoView(pressed: []).frame(width: 220, height: 520).padding() }
#Preview("Pressed") { RemotePhotoView(pressed: [.up, .back, .microphone]).frame(width: 220, height: 520).padding() }
#Preview("Long Press") { RemotePhotoView(pressed: [.up], longPressed: [.up]).frame(width: 220, height: 520).padding() }

#Preview("Double Press") { RemotePhotoView(pressed: [], doublePressed: [.ok]).frame(width: 220, height: 520).padding() }
