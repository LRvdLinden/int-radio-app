import SwiftUI

// MARK: - Kaart (raster en rijen)

/// Vierkante zenderkaart met naam en genres; equalizer als hij speelt.
struct StationCard: View {
    let station: Station
    var width: CGFloat? = Theme.cardWidth
    /// Plaats in een genummerde lijst (Top 100)
    var rank: Int? = nil

    @EnvironmentObject private var player: RadioPlayer

    private var isCurrent: Bool { player.station?.id == station.id }

    var body: some View {
        VStack(alignment: .leading, spacing: tvScaled(7)) {
            StationArt(station: station)
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        EqualizerBars(animating: player.state == .playing, color: .white, height: tvScaled(14))
                            .padding(tvScaled(7))
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: tvScaled(8), style: .continuous))
                            .padding(tvScaled(8))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let rank {
                        Text("\(rank)")
                            .font(.rounded(15, .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, tvScaled(8)).padding(.vertical, tvScaled(3))
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(tvScaled(8))
                    }
                }
                .focusRing()
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCurrent)
            Text(station.displayName)
                .font(.system(size: tvScaled(14), weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Theme.accent : .white)
                .lineLimit(1)
            Text(station.genreLine.isEmpty ? station.placeLine : station.genreLine)
                .font(.system(size: tvScaled(12), weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.displayName + (station.genreLine.isEmpty ? "" : ", " + station.genreLine))
        .accessibilityValue(isCurrent ? L("a11y.nowPlaying") : "")
    }
}

/// Knop rond een zenderkaart: tik = afspelen (in de lijst), contextmenu met Info en Favoriet.
struct StationCardButton: View {
    let station: Station
    var queue: [Station] = []
    var width: CGFloat? = Theme.cardWidth
    var rank: Int? = nil

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button {
            Haptics.tap()
            player.play(station, queue: queue)
        } label: {
            StationCard(station: station, width: width, rank: rank)
        }
        .cardButton()
        .contextMenu { StationContextMenu(station: station, queue: queue) }
        .accessibilityHint(L("a11y.playHint"))
    }
}

#if os(tvOS)
/// Apple TV: tegel "Alles" als laatste in een rij (de knop rechts in de kop is met de afstandsbediening lastig te bereiken)
struct TVAllTile: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: tvScaled(10)) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: tvScaled(30), weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                Text(L("action.all"))
                    .font(.rounded(20))
                    .foregroundStyle(.white)
            }
            .frame(width: Theme.cardWidth, height: Theme.cardWidth)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .cardButton()
        .accessibilityLabel(L("action.all"))
    }
}
#endif

/// Gedeeld contextmenu voor zenders
struct StationContextMenu: View {
    let station: Station
    var queue: [Station] = []
    var onRemove: (() -> Void)? = nil
    var removeTitle: String = ""

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button {
            player.play(station, queue: queue)
        } label: {
            Label(L("action.play"), systemImage: "play.fill")
        }
        Button {
            navigate(.station(station))
        } label: {
            Label(L("action.info"), systemImage: "info.circle")
        }
        Button {
            library.toggleFavorite(station)
        } label: {
            if library.isFavorite(station) {
                Label(L("action.unfavorite"), systemImage: "heart.slash")
            } else {
                Label(L("action.favorite"), systemImage: "heart")
            }
        }
        if let onRemove {
            Button(role: .destructive, action: onRemove) {
                Label(removeTitle, systemImage: "trash")
            }
        }
    }
}

// MARK: - Lijstrij

/// Rij voor lijsten en zoekresultaten: art 56, naam, land/genres, bitrate; equalizer als hij speelt.
struct StationRow: View {
    let station: Station
    var rank: Int? = nil
    var showChevron = false

    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var library: Library

    private var isCurrent: Bool { player.station?.id == station.id }

