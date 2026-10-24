import SwiftUI
import WatchKit

enum WTheme {
    static let bg = Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255)
    static let surface = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x26 / 255)
    static let accent = Color(red: 1, green: 0x5A / 255, blue: 0x1F / 255)
    static let accent2 = Color(red: 1, green: 0xB0 / 255, blue: 0x20 / 255)
    static let secondary = Color(red: 0xA8 / 255, green: 0xA8 / 255, blue: 0xB3 / 255)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let palettes: [(Color, Color)] = [
        (Color(red: 1, green: 0.35, blue: 0.12), Color(red: 1, green: 0.69, blue: 0.13)),
        (Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.86, green: 0.15, blue: 0.47)),
        (Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.13, green: 0.83, blue: 0.93)),
        (Color(red: 0.06, green: 0.73, blue: 0.51), Color(red: 0.52, green: 0.8, blue: 0.09)),
        (Color(red: 0.96, green: 0.25, blue: 0.37), Color(red: 0.98, green: 0.57, blue: 0.24)),
        (Color(red: 0.39, green: 0.4, blue: 0.95), Color(red: 0.02, green: 0.71, blue: 0.83)),
    ]
    static func palette(_ name: String) -> LinearGradient {
        let i = abs(name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % palettes.count
        return LinearGradient(colors: [palettes[i].0, palettes[i].1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Zenderlogo (app-icoon uit de tabel van tunr.online, anders favicon), met monogram als terugval
struct WLogo: View {
    let station: WStation
    var size: CGFloat = 36
    @State private var url: URL?

    var body: some View {
        ZStack {
            WTheme.palette(station.displayName)
            Text(station.monogram)
                .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
            if let url {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: station.id) { url = await WatchIcons.shared.url(for: station) }
        .accessibilityHidden(true)
    }
}

/// Drie oranje balkjes die bewegen tijdens het afspelen
struct WBars: View {
    let playing: Bool
    @State private var phase = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(WTheme.accent)
                    .frame(width: 3, height: playing ? (phase ? [9, 5, 11][i] : [4, 10, 6][i]) : 3)
            }
        }
        .frame(height: 11, alignment: .bottom)
        .animation(playing ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: phase)
        .onAppear { phase.toggle() }
        .accessibilityHidden(true)
    }
}

struct StationRow: View {
    let station: WStation
    var active = false

    var body: some View {
        HStack(spacing: 10) {
            WLogo(station: station, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if !station.subtitle.isEmpty {
                    Text(station.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(WTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if active { WBars(playing: true) }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Nu speelt

struct NowPlayingPage: View {
    @EnvironmentObject private var local: WatchPlayer
    @EnvironmentObject private var phone: PhoneLink
    @EnvironmentObject private var store: WatchStore
    @State private var crown: Double = 0.8
    @State private var showSystem = false

    private enum Source { case watch, phone, none }
    private var source: Source {
        if local.hasMedia { return .watch }
        if phone.nowPlaying != nil { return .phone }
        return .none
    }
    private var station: WStation? { source == .watch ? local.station : phone.nowPlaying?.station }
    private var playing: Bool { source == .watch ? local.isPlaying : (phone.nowPlaying?.isPlaying ?? false) }
    private var line: String {
        let raw = source == .watch ? local.streamTitle : (phone.nowPlaying?.streamTitle ?? "")
        return WTrack.line(raw)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let s = station {
                HStack(spacing: 8) {
                    artwork(s)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            WBars(playing: playing)
                            Text(LocalizedStringKey(source == .watch ? "watch.onWatch" : "watch.onPhone"))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(WTheme.accent)
                                .lineLimit(1)
                        }
                        Text(s.displayName)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(line.isEmpty ? s.subtitle : line)
                            .font(.system(size: 12))
                            .foregroundStyle(WTheme.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                controls(s)
                if source == .watch, local.state == .failed {
                    Text("watch.failed").font(.system(size: 11)).foregroundStyle(WTheme.secondary)
                }
            } else {
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WTheme.gradient)
                Text("watch.nothing")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("watch.nothing.hint")
                    .font(.system(size: 12))
                    .foregroundStyle(WTheme.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .focusable(source == .watch)
        .digitalCrownRotation($crown, from: 0, through: 1, by: 0.02, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, v in if source == .watch { local.volume = v } }
        .onAppear { crown = local.volume; phone.refresh() }
        .sheet(isPresented: $showSystem) { NowPlayingView() }
        .navigationTitle("Tunr")
    }

    @ViewBuilder private func artwork(_ s: WStation) -> some View {
        if source == .phone, let art = phone.nowPlaying?.artwork {
            AsyncImage(url: art) { phase in
                if let img = phase.image { img.resizable().scaledToFill() } else { WLogo(station: s, size: 54) }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            WLogo(station: s, size: 54)
        }
    }

    private func controls(_ s: WStation) -> some View {
        HStack(spacing: 10) {
            Button { source == .watch ? local.step(-1) : phone.command("prev") } label: {
                Image(systemName: "backward.fill").font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("watch.previous"))
            Button { source == .watch ? local.toggle() : phone.command("toggle") } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(WTheme.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(playing ? "watch.pause" : "watch.play")))
            Button { source == .watch ? local.step(1) : phone.command("next") } label: {
                Image(systemName: "forward.fill").font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("watch.next"))
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { store.toggleFavorite(s) } label: {
                    Image(systemName: store.isFavorite(s) ? "heart.fill" : "heart")
                }
                .accessibilityLabel(Text("watch.favorite"))
                Spacer()
                Button { showSystem = true } label: { Image(systemName: "speaker.wave.2.fill") }
                    .accessibilityLabel(Text("watch.volume"))
            }
        }
    }
}

// MARK: - Lijsten

/// Een zender kiezen: op de iPhone (als die bereikbaar is en zo ingesteld) of op de Watch
@MainActor
func playStation(_ s: WStation, queue: [WStation]) {
    let store = WatchStore.shared
    if store.target == .phone, PhoneLink.shared.isReachable {
        if WatchPlayer.shared.hasMedia { WatchPlayer.shared.stop() }
        PhoneLink.shared.play(s, queue: queue)
    } else {
        WatchPlayer.shared.play(s, queue: queue)
    }
    WKInterfaceDevice.current().play(.click)
}

struct StationList: View {
    let title: LocalizedStringKey
    let stations: [WStation]
    @EnvironmentObject private var local: WatchPlayer
    @EnvironmentObject private var phone: PhoneLink

    var body: some View {
        List(stations) { s in
            Button { playStation(s, queue: stations) } label: {
                StationRow(station: s, active: local.station == s || phone.nowPlaying?.station == s)
            }
        }
        .navigationTitle(title)
    }
}

struct LibraryPage: View {
    @EnvironmentObject private var store: WatchStore
    @EnvironmentObject private var local: WatchPlayer
    @EnvironmentObject private var phone: PhoneLink

    var body: some View {
        List {
            Section("watch.favorites") {
                if store.favorites.isEmpty {
                    Text("watch.favorites.empty").font(.system(size: 13)).foregroundStyle(WTheme.secondary)
                }
                ForEach(store.favorites) { s in
                    Button { playStation(s, queue: store.favorites) } label: {
                        StationRow(station: s, active: local.station == s || phone.nowPlaying?.station == s)
                    }
                }
            }
            if !store.allRecents.isEmpty {
                Section("watch.recents") {
                    ForEach(store.allRecents.prefix(10)) { s in
                        Button { playStation(s, queue: store.allRecents) } label: {
                            StationRow(station: s, active: local.station == s || phone.nowPlaying?.station == s)
                        }
                    }
                }
            }
        }
        .navigationTitle("watch.library")
    }
}

struct DiscoverPage: View {
    @EnvironmentObject private var store: WatchStore
    @State private var popular: [WStation] = []
    @State private var loading = false
    @State private var failed = false
    @State private var query = ""
    @State private var results: [WStation]?

    var body: some View {
        List {
            Section {
                TextField("watch.search", text: $query)
                    .onSubmit { Task { await search() } }
            }
            if let results {
                Section("watch.results") {
                    if results.isEmpty {
                        Text("watch.noResults").font(.system(size: 13)).foregroundStyle(WTheme.secondary)
                    }
                    ForEach(results) { s in
                        Button { playStation(s, queue: results) } label: { StationRow(station: s) }
                    }
                }
            }
            Section(header: Text(popularTitle)) {
                if loading && popular.isEmpty { ProgressView() }
                if failed && popular.isEmpty {
                    Button("watch.retry") { Task { await load() } }
                }
                ForEach(popular) { s in
                    Button { playStation(s, queue: popular) } label: { StationRow(station: s) }
                }
            }
        }
        .navigationTitle("watch.discover")
        .task(id: store.countryCode) { await load() }
    }

    private var popularTitle: String {
        let cc = store.countryCode
        guard !cc.isEmpty else { return String(localized: "watch.popularWorld") }
        let name = Locale.current.localizedString(forRegionCode: cc) ?? cc
        return String(format: String(localized: "watch.popularIn %@"), name)
    }

    private func load() async {
        loading = true
        failed = false
        do {
            popular = store.countryCode.isEmpty
                ? try await WatchRadioBrowser.shared.top()
                : try await WatchRadioBrowser.shared.popular(country: store.countryCode)
        } catch {
            failed = true
        }
        loading = false
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = nil; return }
        results = (try? await WatchRadioBrowser.shared.search(name: q, country: store.countryCode)) ?? []
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var store: WatchStore
    @EnvironmentObject private var phone: PhoneLink

    var body: some View {
        List {
            Section {
                Picker("watch.playOn", selection: $store.target) {
                    Text("watch.target.phone").tag(PlaybackTarget.phone)
                    Text("watch.target.watch").tag(PlaybackTarget.watch)
                }
            } footer: {
                Text(LocalizedStringKey(store.target == .phone ? "watch.target.phone.hint" : "watch.target.watch.hint"))
            }
            Section {
                Toggle("watch.stats", isOn: $store.shareStats)
            } footer: {
                Text("watch.stats.hint")
            }
            Section {
                HStack {
                    Text("Tunr")
                    Spacer()
                    Text(Brand.versionText).foregroundStyle(WTheme.secondary)
                }
                HStack {
                    Text("watch.iphone")
                    Spacer()
                    Text(LocalizedStringKey(phone.isReachable ? "watch.connected" : "watch.notConnected"))
                        .foregroundStyle(WTheme.secondary)
                }
            }
        }
        .navigationTitle("watch.settings")
    }
}
