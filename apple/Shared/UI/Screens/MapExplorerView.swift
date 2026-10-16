import SwiftUI
import MapKit

/// Eén stip of cluster op de kaart
struct MapCluster: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let stations: [Station]
    var count: Int { stations.count }

    static func == (a: MapCluster, b: MapCluster) -> Bool { a.id == b.id && a.count == b.count }
}

/// Data voor de kaart: zenders met coördinaten, clustering op een raster dat meeschaalt met de zoom
@MainActor
final class MapModel: ObservableObject {
    @Published var stations: [Station] = []
    @Published var clusters: [MapCluster] = []
    @Published var isLoading = false
    @Published var failed = false
    @Published var world = false
    @Published var selected: Station?
    @Published var rolling = false

    private(set) var region: MKCoordinateRegion?
    private var loadedKey: String?

    func load(country: String, world: Bool, force: Bool = false) async {
        let key = world ? "world" : country
        guard force || loadedKey != key else { return }
        loadedKey = key
        isLoading = true
        failed = false
        do {
            let list = try await RadioBrowser.shared.geoStations(country: world ? nil : country)
            stations = list
            recluster()
        } catch {
            failed = true
            loadedKey = nil
        }
        isLoading = false
    }

    func regionChanged(_ r: MKCoordinateRegion) {
        region = r
        recluster()
    }

    /// Zenders in beeld (tv/Mac-lijst), populairste eerst
    var visibleStations: [Station] {
        guard let r = region else { return Array(stations.prefix(100)) }
        let minLat = r.center.latitude - r.span.latitudeDelta / 2
        let maxLat = r.center.latitude + r.span.latitudeDelta / 2
        let minLon = r.center.longitude - r.span.longitudeDelta / 2
        let maxLon = r.center.longitude + r.span.longitudeDelta / 2
        return Array(stations.filter { s in
            guard let c = s.coordinate else { return false }
            let lonOK = minLon < -180 || maxLon > 180 || (c.longitude >= minLon && c.longitude <= maxLon)
            return c.latitude >= minLat && c.latitude <= maxLat && lonOK
        }.prefix(150))
    }

    /// Eenvoudige rasterclustering: celgrootte = 1/9 van de zichtbare breedte
    func recluster() {
        let span = region?.span ?? MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
        let cellLat = max(span.latitudeDelta / 9, 0.0005)
        let cellLon = max(span.longitudeDelta / 9, 0.0005)
        var buckets: [String: [Station]] = [:]
        var order: [String] = []
        for s in stations {
            guard let c = s.coordinate else { continue }
            let key = "\(Int(floor(c.latitude / cellLat)))_\(Int(floor(c.longitude / cellLon)))"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(s)
        }
        var out: [MapCluster] = []
        out.reserveCapacity(order.count)
        for key in order {
            guard let list = buckets[key], !list.isEmpty else { continue }
            let lat = list.compactMap { $0.coordinate?.latitude }.reduce(0, +) / Double(list.count)
            let lon = list.compactMap { $0.coordinate?.longitude }.reduce(0, +) / Double(list.count)
            let id = list.count == 1 ? list[0].id : key + "#\(list.count)"
            out.append(MapCluster(id: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), stations: list))
        }
        clusters = out
    }

    /// Dichtstbijzijnde zenders rond een zender (voor het swipen in het kaartje)
    func nearest(to s: Station, limit: Int = 12) -> [Station] {
        guard let c = s.coordinate else { return [s] }
        let others = stations.filter { $0.id != s.id && $0.coordinate != nil }
        let sorted = others.sorted { a, b in
            Self.distance(c, a.coordinate!) < Self.distance(c, b.coordinate!)
        }
        return [s] + sorted.prefix(limit - 1)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLat = a.latitude - b.latitude
        let dLon = (a.longitude - b.longitude) * cos(a.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }
}

