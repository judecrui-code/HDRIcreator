import SwiftUI

enum Theme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.04)
    static let surface = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let surfaceHigh = Color(red: 0.13, green: 0.13, blue: 0.16)
    static let hairline = Color.white.opacity(0.08)
    static let accent = Color(red: 0.36, green: 0.78, blue: 1.0)
    static let good = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.25)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.35)
    static let textSecondary = Color.white.opacity(0.55)

    static var backdrop: some View {
        LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.09), background], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func capture() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
