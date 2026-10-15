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
        Image("AppIcon", bundle: AppResources.bundle).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
    }
}

public struct BrandCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Brand.line(scheme), lineWidth: 1))
    }
}

public struct BrandButton: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Brand.font(16)).padding(.horizontal, 20).padding(.vertical, 10)
            .foregroundStyle(.white).background(Brand.ocean.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

public struct CategoryTile: View {
    @Environment(\.colorScheme) private var scheme
    let category: SpiritualCategory
    let action: () -> Void
    public init(_ category: SpiritualCategory, action: @escaping () -> Void) { self.category = category; self.action = action }
    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: category.type.symbol).font(.system(size: 25, weight: .light)).foregroundStyle(Brand.accent(scheme))
                    .frame(width: 48, height: 48).background(Brand.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Text(category.title).font(Brand.font(22)).foregroundStyle(Brand.ink(scheme))
                Text(category.subtitle).font(Brand.font(14)).foregroundStyle(Brand.muted(scheme)).lineLimit(2)
            }.frame(maxWidth: .infinity, minHeight: 136, alignment: .leading).padding(20)
                .background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.line(scheme), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }
}
