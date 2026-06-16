import SwiftUI

private struct MacPanelModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

extension View {
    func glassCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macPanel(cornerRadius: 12)
    }

    func macPanel(cornerRadius: CGFloat = 10) -> some View {
        modifier(MacPanelModifier(cornerRadius: cornerRadius))
    }
}