/// Kaart (SPEC §6): donkere wereldkaart met gloeiende stippen, clusters, kaartje onderaan, "Wereld" en "Willekeurig".
/// Apple TV en Mac: lijst met zenders in beeld links, kaart rechts; selecteren centreert de kaart.
struct MapExplorerView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.navigate) private var navigate
    @StateObject private var model = MapModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var cardQueue: [Station] = []
    @State private var didFocus = false

    private var country: String { library.countryCode ?? "NL" }

    var body: some View {
        layout
            .screenBackground()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #elseif os(macOS)
            .navigationTitle(L("tab.map"))
            #endif
            .task(id: country) {
                if app.mapWantsWorld {
                    app.mapWantsWorld = false
                    model.world = true
                    didFocus = false
                }
                await model.load(country: country, world: model.world)
                if !didFocus {
                    didFocus = true
                    focusOnData()
                }
            }
            .onChange(of: app.mapWantsWorld) { _, wants in
                guard wants else { return }
                app.mapWantsWorld = false
                setWorld(true)
            }
    }

    @ViewBuilder private var layout: some View {
        #if os(tvOS) || os(macOS)
        HStack(spacing: 0) {
            sideList
                .frame(width: sideWidth)
            ZStack(alignment: .bottom) {
                map
                VStack {
                    controls
                    Spacer()
                }
                if let s = model.selected { selectedCard(s).padding(Theme.edge) }
            }
        }
        #else
        ZStack(alignment: .bottom) {
            map.ignoresSafeArea(edges: .top)
            VStack {
                controls
                Spacer()
            }
            if let s = model.selected {
                bottomCards(s)
                    .padding(.bottom, player.hasMedia ? 4 : 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: model.selected?.id)
        #endif
    }

    private var sideWidth: CGFloat {
        #if os(tvOS)
        return 620
        #else
        return 300
        #endif
    }

    // MARK: Kaart

    private var map: some View {
        Map(position: $camera) {
            ForEach(model.clusters) { cluster in
                Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                    annotationView(cluster)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .onMapCameraChange(frequency: .onEnd) { ctx in
            model.regionChanged(ctx.region)
        }
        .overlay {
            if model.isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .padding(tvScaled(18))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if model.failed {
                ErrorRetryView { Task { await model.load(country: country, world: model.world, force: true) } }
                    .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
        .accessibilityLabel(L("tab.map"))
    }

    @ViewBuilder private func annotationView(_ cluster: MapCluster) -> some View {
        if cluster.count == 1, let s = cluster.stations.first {
            Button { select(s) } label: {
                GlowDot(isPlaying: player.station?.id == s.id && player.state == .playing,
                        isSelected: model.selected?.id == s.id)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.displayName)
        } else {
            Button { zoomInto(cluster) } label: {
                ClusterBubble(count: cluster.count,
                              containsPlaying: cluster.stations.contains { $0.id == player.station?.id })
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("map.cluster", cluster.count))
        }
    }

    // MARK: Knoppen

    /// "Wereld", of (als de wereld al getoond wordt) de knop terug naar het eigen land
    private var scopeTitle: String {
        guard model.world else { return L("map.world") }
        let name = Country.localizedName(code: country, fallback: country)
        return Country.flag(for: country) + " " + name
    }

    private var controls: some View {
        HStack(spacing: tvScaled(10)) {
            #if os(iOS)
            Text(L("tab.map"))
                .font(.rounded(22, .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 6)
            #endif
            Spacer()
            Button { setWorld(!model.world) } label: {
                Label(scopeTitle, systemImage: model.world ? "location" : "globe")
                    .font(.system(size: tvScaled(14), weight: .bold))
                    .padding(.horizontal, tvScaled(14))
                    .padding(.vertical, tvScaled(9))
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: tvScaled(20)))
            .accessibilityHint(L("a11y.mapWorldHint"))

            Button { Task { await rollDice() } } label: {
                Label(L("map.random"), systemImage: "dice.fill")
                    .font(.system(size: tvScaled(14), weight: .bold))
                    .padding(.horizontal, tvScaled(14))
                    .padding(.vertical, tvScaled(9))
                    .symbolEffect(.bounce, value: model.rolling)
            }
            .buttonStyle(AccentButtonStyle(cornerRadius: tvScaled(20)))
            .disabled(model.rolling)
        }
        .padding(.horizontal, Theme.edge)
        .padding(.top, tvScaled(10))
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // MARK: Kaartje onderaan (iPhone/iPad): horizontaal swipen = dichtstbijzijnde zenders

    #if os(iOS)
    private func bottomCards(_ s: Station) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(cardQueue) { st in
                    selectedCard(st)
                        .containerRelativeFrame(.horizontal) { w, _ in min(w - 40, 520) }
                        .id(st.id)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding<String?>(
            get: { model.selected?.id },
            set: { id in
                guard let id, let st = cardQueue.first(where: { $0.id == id }) else { return }
                model.selected = st
                if let c = st.coordinate {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        camera = .camera(MapCamera(centerCoordinate: c, distance: currentDistance))
                    }
                }
            }))
        .frame(height: 170)
    }
    #endif

    private func selectedCard(_ s: Station) -> some View {
        HStack(spacing: tvScaled(12)) {
            StationArt(station: s, cornerRadius: tvScaled(12))
                .frame(width: tvScaled(84), height: tvScaled(84))
            VStack(alignment: .leading, spacing: tvScaled(3)) {
                Text(s.displayName).font(.rounded(17)).foregroundStyle(.white).lineLimit(1)
                Text(s.placeLine).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                if !s.genreLine.isEmpty {
                    Text(s.genreLine).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                HStack(spacing: tvScaled(8)) {
                    Button {
                        Haptics.tap()
                        if player.station?.id == s.id { player.toggle() } else { player.play(s, queue: cardQueue.isEmpty ? [s] : cardQueue) }
                    } label: {
                        Label(player.station?.id == s.id && player.isPlaying ? L("player.pause") : L("player.play"),
                              systemImage: player.station?.id == s.id && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: tvScaled(14), weight: .bold))
                            .padding(.horizontal, tvScaled(16))
                            .padding(.vertical, tvScaled(8))
                    }
                    .buttonStyle(AccentButtonStyle())
                    Button { navigate(.station(s)) } label: {
                        Label(L("action.info"), systemImage: "info.circle")
                            .font(.system(size: tvScaled(14), weight: .bold))
                            .padding(.horizontal, tvScaled(12))
                            .padding(.vertical, tvScaled(8))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, tvScaled(4))
            }
            Spacer(minLength: 0)
            #if !os(tvOS)
            Button { model.selected = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("action.close"))
            #endif
        }
        .padding(tvScaled(12))
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius + 4, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: Theme.cardRadius + 4, style: .continuous).fill(Theme.elevated.opacity(0.8))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius + 4, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .frame(maxWidth: 560)
    }

    // MARK: Lijst (tv/Mac)

    #if os(tvOS) || os(macOS)
    private var sideList: some View {
        VStack(alignment: .leading, spacing: tvScaled(8)) {
            Text(L("map.inView"))
                .font(Theme.rowTitle)
                .foregroundStyle(.white)
                .padding(.horizontal, tvScaled(16))
                .padding(.top, tvScaled(14))
            Text(L("stations.count", formattedNumber(model.visibleStations.count)))
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, tvScaled(16))
            ScrollView {
                LazyVStack(spacing: tvScaled(2)) {
                    ForEach(model.visibleStations) { s in
                        Button { select(s, recenter: true) } label: {
                            StationRow(station: s)
                                .padding(.horizontal, tvScaled(10))
                                .background {
                                    #if os(tvOS)
                                    RowFocusBackground()
                                    #else
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(model.selected?.id == s.id ? Theme.elevated : Color.clear)
                                    #endif
                                }
                        }
                        #if os(tvOS)
                        .buttonStyle(TVLiftStyle(scale: 1.03, border: false))
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .contextMenu { StationContextMenu(station: s, queue: model.visibleStations) }
                    }
                }
                .padding(.horizontal, tvScaled(6))
                .padding(.vertical, tvScaled(8))
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .background(Theme.surface)
    }
    #endif

    // MARK: Acties

    private var currentDistance: Double {
        guard let r = model.region else { return 400_000 }
        return max(30_000, min(2_000_000, r.span.latitudeDelta * 111_000 * 1.2))
    }

    private func select(_ s: Station, recenter: Bool = false) {
        Haptics.tap()
        cardQueue = model.nearest(to: s)
        model.selected = s
        if recenter, let c = s.coordinate {
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .camera(MapCamera(centerCoordinate: c, distance: min(currentDistance, 250_000)))
            }
        }
    }

    private func zoomInto(_ cluster: MapCluster) {
        let lats = cluster.stations.compactMap { $0.coordinate?.latitude }
        let lons = cluster.stations.compactMap { $0.coordinate?.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 0.05),
                                    longitudeDelta: max((maxLon - minLon) * 1.6, 0.05))
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func setWorld(_ world: Bool) {
        model.world = world
        model.selected = nil
        Task {
            await model.load(country: country, world: world)
            focusOnData()
        }
    }

    /// Kaart op het land (of de wereld) zetten
    private func focusOnData() {
        if model.world {
            withAnimation(.easeInOut(duration: 0.8)) {
                camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 25, longitude: 10),
                                                    span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 160)))
            }
            return
        }
        let coords = model.stations.compactMap(\.coordinate)
        guard !coords.isEmpty else { return }
        // mediaan: uitschieters (verkeerde coördinaten) tellen niet mee
        let lats = coords.map(\.latitude).sorted()
        let lons = coords.map(\.longitude).sorted()
        let lo = lats.count / 10, hi = max(lo, lats.count - 1 - lats.count / 10)
        let center = CLLocationCoordinate2D(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
        let span = MKCoordinateSpan(latitudeDelta: min(max((lats[hi] - lats[lo]) * 1.5, 1.5), 60),
                                    longitudeDelta: min(max((lons[hi] - lons[lo]) * 1.5, 1.5), 80))
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    /// Willekeurig: vliegt naar een willekeurige zender wereldwijd en speelt hem af
    private func rollDice() async {
        model.rolling = true
        defer { model.rolling = false }
        Haptics.soft()
        guard let s = try? await RadioBrowser.shared.randomStation(), let c = s.coordinate else { return }
        if !model.stations.contains(s) {
            model.stations.append(s)
            model.recluster()
        }
        withAnimation(.easeInOut(duration: 1.4)) {
            camera = .camera(MapCamera(centerCoordinate: c, distance: 180_000))
        }
        cardQueue = model.nearest(to: s)
        model.selected = s
        player.play(s, queue: cardQueue)
        Haptics.success()
    }
}

// MARK: - Stippen

/// Gloeiende stip (accent); pulseert als hij speelt
struct GlowDot: View {
    var isPlaying = false
    var isSelected = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.35))
                .frame(width: tvScaled(22), height: tvScaled(22))
                .blur(radius: tvScaled(4))
            if isPlaying {
                Circle()
                    .stroke(Theme.accent2, lineWidth: tvScaled(2))
                    .frame(width: tvScaled(18), height: tvScaled(18))
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(isPlaying ? Theme.accent2 : Theme.accent)
                .frame(width: tvScaled(isSelected ? 14 : 10), height: tvScaled(isSelected ? 14 : 10))
                .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 1 : 0.7), lineWidth: tvScaled(isSelected ? 2.5 : 1.5)))
                .shadow(color: Theme.accent, radius: tvScaled(6))
        }
        .frame(width: tvScaled(34), height: tvScaled(34))
        .contentShape(Circle())
        .onAppear { pulse = true }
    }
}

/// Cluster: aantal in een rondje
struct ClusterBubble: View {
    let count: Int
    var containsPlaying = false

    private var size: CGFloat {
        let base: CGFloat = count < 10 ? 30 : (count < 100 ? 38 : 46)
        return tvScaled(base)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.28))
                .frame(width: size + tvScaled(12), height: size + tvScaled(12))
                .blur(radius: tvScaled(3))
            Circle()
                .fill(Theme.gradient)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(containsPlaying ? Theme.accent2 : .white.opacity(0.85), lineWidth: tvScaled(2)))
            Text(count > 999 ? "999+" : "\(count)")
                .font(.system(size: tvScaled(count < 100 ? 13 : 11), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
    }
}
