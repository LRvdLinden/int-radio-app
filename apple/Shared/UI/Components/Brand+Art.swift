import SwiftUI

// MARK: - Wordmark

/// Wordmark: `TUNR` (heavy rounded, wit) met eronder een frequentieschaal in het accentverloop,
/// 9 maatstreepjes en een naaldje (accent2) iets rechts van het midden.
struct TunrLogo: View {
    var size: CGFloat = 24

    var body: some View {
        VStack(spacing: size * 0.14) {
            Text("TUNR")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .kerning(size * 0.08)
                .foregroundStyle(.white)
            FrequencyBar(width: size * 2.75, height: size * 0.34)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
    }
}

/// De frequentieschaal onder het woordmerk
struct FrequencyBar: View {
    var width: CGFloat
    var height: CGFloat
    /// Positie van het naaldje (0…1)
    var needle: CGFloat = 0.58

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // maatstreepjes
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i == 4 ? 0.85 : 0.5))
                        .frame(width: max(1, height * 0.12), height: height * (i % 2 == 0 ? 0.5 : 0.32))
                    if i < 8 { Spacer(minLength: 0) }
                }
            }
            .frame(width: width, height: height * 0.62, alignment: .bottom)
            .offset(y: -height * 0.32)

            // balk
            Capsule()
                .fill(Theme.gradient)
                .frame(width: width, height: max(2, height * 0.26))

            // naaldje
            Capsule()
                .fill(Theme.accent2)
                .frame(width: max(1.5, height * 0.16), height: height)
                .shadow(color: Theme.accent2.opacity(0.7), radius: height * 0.3)
                .offset(x: width * needle)
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
    }
}

// MARK: - Zendercover

/// Vierkante zendercover: verloop uit de naam-hash, het logo (favicon of terugval via het domein van de zender),
/// of een monogram als er geen logo is of het laden mislukt.
struct StationArt: View {
    let station: Station
    var cornerRadius: CGFloat = Theme.cardRadius
    /// Hoes van het nummer (speler) in plaats van het logo
    var overrideURL: URL? = nil

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let colors = Theme.palette(for: station.displayName)
            ZStack {
                LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let overrideURL {
                    RemoteImage(url: overrideURL, contentMode: .fill) { monogram(side) }
                } else {
                    // build 4: het logo vult de hele tegel, zonder extra witte tegel of rand eromheen.
                    // Logo met terugval: favicon → Google/DuckDuckGo op het domein → monogram (LogoSources)
                    StationLogoImage(station: station) { monogram(side) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func monogram(_ side: CGFloat) -> some View {
        Text(station.monogram)
            .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.2), radius: 4)
            .padding(side * 0.08)
    }
}

/// Zenderlogo via LogoResolver (probeert de bronnen uit `LogoSources` na elkaar), met een eigen terugval.
struct StationLogoImage<Fallback: View>: View {
    let station: Station
    let fallback: () -> Fallback

    @State private var image: PlatformImage?
    @State private var failed: Bool

    init(station: Station, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.station = station
        self.fallback = fallback
        _image = State(initialValue: LogoResolver.shared.cachedImage(for: station))
        _failed = State(initialValue: LogoResolver.shared.knownMissing(station) || station.logoCandidates.isEmpty)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                fallback().opacity(failed ? 1 : 0.55)
            }
        }
        .task(id: station.id) {
            if let hit = LogoResolver.shared.cachedImage(for: station) {
                image = hit
                failed = false
                return
            }
            image = nil
            guard !station.logoCandidates.isEmpty, !LogoResolver.shared.knownMissing(station) else {
                failed = true
                return
            }
            failed = false
            let loaded = await LogoResolver.shared.image(for: station)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}

/// Afbeelding van internet met cache (ImageLoader) en een eigen terugval.
struct RemoteImage<Fallback: View, Decorated: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    let fallback: () -> Fallback
    let decorate: (AnyView) -> Decorated

    @State private var image: PlatformImage?
    @State private var failed = false

    init(url: URL?, contentMode: ContentMode = .fit,
         @ViewBuilder fallback: @escaping () -> Fallback,
         @ViewBuilder decorate: @escaping (AnyView) -> Decorated) {
        self.url = url
        self.contentMode = contentMode
        self.fallback = fallback
        self.decorate = decorate
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cached($0) })
    }

    var body: some View {
        ZStack {
            if let image {
                decorate(AnyView(
                    Image(platformImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: contentMode)
                ))
                .transition(.opacity)
            } else {
                fallback().opacity(failed ? 1 : 0.55)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; failed = true; return }
            if let hit = ImageLoader.shared.cached(url) { image = hit; return }
            failed = false
            let loaded = await ImageLoader.shared.load(url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}

extension RemoteImage where Decorated == AnyView {
    init(url: URL?, contentMode: ContentMode = .fit, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.init(url: url, contentMode: contentMode, fallback: fallback, decorate: { $0 })
    }
}

/// Vervaagde achtergrond van een cover (hero, speler, detail)
struct BlurredArt: View {
    let station: Station
    var overrideURL: URL? = nil

    var body: some View {
        StationArt(station: station, cornerRadius: 0, overrideURL: overrideURL)
            .scaleEffect(1.6)
            .blur(radius: 60)
            .saturation(1.4)
            .overlay(Color.black.opacity(0.45))
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Equalizer en LIVE

/// 4 staafjes in het accent bij de zender die speelt
struct EqualizerBars: View {
    var animating: Bool = true
    var color: Color = Theme.accent
    var height: CGFloat = 14

    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: height * 0.14) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: height * 0.2, height: height * barHeight(i))
                    .animation(
                        animating
                            ? .easeInOut(duration: 0.32 + Double(i) * 0.07).repeatForever(autoreverses: true).delay(Double(i) * 0.05)
                            : .easeOut(duration: 0.2),
                        value: phase
                    )
            }
        }
        .frame(height: height, alignment: .bottom)
        .onAppear { if animating { phase = true } }
        .onChange(of: animating) { _, on in phase = on }
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard animating else { return [0.35, 0.55, 0.4, 0.3][i] }
        let lows: [CGFloat] = [0.3, 0.5, 0.25, 0.45]
        let highs: [CGFloat] = [1.0, 0.7, 0.95, 0.6]
        return phase ? highs[i] : lows[i]
    }
}

/// Rode LIVE-pil met pulserend bolletje
struct LivePill: View {
    var compact = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: tvScaled(5)) {
            Circle()
                .fill(Theme.live)
                .frame(width: tvScaled(7), height: tvScaled(7))
                .scaleEffect(pulse ? 1.25 : 0.85)
                .opacity(pulse ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text(L("player.live"))
                .font(.system(size: tvScaled(compact ? 10 : 12), weight: .heavy, design: .rounded))
                .kerning(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, tvScaled(compact ? 7 : 10))
        .padding(.vertical, tvScaled(compact ? 3 : 5))
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.live.opacity(0.6), lineWidth: 1))
        .onAppear { pulse = true }
        .accessibilityLabel(L("player.live"))
    }
}