    var body: some View {
        HStack(spacing: tvScaled(12)) {
            if let rank {
                Text("\(rank)")
                    .font(.rounded(15, .black))
                    .foregroundStyle(rank <= 3 ? Theme.accent : Theme.secondary)
                    .frame(width: tvScaled(30))
                    .monospacedDigit()
            }
            StationArt(station: station, cornerRadius: tvScaled(10))
                .frame(width: Theme.rowArt, height: Theme.rowArt)
            VStack(alignment: .leading, spacing: tvScaled(3)) {
                HStack(spacing: tvScaled(6)) {
                    Text(station.displayName)
                        .font(.system(size: tvScaled(16), weight: .bold, design: .rounded))
                        .foregroundStyle(isCurrent ? Theme.accent : .white)
                        .lineLimit(1)
                    if library.isFavorite(station) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: tvScaled(10)))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(subtitle)
                    .font(.system(size: tvScaled(13), weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: tvScaled(8))
            if isCurrent {
                EqualizerBars(animating: player.state == .playing, height: tvScaled(16))
            } else if !station.bitrateText.isEmpty {
                Text(station.bitrateText)
                    .font(.system(size: tvScaled(11), weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, tvScaled(7)).padding(.vertical, tvScaled(3))
                    .background(Theme.elevated, in: Capsule())
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: tvScaled(12), weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, tvScaled(6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.displayName + ", " + subtitle)
        .accessibilityValue(isCurrent ? L("a11y.nowPlaying") : "")
    }

    private var subtitle: String {
        let flagCountry = [station.flag, Country.localizedName(code: station.countryCode, fallback: station.country)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return [flagCountry, station.genreLine].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Knop rond een StationRow (tik = afspelen)
struct StationRowButton: View {
    let station: Station
    var queue: [Station] = []
    var rank: Int? = nil
    var onRemove: (() -> Void)? = nil
    var removeTitle: String = ""
    /// Extra actie na tikken (bv. zoekopdracht onthouden)
    var onPlay: (() -> Void)? = nil

    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        Button {
            Haptics.tap()
            onPlay?()
            player.play(station, queue: queue)
        } label: {
            StationRow(station: station, rank: rank)
                #if os(tvOS)
                .padding(.horizontal, 16)
                .background(RowFocusBackground())
                #endif
        }
        #if os(tvOS)
        .buttonStyle(TVLiftStyle(scale: 1.03, border: false))
        #else
        .buttonStyle(PressableStyle())
        #endif
        .contextMenu { StationContextMenu(station: station, queue: queue, onRemove: onRemove, removeTitle: removeTitle) }
        .accessibilityHint(L("a11y.playHint"))
    }
}

/// tv: rij-achtergrond die oplicht bij focus (geen grijs systeemvlak)
struct RowFocusBackground: View {
    @Environment(\.tvFocused) private var focused
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(focused ? Theme.elevated : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white, lineWidth: focused ? 3 : 0))
    }
}

// MARK: - Kop van een rij

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(Theme.caption).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.system(size: tvScaled(11), weight: .bold))
                    }
                    .font(.system(size: tvScaled(14), weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    #if os(tvOS)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    #endif
                }
                .textTVButton()
            }
        }
        .padding(.horizontal, Theme.edge)
    }
}

/// Horizontale rij met zenderkaarten + "Alles"-knop
struct StationShelf: View {
    let title: String
    let stations: [Station]
    var source: StationSource? = nil
    var loading = false
    var failed = false
    var onRetry: (() -> Void)? = nil

    @Environment(\.navigate) private var navigate

    private var allAction: (() -> Void)? {
        guard let source else { return nil }
        let nav = navigate
        return { nav(.list(source)) }
    }

    var body: some View {
        if loading || failed || !stations.isEmpty {
            VStack(alignment: .leading, spacing: tvScaled(10)) {
                SectionHeader(title: title,
                              actionTitle: source != nil && !stations.isEmpty ? L("action.all") : nil,
                              action: allAction)
                if failed && stations.isEmpty {
                    InlineError(onRetry: onRetry)
                        .padding(.horizontal, Theme.edge)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.itemSpacing) {
                            if loading && stations.isEmpty {
                                ForEach(0..<8, id: \.self) { _ in CardSkeleton() }
                            } else {
                                ForEach(stations.prefix(30)) { s in
                                    StationCardButton(station: s, queue: stations)
                                }
                                #if os(tvOS)
                                if let allAction { TVAllTile(action: allAction) }
                                #endif
                            }
                        }
                        .padding(.horizontal, Theme.edge)
                        #if os(tvOS)
                        .padding(.vertical, 30)
                        #endif
                    }
                    .scrollClipDisabled()
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
    }
}

// MARK: - Genre-chips

struct GenreChips: View {
    var genres: [Genre] = Genre.all
    var horizontal = true

    @Environment(\.navigate) private var navigate

    var body: some View {
        if horizontal {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: tvScaled(8)) { chips }
                    .padding(.horizontal, Theme.edge)
                    #if os(tvOS)
                    .padding(.vertical, 20)
                    #endif
            }
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        } else {
            FlowLayout(spacing: tvScaled(8)) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(genres) { g in
            GenreChip(title: g.title, symbol: g.symbol) {
                navigate(.list(.genre(tag: g.tag, country: Library.shared.countryCode)))
            }
        }
    }
}

struct GenreChip: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, symbol: symbol)
        }
        #if os(tvOS)
        .buttonStyle(TVLiftStyle(scale: 1.08, border: false))
        #else
        .buttonStyle(PressableStyle())
        #endif
    }
}

private struct ChipLabel: View {
    let title: String
    let symbol: String?
    @Environment(\.tvFocused) private var focused

