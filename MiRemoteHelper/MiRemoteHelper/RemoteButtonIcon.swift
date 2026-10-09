import SwiftUI

/// Matches the markings on the remote; action icons describe the mapped result.
struct RemoteButtonIcon: View {
    let button: RemoteButton

    var body: some View {
        switch button {
        case .home:
            RemoteHomeOutline()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 17)
        case .tv:
            Text(verbatim: "TV")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .frame(width: 18, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.3))
        default:
            Image(systemName: button.symbolName)
        }
    }
}

private struct RemoteHomeOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38))
        path.closeSubpath()
        return path
    }
}
