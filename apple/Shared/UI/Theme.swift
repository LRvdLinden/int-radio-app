import SwiftUI

/// Huisstijl (SPEC §1): altijd donker, "On Air"-oranje als accent.
enum Theme {
    static let bg = Color(hex: 0x0A0A0C)
    static let surface = Color(hex: 0x16161A)
    static let elevated = Color(hex: 0x202026)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color.white
    static let secondary = Color(hex: 0xA8A8B3)
    static let accent = Color(hex: 0xFF5A1F)
    static let accent2 = Color(hex: 0xFFB020)
    static let live = Color(hex: 0xFF3B30)

    /// Accentverloop (135°)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// StationArt-paletten (begin, eind)
    static let palettes: [(Color, Color)] = [
        (Color(hex: 0xFF5A1F), Color(hex: 0xFFB020)),
        (Color(hex: 0x7C3AED), Color(hex: 0xDB2777)),
        (Color(hex: 0x0EA5E9), Color(hex: 0x22D3EE)),
        (Color(hex: 0x10B981), Color(hex: 0x84CC16)),
        (Color(hex: 0xF43F5E), Color(hex: 0xFB923C)),
        (Color(hex: 0x6366F1), Color(hex: 0x06B6D4)),
        (Color(hex: 0xEAB308), Color(hex: 0xF97316)),
        (Color(hex: 0x14B8A6), Color(hex: 0x3B82F6)),
    ]

    /// Stabiele hash (FNV-1a) zodat een zender overal dezelfde kleuren krijgt
    static func palette(for name: String) -> (Color, Color) {
        var h: UInt32 = 2166136261
        for b in name.lowercased().utf8 { h ^= UInt32(b); h = h &* 16777619 }
        return palettes[Int(h % UInt32(palettes.count))]
    }

    static func paletteGradient(_ index: Int) -> LinearGradient {
        let p = palettes[((index % palettes.count) + palettes.count) % palettes.count]
        return LinearGradient(colors: [p.0, p.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Maten per platform

    #if os(tvOS)
    static let edge: CGFloat = 80
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 16
    static let cardWidth: CGFloat = 260
    static let heroHeight: CGFloat = 460
    static let rowSpacing: CGFloat = 48
    static let itemSpacing: CGFloat = 40
    static let rowTitle = Font.system(size: 34, weight: .heavy, design: .rounded)
    static let screenTitle = Font.system(size: 56, weight: .black, design: .rounded)
    static let body = Font.system(size: 26, weight: .medium)
    static let caption = Font.system(size: 22, weight: .medium)
    static let rowArt: CGFloat = 96
    #elseif os(macOS)
    static let edge: CGFloat = 28
    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12
    static let cardWidth: CGFloat = 168
    static let heroHeight: CGFloat = 300
    static let rowSpacing: CGFloat = 30
    static let itemSpacing: CGFloat = 18
    static let rowTitle = Font.system(size: 21, weight: .heavy, design: .rounded)
    static let screenTitle = Font.system(size: 34, weight: .black, design: .rounded)
    static let body = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)
    static let rowArt: CGFloat = 52
    #else
    static let edge: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12
    static let cardWidth: CGFloat = 140
    static let heroHeight: CGFloat = 250
    static let rowSpacing: CGFloat = 26
    static let itemSpacing: CGFloat = 14
    static let rowTitle = Font.system(size: 21, weight: .heavy, design: .rounded)
    static let screenTitle = Font.system(size: 32, weight: .black, design: .rounded)
    static let body = Font.system(size: 16, weight: .medium)
    static let caption = Font.system(size: 13, weight: .medium)
    static let rowArt: CGFloat = 56
    #endif
}

/// Schaal voor Apple TV (afstand tot het scherm); iPhone/iPad/Mac 1×
func tvScaled(_ v: CGFloat) -> CGFloat {
    #if os(tvOS)
    return v * 1.9
    #else
    return v
    #endif
}

extension Color {
    /// `Color(hex: 0xFF5A1F)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Knopstijlen

/// iPhone/iPad/Mac: licht indrukken
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Apple TV-focus zonder grijze systeemvlakken: 1.08× + schaduw + witte 3px rand (SPEC §1)
struct TVLiftStyle: ButtonStyle {
    var scale: CGFloat = 1.08
    var cornerRadius: CGFloat = Theme.cardRadius
    var border = true
    func makeBody(configuration: Configuration) -> some View {
        Lift(configuration: configuration, scale: scale, cornerRadius: cornerRadius, border: border)
    }

    private struct Lift: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        let cornerRadius: CGFloat
        let border: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .environment(\.tvFocused, focused)
                .overlay {
                    if border {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white, lineWidth: focused ? 3 : 0)
                    }
                }
                .scaleEffect(configuration.isPressed ? scale * 0.97 : (focused ? scale : 1))
                .shadow(color: .black.opacity(focused ? 0.65 : 0), radius: 18, y: 12)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: focused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

private struct TVFocusedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Is de knop waar dit in staat geselecteerd (Apple TV)?
    var tvFocused: Bool {
        get { self[TVFocusedKey.self] }
        set { self[TVFocusedKey.self] = newValue }
    }
}

/// Primaire knop: accentverloop, wit; op tv met focus-lift
struct AccentButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.buttonRadius
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        private var isFocused: Bool {
            #if os(tvOS)
            return focused
            #else
            return false
            #endif
        }
        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: isFocused ? 3 : 0)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.black.opacity(configuration.isPressed ? 0.18 : 0))
                }
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1))
                .shadow(color: Theme.accent.opacity(isFocused ? 0.5 : 0.25), radius: isFocused ? 20 : 10, y: 6)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Secundaire knop: donker vlak met rand
struct SecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.buttonRadius
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        @Environment(\.isFocused) private var focused
        private var isFocused: Bool {
            #if os(tvOS)
            return focused
            #else
            return false
            #endif
        }
        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(isFocused ? Color.white : Theme.elevated,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 16, y: 10)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension View {
    /// Kaart-knoppen: tv = lift (de witte rand tekent de kaart zelf met `focusRing`); elders licht indrukken
    @ViewBuilder func cardButton() -> some View {
        #if os(tvOS)
        self.buttonStyle(TVLiftStyle(scale: 1.08, border: false))
        #else
        self.buttonStyle(PressableStyle())
        #endif
    }

    /// Knoppen zonder rand (rijen, chips): tv = lift, elders licht indrukken
    @ViewBuilder func plainTVButton() -> some View {
        #if os(tvOS)
        self.buttonStyle(TVLiftStyle(scale: 1.05, border: false))
        #else
        self.buttonStyle(PressableStyle())
        #endif
    }

    /// Witte 3px rand als de omringende knop geselecteerd is (Apple TV)
    func focusRing(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        modifier(FocusRing(cornerRadius: cornerRadius))
    }

    /// Standaard schermachtergrond
    func screenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// Titel in de navigatiebalk alleen inline op iPhone/iPad
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func largeTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}

/// Afgeronde, zware koptekst
extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: tvScaled(size), weight: weight, design: .rounded)
    }
}

/// Zie `focusRing(cornerRadius:)`
struct FocusRing: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.tvFocused) private var focused
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white, lineWidth: focused ? 3 : 0)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
