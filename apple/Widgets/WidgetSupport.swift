import WidgetKit
import SwiftUI

// Gedeelde onderdelen van de widget-extensie: teksten (taal van de app), huisstijl, logo's en de tijdlijn.

// MARK: - Teksten

/// Vertalingen uit de Localizable.strings van de extensie, in de taal die in de app gekozen is
/// (WidgetBridge.language), anders de systeemtaal.
enum WidgetText {
    static func t(_ key: String) -> String {
        let lang = language
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) {
            let v = b.localizedString(forKey: key, value: nil, table: nil)
            if v != key { return v }
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let en = Bundle(path: path) {
            return en.localizedString(forKey: key, value: key, table: nil)
        }
        return key
    }

    /// "nl" of "en"
    static var language: String {
        let saved = WidgetBridge.language
        if saved == "nl" || saved == "en" { return saved }
        for pref in Locale.preferredLanguages {
            let base = String(pref.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
            if base == "nl" || base == "en" { return base }
        }
        return "en"
    }
}

// MARK: - Huisstijl

extension Color {
    /// `Color(widgetHex: 0xFF5A1F)`
    init(widgetHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Zelfde kleuren als de app (Theme.swift, SPEC §1)
enum WidgetTheme {
    static let bg = Color(widgetHex: 0x0A0A0C)
    static let surface = Color(widgetHex: 0x16161A)
    static let elevated = Color(widgetHex: 0x202026)
    static let secondary = Color(widgetHex: 0xA8A8B3)
    static let accent = Color(widgetHex: 0xFF5A1F)
    static let accent2 = Color(widgetHex: 0xFFB020)
    static let live = Color(widgetHex: 0xFF3B30)
    static let stroke = Color.white.opacity(0.08)

    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Donkere achtergrond met een zachte oranje gloed rechtsboven
    static var background: some View {
        ZStack {
            LinearGradient(colors: [Color(widgetHex: 0x17171C), bg], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.28), .clear], center: .topTrailing, startRadius: 4, endRadius: 190)
        }
    }

    private static let palettes: [(UInt32, UInt32)] = [
        (0xFF5A1F, 0xFFB020), (0x7C3AED, 0xDB2777), (0x0EA5E9, 0x22D3EE), (0x10B981, 0x84CC16),
        (0xF43F5E, 0xFB923C), (0x6366F1, 0x06B6D4), (0xEAB308, 0xF97316), (0x14B8A6, 0x3B82F6),
    ]

    /// Zelfde palet per zendernaam als StationArt in de app (FNV-1a)
    static func palette(for name: String) -> LinearGradient {
        var h: UInt32 = 2166136261
        for b in name.lowercased().utf8 { h ^= UInt32(b); h = h &* 16777619 }
        let p = palettes[Int(h % UInt32(palettes.count))]
        return LinearGradient(colors: [Color(widgetHex: p.0), Color(widgetHex: p.1)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Logo's

/// Zenderlogo uit de App Group (verkleind door de app), anders een gekleurde tegel met letters
struct StationLogoView: View {
    let station: WidgetStation
    var size: CGFloat
    var cornerRadius: CGFloat? = nil
    /// Alternatieve bestandsnaam (Live Activity)
    var fileName: String? = nil
    /// Albumhoes van het huidige nummer (gaat voor het logo)
    var coverFile: String? = nil

    var body: some View {
        let radius = cornerRadius ?? size * 0.22
        ZStack {
            WidgetTheme.palette(for: station.displayName)
            if let image = loadImage() {
                // vierkante PNG met het logo al op zijn eigen achtergrond (WidgetLogoMaker in de app)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(station.monogram)
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(WidgetTheme.stroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func loadImage() -> CGImage? {
        if let coverFile, let img = WidgetBridge.logoImage(fileName: coverFile) { return img }
        if let fileName, let img = WidgetBridge.logoImage(fileName: fileName) { return img }
        return WidgetBridge.logoImage(for: station.id)
    }
}

/// Klein Tunr-merkje: oranje tegel met radiogolven + "TUNR"
struct TunrMark: View {
    var size: CGFloat = 14
    var showName = true

    var body: some View {
        HStack(spacing: size * 0.35) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.62, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 1.25, height: size * 1.25)
                .background(WidgetTheme.gradient, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            if showName {
                Text("TUNR")
                    .font(.system(size: size * 0.8, weight: .heavy, design: .rounded))
                    .kerning(size * 0.06)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Equalizer-balkjes (stilstaand: widgets en Live Activities mogen niet doorlopend animeren)
struct EqualizerBars: View {
    var isPlaying: Bool
    var height: CGFloat = 14
    var color: Color = WidgetTheme.accent

    var body: some View {
        let levels: [CGFloat] = isPlaying ? [0.55, 1.0, 0.7, 0.85] : [0.3, 0.3, 0.3, 0.3]
        HStack(alignment: .bottom, spacing: height * 0.14) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: height * 0.16, height: max(2, height * levels[i]))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Tijdlijn

struct TunrEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Eén item per keer; de app laat de widgets opnieuw tekenen als er iets verandert (WidgetSync)
struct TunrProvider: TimelineProvider {
    func placeholder(in context: Context) -> TunrEntry {
        TunrEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TunrEntry) -> Void) {
        let snap = WidgetBridge.load()
        // widgetgalerie: voorbeeld tonen zolang er nog niets is
        let empty = snap.nowPlaying == nil && snap.favorites.isEmpty && snap.recents.isEmpty
        completion(TunrEntry(date: Date(), snapshot: context.isPreview && empty ? .sample : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TunrEntry>) -> Void) {
        completion(Timeline(entries: [TunrEntry(date: Date(), snapshot: WidgetBridge.load())], policy: .never))
    }
}

// MARK: - Voorbeeldgegevens (galerie, placeholders, previews)

extension WidgetStation {
    static let samples: [WidgetStation] = [
        WidgetStation(id: "sample-1", name: "NPO Radio 2", country: "The Netherlands", countryCode: "NL", logoURL: nil),
        WidgetStation(id: "sample-2", name: "Radio 538", country: "The Netherlands", countryCode: "NL", logoURL: nil),
        WidgetStation(id: "sample-3", name: "BBC Radio 1", country: "The United Kingdom", countryCode: "GB", logoURL: nil),
        WidgetStation(id: "sample-4", name: "Qmusic", country: "The Netherlands", countryCode: "NL", logoURL: nil),
        WidgetStation(id: "sample-5", name: "FIP", country: "France", countryCode: "FR", logoURL: nil),
        WidgetStation(id: "sample-6", name: "Sky Radio", country: "The Netherlands", countryCode: "NL", logoURL: nil),
        WidgetStation(id: "sample-7", name: "KEXP 90.3", country: "The United States", countryCode: "US", logoURL: nil),
        WidgetStation(id: "sample-8", name: "Radio Veronica", country: "The Netherlands", countryCode: "NL", logoURL: nil),
    ]
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        nowPlaying: WidgetNowPlaying(station: WidgetStation.samples[0], isPlaying: true,
                                     title: "Bohemian Rhapsody", artist: "Queen"),
        favorites: WidgetStation.samples,
        recents: Array(WidgetStation.samples.reversed()),
        language: ""
    )
}

/// Diepe link naar een zender (terugval als de intent niet in de app draait)
func stationURL(_ id: String) -> URL {
    URL(string: "tunr://station/\(id)") ?? URL(string: "tunr://open")!
}
