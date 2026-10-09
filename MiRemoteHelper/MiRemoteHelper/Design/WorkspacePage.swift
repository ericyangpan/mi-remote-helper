import SwiftUI

/// Shared baselines for the two pages in the fixed-size main window.
struct WorkspacePage<Header: View, Controls: View, Content: View, Footer: View>: View {
    var controlsHeight: CGFloat = 54
    @ViewBuilder var header: Header
    @ViewBuilder var controls: Controls
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            header.frame(maxWidth: .infinity, alignment: .leading).frame(height: 48)
            controls.frame(maxWidth: .infinity, alignment: .leading).frame(height: controlsHeight)
                .padding(.top, 8).padding(.bottom, 24)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 12) {
                SectionRule()
                footer.frame(height: 30)
            }.padding(.top, 24)
        }
        .padding(32)
    }
}

enum WorkspaceLayout {
    static let photoWidth: CGFloat = 220
    static let columnSpacing: CGFloat = 28
}