    var body: some View {
        HStack(spacing: tvScaled(6)) {
            if let symbol { Image(systemName: symbol).font(.system(size: tvScaled(12), weight: .semibold)) }
            Text(title).font(.system(size: tvScaled(14), weight: .semibold, design: .rounded))
        }
        .foregroundStyle(focused ? Color.black : Color.white)
        .padding(.horizontal, tvScaled(14))
        .padding(.vertical, tvScaled(8))
        .background(focused ? Color.white : Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Bladeren-tegel

/// Grote gekleurde tegel (zoals TuneIn) met icoon en titel
struct BrowseTile: View {
    let title: String
    let symbol: String
    var paletteIndex: Int = 0
    var subtitle: String? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.paletteGradient(paletteIndex)
            Image(systemName: symbol)
                .font(.system(size: tvScaled(64), weight: .bold))
                .foregroundStyle(.white.opacity(0.22))
                .rotationEffect(.degrees(-12))
                .offset(x: tvScaled(18), y: tvScaled(10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: tvScaled(4)) {
                Image(systemName: symbol)
                    .font(.system(size: tvScaled(24), weight: .bold))
                Spacer(minLength: 0)
                Text(title)
                    .font(.rounded(18, .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: tvScaled(12), weight: .medium))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(tvScaled(14))
        }
        .frame(height: tvScaled(DeviceKind.isPhone ? 110 : 130))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .focusRing()
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Skeletten en fouten

/// Glinsterend laadvlak
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct CardSkeleton: View {
    var width: CGFloat? = Theme.cardWidth
    var body: some View {
        VStack(alignment: .leading, spacing: tvScaled(7)) {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .aspectRatio(1, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(height: tvScaled(12)).padding(.trailing, tvScaled(20))
            RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(height: tvScaled(10)).padding(.trailing, tvScaled(50))
        }
        .frame(width: width)
        .shimmering()
        .accessibilityHidden(true)
    }
}

struct RowSkeleton: View {
    var body: some View {
        HStack(spacing: tvScaled(12)) {
            RoundedRectangle(cornerRadius: tvScaled(10), style: .continuous).fill(Theme.surface)
                .frame(width: Theme.rowArt, height: Theme.rowArt)
            VStack(alignment: .leading, spacing: tvScaled(6)) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(width: tvScaled(170), height: tvScaled(13))
                RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(width: tvScaled(110), height: tvScaled(10))
            }
            Spacer()
        }
        .padding(.vertical, tvScaled(6))
        .shimmering()
        .accessibilityHidden(true)
    }
}

struct HeroSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius + 6, style: .continuous)
            .fill(Theme.surface)
            .frame(height: Theme.heroHeight)
            .padding(.horizontal, Theme.edge)
            .shimmering()
            .accessibilityHidden(true)
    }
}

/// Foutmelding met "Opnieuw" (volledig scherm of in een rij)
struct ErrorRetryView: View {
    var title: String = L("error.title")
    var message: String = L("error.message")
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: tvScaled(12)) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: tvScaled(40), weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title).font(.rounded(19)).foregroundStyle(.white)
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                Button(action: onRetry) {
                    Label(L("action.retry"), systemImage: "arrow.clockwise")
                        .font(.system(size: tvScaled(15), weight: .bold))
                        .padding(.horizontal, tvScaled(20)).padding(.vertical, tvScaled(10))
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, tvScaled(4))
            }
        }
        .padding(tvScaled(28))
        .frame(maxWidth: tvScaled(420))
    }
}

struct InlineError: View {
    var onRetry: (() -> Void)?
    var body: some View {
        HStack(spacing: tvScaled(12)) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
            Text(L("error.short")).font(Theme.body).foregroundStyle(Theme.secondary)
            Spacer()
            if let onRetry {
                Button(L("action.retry"), action: onRetry)
                    .font(.system(size: tvScaled(14), weight: .bold))
                    .foregroundStyle(Theme.accent)
                    #if os(tvOS)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    #endif
                    .textTVButton()
            }
        }
        .padding(tvScaled(14))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Lege toestand: icoon in golven + tekst
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    @State private var wave = false

    var body: some View {
        VStack(spacing: tvScaled(14)) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.5 - Double(i) * 0.15), lineWidth: 2)
                        .frame(width: tvScaled(60 + CGFloat(i) * 30), height: tvScaled(60 + CGFloat(i) * 30))
                        .scaleEffect(wave ? 1.08 : 0.94)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: wave)
                }
                Image(systemName: symbol)
                    .font(.system(size: tvScaled(30), weight: .bold))
                    .foregroundStyle(Theme.gradient)
            }
            .frame(height: tvScaled(130))
            Text(title).font(.rounded(19)).foregroundStyle(.white)
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: tvScaled(340))
        }
        .padding(tvScaled(24))
        .onAppear { wave = true }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - FlowLayout

/// Elementen naast elkaar, doorlopend naar de volgende regel (chips)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
