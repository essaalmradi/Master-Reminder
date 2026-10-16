import SwiftUI
import CoreText
import ReminderCore

public enum Brand {
    public static let night = Color(hex: 0x010E16)
    public static let navy = Color(hex: 0x044670)
    public static let ocean = Color(hex: 0x085C8F)
    public static let blue = Color(hex: 0x1F79AD)
    public static let sky = Color(hex: 0x61BCEB)
    public static let ice = Color(hex: 0xA4E0FF)
    public static let gradient = LinearGradient(colors: [night, navy], startPoint: .topLeading, endPoint: .bottomTrailing)
    public static let arabicName = "TheYearofHandicrafts-Regular"
    private static let registration: Void = {
        for (name, ext) in [("TheYearofHandicrafts-Regular", "otf"), ("Inter", "ttf"), ("HeptaSlab", "ttf")] {
            if let url = AppResources.url(name, ext) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }()
    public static func registerFonts() { _ = registration }
    public static func font(_ size: CGFloat = 17) -> Font { registerFonts(); return .custom(arabicName, size: size) }
    public static func number(_ size: CGFloat = 17) -> Font { registerFonts(); return .custom("Inter-Regular", size: size).monospacedDigit() }
    public static func latin(_ size: CGFloat = 17) -> Font { registerFonts(); return .custom("HeptaSlab-Regular", size: size) }
    public static func page(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x09131C : 0xFDFDFB) }
    public static func panel(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x0E1C27 : 0xFFFFFF) }
    public static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : night }
    public static func muted(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xA4B8C6 : 0x3E5566) }
    public static func line(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x1F3342 : 0xD7E3EB) }
    public static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x7ED3FD) : ocean }
}

public extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

public struct BrandIcon: View {
    private let size: CGFloat
    public init(size: CGFloat = 48) { self.size = size }
    public var body: some View {
        Group {
            #if os(macOS)
            if let url = AppResources.url("AppIcon", "png"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            }
            #else
            if let url = AppResources.url("AppIcon", "png"), let icon = UIImage(contentsOfFile: url.path) {
                Image(uiImage: icon).resizable().interpolation(.high).scaledToFit()
            }
            #endif
        }.frame(width: size, height: size)
    }
}

public struct BrandCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.panel(scheme).opacity(0.82), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.line(scheme).opacity(0.6), lineWidth: 0.7))
    }
}

public struct BrandButton: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Brand.font(15)).padding(.horizontal, 20).padding(.vertical, 10)
            .foregroundStyle(.white).background(Brand.ocean.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

public struct CategoryTile: View {
    @Environment(\.colorScheme) private var scheme
    let category: SpiritualCategory
    let action: () -> Void
    public init(_ category: SpiritualCategory, action: @escaping () -> Void) { self.category = category; self.action = action }
    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: category.type.symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Brand.accent(scheme)).padding(.bottom, 8)
                Text(category.title).font(Brand.font(19)).foregroundStyle(Brand.ink(scheme))
                Text(category.subtitle).font(Brand.font(13)).foregroundStyle(Brand.muted(scheme)).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(16)
                .background(Brand.panel(scheme).opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.line(scheme).opacity(0.65), lineWidth: 0.7))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
