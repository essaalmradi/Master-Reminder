import SwiftUI

/// Glass is reserved for navigation and controls; reading surfaces stay quiet.
public struct BrandGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public var radius: CGFloat
    public init(radius: CGFloat = 20) { self.radius = radius }
    @ViewBuilder public func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Brand.line(scheme), lineWidth: 0.7))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
            } else { fallback(content) }
            #else
            fallback(content)
            #endif
        }
    }
    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(scheme == .dark ? 0.1 : 0.65), lineWidth: 0.7))
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.035), radius: 16, y: 5)
    }
}
public extension View {
    func brandGlass(radius: CGFloat = 20) -> some View { modifier(BrandGlass(radius: radius)) }
}
