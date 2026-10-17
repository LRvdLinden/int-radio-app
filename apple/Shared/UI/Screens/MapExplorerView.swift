import SwiftUI
import MapKit
import Combine

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
    /// Telt elke laadactie; een trager, ouder antwoord overschrijft zo nooit een nieuwer
    private var generation = 0

    func load(country: String, world: Bool, force: Bool = false) async {
        let key = world ? "world" : country
        guard force || loadedKey != key else { return }
        loadedKey = key
        generation += 1
        let gen = generation
        isLoading = true
        failed = false
        do {
            let list = try await RadioBrowser.shared.geoStations(country: world ? nil : country)
            guard gen == generation else { return }
            stations = list
            recluster()
        } catch {
            guard gen == generation else { return }
            failed = true
            loadedKey = nil
        }
        isLoading = false
    }

    /// Hoe ver `loadNear` moest zoeken
    enum NearbyResult { case near, wide, country, empty }

    /// Zenders rond een plaats (SPEC §9): binnen 50 km, anders 150 km, anders het land van de plaats.
    /// `nil` = mislukt of ingehaald door een nieuwere laadactie.
    func loadNear(_ c: CLLocationCoordinate2D, countryCode: String) async -> NearbyResult? {
        loadedKey = String(format: "geo|%.3f|%.3f", c.latitude, c.longitude)
        generation += 1
        let gen = generation
        isLoading = true
        failed = false
        world = false
        let api = RadioBrowser.shared
        do {
            var result = NearbyResult.near
            var list = try await api.geoStations(latitude: c.latitude, longitude: c.longitude, distance: 50_000)
            if list.isEmpty {
                guard gen == generation else { return nil }
                result = .wide
                list = try await api.geoStations(latitude: c.latitude, longitude: c.longitude, distance: 150_000)
            }
            if list.isEmpty, !countryCode.isEmpty {
                guard gen == generation else { return nil }
                result = .country
                list = try await api.geoStations(country: countryCode)
            }
            guard gen == generation else { return nil }
            stations = list
            recluster()
            isLoading = false
            return list.isEmpty ? .empty : result
        } catch {
            guard gen == generation else { return nil }
            failed = true
            loadedKey = nil
            isLoading = false
            return nil
        }
    }

    /// De zender die het dichtst bij een punt ligt
    func nearestStation(to c: CLLocationCoordinate2D) -> Station? {
        stations
            .compactMap { s -> (Station, Double)? in
                guard let sc = s.coordinate else { return nil }
                return (s, Self.distance(c, sc))
            }
            .min { $0.1 < $1.1 }?
            .0
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

// MARK: - Zoeken op de kaart (SPEC §9)

/// Een suggestie onder het zoekveld van de kaart
enum MapSuggestion {
    /// Land uit de landenlijst van Radio Browser
    case country(Country)
    /// Plaats uit de geocoder van Apple (nog niet opgelost naar een coördinaat)
    case place(MKLocalSearchCompletion)
    /// Al opgelost (recente zoekopdracht of directe geocode na Enter)
    case item(MapSearchItem)
}

/// Focus van het zoekveld en (Apple TV) de recente zoekopdrachten eronder
enum MapSearchFocus: Hashable {
    case field
    case recent(String)
}

/// Opgeloste plaats uit MKLocalSearch (Sendable, zodat hij veilig uit de callback komt)
private struct ResolvedPlace: Sendable {
    let latitude: Double
    let longitude: Double
    let countryCode: String
    let name: String
    let region: String
}

/// Suggesties tijdens het typen (debounce 300 ms, vanaf 2 tekens): landen uit de (gecachete) landenlijst van
/// Radio Browser en plaatsen uit `MKLocalSearchCompleter` (`.address`). Een gekozen plaats wordt met
/// `MKLocalSearch` opgelost naar coördinaat + landcode.
@MainActor
final class MapSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    @Published private(set) var countries: [Country] = []
    @Published private(set) var places: [MKLocalSearchCompletion] = []
    /// Debounce of geocoder loopt nog
    @Published private(set) var isSearching = false
    /// Een gekozen plaats wordt opgelost
    @Published private(set) var resolving = false
    /// De zoekterm waarvoor `countries` en `places` gelden
    @Published private(set) var searchedQuery = ""

    static let maxCountries = 5
    static let maxPlaces = 6

    private let completer: MKLocalSearchCompleter
    private var debounce: Task<Void, Never>?
    private var allCountries: [Country] = []
    /// Genormaliseerde landnamen (app-taal, systeemtaal, Engels, Radio Browser) → ISO-code
    private var nameIndex: [String: String] = [:]
    private var running: [MKLocalSearch] = []

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasQuery: Bool { trimmed.count >= 2 }

    /// Alle suggesties in volgorde: eerst landen, dan plaatsen
    var suggestions: [MapSuggestion] {
        countries.map { MapSuggestion.country($0) } + places.map { MapSuggestion.place($0) }
    }

    var showsNoResults: Bool {
        hasQuery && !isSearching && searchedQuery == trimmed && countries.isEmpty && places.isEmpty
    }

    func clear() {
        query = ""
    }

    // MARK: Zoeken

    private func schedule() {
        debounce?.cancel()
        let q = trimmed
        guard q.count >= 2 else {
            completer.cancel()
            countries = []
            places = []
            searchedQuery = ""
            isSearching = false
            return
        }
        isSearching = true
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.ensureCountries()
            guard !Task.isCancelled, self.trimmed == q else { return }
            self.countries = self.matchCountries(q)
            self.searchedQuery = q
            if self.completer.queryFragment == q {
                // zelfde term als de vorige keer: de completer meldt zich dan niet opnieuw
                self.completerUpdated()
            } else {
                self.places = []
                self.completer.queryFragment = q
            }
        }
    }

    private func ensureCountries() async {
        guard allCountries.isEmpty else { return }
        let list = (try? await RadioBrowser.shared.countries()) ?? []
        guard allCountries.isEmpty, !list.isEmpty else { return }
        allCountries = list
        var index: [String: String] = [:]
        let locales = [Localizer.shared.locale, Locale.current, Locale(identifier: "en_US"), Locale(identifier: "nl_NL")]
        for c in list {
            index[Self.norm(c.name)] = c.code
            for l in locales {
                if let n = l.localizedString(forRegionCode: c.code) { index[Self.norm(n)] = c.code }
            }
        }
        nameIndex = index
    }

    /// Match op gelokaliseerde naam, Engelse naam en landcode; beste match eerst, dan meeste zenders
    private func matchCountries(_ q: String) -> [Country] {
        let nq = Self.norm(q)
        let code = q.uppercased()
        var scored: [(country: Country, score: Int)] = []
        for c in allCountries {
            let local = Self.norm(c.localizedName)
            let english = Self.norm(c.name)
            let score: Int
            if (q.count == 2 && c.code == code) || local == nq || english == nq {
                score = 0
            } else if local.hasPrefix(nq) || english.hasPrefix(nq) {
                score = 1
            } else if local.contains(" " + nq) || english.contains(" " + nq) || local.contains("-" + nq) {
                score = 2
            } else if nq.count >= 3, local.contains(nq) || english.contains(nq) {
                score = 3
            } else {
                continue
            }
            scored.append((c, score))
        }
        scored.sort { $0.score != $1.score ? $0.score < $1.score : $0.country.stationCount > $1.country.stationCount }
        return scored.prefix(Self.maxCountries).map { $0.country }
    }

    /// Kleine letters, zonder accenten en zonder "the " (Radio Browser: "The Netherlands")
    static func norm(_ s: String) -> String {
        var t = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("the ") { t.removeFirst(4) }
        return t
    }

    /// Landcode bij een plaatssuggestie, geraden uit het laatste deel van de ondertitel ("Noord-Holland, Nederland")
    func countryCode(for p: MKLocalSearchCompletion) -> String {
        for text in [p.subtitle, p.title] {
            guard let last = text.split(separator: ",").last else { continue }
            if let code = nameIndex[Self.norm(String(last))] { return code }
        }
        return ""
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in self?.completerUpdated() }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.completerFailed() }
    }

    private func completerUpdated() {
        guard completer.queryFragment == trimmed, hasQuery else { return }
        places = Array(completer.results.filter { !$0.title.isEmpty }.prefix(Self.maxPlaces))
        searchedQuery = trimmed
        isSearching = false
    }

    private func completerFailed() {
        guard completer.queryFragment == trimmed else { return }
        places = []
        searchedQuery = trimmed
        isSearching = false
    }

    // MARK: Oplossen

    /// Een plaatssuggestie oplossen naar coördinaat + landcode
    func resolve(_ p: MKLocalSearchCompletion) async -> MapSearchItem? {
        let request = MKLocalSearch.Request(completion: p)
        request.resultTypes = .address
        guard let found = await run(request) else { return nil }
        let code = found.countryCode.isEmpty ? countryCode(for: p) : found.countryCode
        return MapSearchItem(kind: .place, title: p.title, subtitle: p.subtitle, countryCode: code, stationCount: 0,
                             latitude: found.latitude, longitude: found.longitude)
    }

    /// Enter zonder suggestie te kiezen: de eerste suggestie (zo nodig meteen gezocht, zonder debounce)
    func firstSuggestion() async -> MapSuggestion? {
        let q = trimmed
        guard q.count >= 2 else { return nil }
        if searchedQuery == q, !isSearching, let first = suggestions.first { return first }
        debounce?.cancel()
        await ensureCountries()
        guard trimmed == q else { return nil }
        countries = matchCountries(q)
        if let c = countries.first { return .country(c) }
        if completer.queryFragment == q, let p = completer.results.first(where: { !$0.title.isEmpty }) { return .place(p) }
        // nog geen plaatsen: direct geocoderen
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = .address
        let found = await run(request)
        guard trimmed == q else { return nil }
        guard let found else {
            places = []
            searchedQuery = q
            isSearching = false
            return nil
        }
        return .item(MapSearchItem(kind: .place, title: found.name.isEmpty ? q : found.name, subtitle: found.region,
                                   countryCode: found.countryCode, stationCount: 0,
                                   latitude: found.latitude, longitude: found.longitude))
    }

    private func run(_ request: MKLocalSearch.Request) async -> ResolvedPlace? {
        let search = MKLocalSearch(request: request)
        running.append(search)
        resolving = true
        let found: ResolvedPlace? = await withCheckedContinuation { cont in
            search.start { response, _ in
                guard let item = response?.mapItems.first else {
                    cont.resume(returning: nil)
                    return
                }
                let pm = item.placemark
                let region = [pm.administrativeArea, pm.country].compactMap { $0 }.filter { !$0.isEmpty }
                cont.resume(returning: ResolvedPlace(latitude: pm.coordinate.latitude,
                                                     longitude: pm.coordinate.longitude,
                                                     countryCode: (pm.isoCountryCode ?? "").uppercased(),
                                                     name: item.name ?? pm.locality ?? "",
                                                     region: region.joined(separator: ", ")))
            }
        }
        running.removeAll { $0 === search }
        resolving = !running.isEmpty
        return found
    }
}

/// Kaart (SPEC §6): donkere wereldkaart met gloeiende stippen, clusters, kaartje onderaan, "Wereld" en "Willekeurig".
/// Apple TV en Mac: lijst met zenders in beeld links, kaart rechts; selecteren centreert de kaart.
/// Zoeken op de kaart (SPEC §9): zoekveld "Zoek een land of plaats" met suggesties (landen + plaatsen, recent).
/// iPhone: zoekveld op een eigen regel boven de knoppen; iPad/Mac: in de bovenbalk; Apple TV: boven de lijst.
struct MapExplorerView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.navigate) private var navigate
    @StateObject private var model = MapModel()
    @StateObject private var search = MapSearchModel()
    @FocusState private var searchFocus: MapSearchFocus?
    @State private var camera: MapCameraPosition = .automatic
    @State private var cardQueue: [Station] = []
    @State private var didFocus = false
    /// Land dat via zoeken getoond wordt (tijdelijk; het land in Instellingen verandert niet)
    @State private var tempCountry: String?
    /// Plaats die via zoeken gekozen is
    @State private var placeItem: MapSearchItem?
    /// Eigen land bij de vorige `.task`, om een gewijzigd land te herkennen
    @State private var lastHome: String?

    private var country: String { library.countryCode ?? "NL" }
    /// Het land waarvan de kaart nu de zenders toont
    private var activeCountry: String { tempCountry ?? country }
    private var searchActive: Bool { tempCountry != nil || placeItem != nil }

    var body: some View {
        layout
            .screenBackground()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #elseif os(macOS)
            .navigationTitle(L("tab.map"))
            #endif
            .task(id: country) {
                if let last = lastHome, last != country {
                    // eigen land gewijzigd: tijdelijke zoekweergave vervalt
                    tempCountry = nil
                    placeItem = nil
                }
                lastHome = country
                if app.mapWantsWorld {
                    app.mapWantsWorld = false
                    model.world = true
                    tempCountry = nil
                    placeItem = nil
                    didFocus = false
                }
                if placeItem == nil {
                    await model.load(country: activeCountry, world: model.world)
                }
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
                VStack(alignment: .leading, spacing: 8) {
                    #if os(macOS)
                    controls(includeSearch: true)
                    if showsPanel {
                        suggestionPanel
                            .padding(.horizontal, Theme.edge)
                    }
                    #else
                    controls(includeSearch: false)
                    #endif
                    Spacer()
                }
                if let s = model.selected {
                    selectedCard(s)
                        .padding(Theme.edge)
                        #if os(tvOS)
                        .focusSection()
                        #endif
                }
            }
        }
        #else
        ZStack(alignment: .bottom) {
            map.ignoresSafeArea(edges: .top)
            VStack(alignment: .leading, spacing: 8) {
                if DeviceKind.isPhone {
                    searchField
                        .padding(.horizontal, Theme.edge)
                        .padding(.top, 10)
                    if showsPanel {
                        suggestionPanel
                            .padding(.horizontal, Theme.edge)
                    } else {
                        controls(includeSearch: false, topPadding: 0)
                    }
                } else {
                    controls(includeSearch: true)
                    if showsPanel {
                        suggestionPanel
                            .padding(.horizontal, Theme.edge)
                    }
                }
                Spacer()
            }
            .animation(.easeOut(duration: 0.15), value: showsPanel)
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

    /// Apple TV: de kaart zelf is niet bedienbaar met de afstandsbediening (geen focus, geen pannen);
    /// je kiest via de lijst links, die de kaart centreert, en de knoppen bovenaan.
    private var mapInteraction: MapInteractionModes {
        #if os(tvOS)
        return []
        #else
        return .all
        #endif
    }

    private var map: some View {
        Map(position: $camera, interactionModes: mapInteraction) {
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
        #if os(iOS)
        .simultaneousGesture(TapGesture().onEnded {
            // tik op de kaart: toetsenbord en suggesties dicht
            if searchFocus != nil { searchFocus = nil }
        })
        #endif
        .overlay {
            if model.isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .padding(tvScaled(18))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if model.failed {
                ErrorRetryView { retryLoad() }
                    .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
        .accessibilityLabel(L("tab.map"))
    }

    @ViewBuilder private func annotationView(_ cluster: MapCluster) -> some View {
        #if os(tvOS)
        // Apple TV: stippen zijn geen knoppen (honderden focusdoelen op de kaart werken niet met de afstandsbediening)
        if cluster.count == 1, let s = cluster.stations.first {
            GlowDot(isPlaying: player.station?.id == s.id && player.state == .playing,
                    isSelected: model.selected?.id == s.id)
                .accessibilityHidden(true)
        } else {
            ClusterBubble(count: cluster.count,
                          containsPlaying: cluster.stations.contains { $0.id == player.station?.id })
                .accessibilityHidden(true)
        }
        #else
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
        #endif
    }

    // MARK: Knoppen

    private var homeName: String { Country.localizedName(code: country, fallback: country) }

    /// "Wereld", of (als de wereld al getoond wordt) de knop terug naar het eigen land
    private var scopeTitle: String {
        guard model.world else { return L("map.world") }
        return Country.flag(for: country) + " " + homeName
    }

    /// Landknop tijdens een zoekweergave: het gezochte land (of de gekozen plaats)
    private var searchScopeTitle: String {
        if let p = placeItem {
            return (p.flag.isEmpty ? "📍" : p.flag) + " " + p.displayTitle
        }
        let code = tempCountry ?? country
        return Country.flag(for: code) + " " + Country.localizedName(code: code, fallback: code)
    }

    /// iPhone tijdens een zoekweergave: "Wereld" en "Willekeurig" alleen als icoon (anders past de balk niet)
    private var compactButtons: Bool {
        #if os(iOS)
        return DeviceKind.isPhone && searchActive
        #else
        return false
        #endif
    }

    private func controls(includeSearch: Bool, topPadding: CGFloat = 10) -> some View {
        HStack(spacing: tvScaled(10)) {
            #if os(iOS)
            if !compactButtons {
                Text(L("tab.map"))
                    .font(.rounded(22, .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .lineLimit(1)
            }
            #endif
            #if !os(tvOS)
            if includeSearch {
                searchField
                    .frame(maxWidth: searchFieldWidth)
            }
            #endif
            Spacer(minLength: 0)
            if searchActive {
                Button { setWorld(false) } label: {
                    HStack(spacing: tvScaled(6)) {
                        Text(searchScopeTitle).lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: tvScaled(11), weight: .heavy))
                    }
                    .font(.system(size: tvScaled(14), weight: .bold))
                    .padding(.horizontal, tvScaled(14))
                    .padding(.vertical, tvScaled(9))
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: tvScaled(20)))
                .accessibilityHint(L("a11y.mapBackHome", homeName))

                Button { setWorld(true) } label: {
                    pillLabel(L("map.world"), systemImage: "globe", iconOnly: compactButtons)
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: tvScaled(20)))
                .accessibilityLabel(L("map.world"))
            } else {
                Button { setWorld(!model.world) } label: {
                    pillLabel(scopeTitle, systemImage: model.world ? "location" : "globe")
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: tvScaled(20)))
                .accessibilityHint(L("a11y.mapWorldHint"))
            }

            Button { Task { await rollDice() } } label: {
                pillLabel(L("map.random"), systemImage: "dice.fill", iconOnly: compactButtons)
                    .symbolEffect(.bounce, value: model.rolling)
            }
            .buttonStyle(AccentButtonStyle(cornerRadius: tvScaled(20)))
            .disabled(model.rolling)
            .accessibilityLabel(L("map.random"))
        }
        .padding(.horizontal, Theme.edge)
        .padding(.top, tvScaled(topPadding))
        #if os(tvOS)
        .focusSection()
        #endif
    }

    @ViewBuilder private func pillLabel(_ title: String, systemImage: String, iconOnly: Bool = false) -> some View {
        Group {
            if iconOnly {
                Label(title, systemImage: systemImage).labelStyle(.iconOnly)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .lineLimit(1)
        .font(.system(size: tvScaled(14), weight: .bold))
        .padding(.horizontal, tvScaled(14))
        .padding(.vertical, tvScaled(9))
    }

    // MARK: Zoekveld en suggesties (SPEC §9)

    private var searchFieldWidth: CGFloat {
        #if os(macOS)
        return 280
        #else
        return 340
        #endif
    }

    /// Suggestiepaneel zichtbaar (iPhone/iPad/Mac): veld heeft focus en er is iets te tonen
    private var showsPanel: Bool {
        guard searchFocus != nil else { return false }
        return search.hasQuery || (search.query.isEmpty && !library.recentMapSearches.isEmpty)
    }

    #if !os(tvOS)
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: searchFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            TextField(L("map.search.prompt"), text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: searchFontSize, weight: .medium))
                .foregroundStyle(.white)
                .focused($searchFocus, equals: .field)
                .autocorrectionDisabled()
                .submitLabel(.search)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                .onKeyPress(.escape) {
                    clearSearch()
                    return .handled
                }
                #elseif os(macOS)
                .onExitCommand { clearSearch() }
                #endif
                .onSubmit { Task { await chooseFirst() } }
                .accessibilityLabel(L("a11y.mapSearch"))
            if search.resolving {
                ProgressView().smallControl()
            } else if !search.query.isEmpty {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: searchFontSize))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("action.clear"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, searchVerticalPadding)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Theme.elevated.opacity(0.75))
            }
        }
        .overlay(Capsule().strokeBorder(searchFocus == .field ? Theme.accent.opacity(0.8) : Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
    }

    private var searchFontSize: CGFloat {
        #if os(macOS)
        return 13
        #else
        return 16
        #endif
    }

    private var searchVerticalPadding: CGFloat {
        #if os(macOS)
        return 7
        #else
        return 10
        #endif
    }

    /// Paneel onder het zoekveld; scrollt pas als het niet past
    private var suggestionPanel: some View {
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView { panelContent }
        }
        .frame(maxWidth: 440, maxHeight: 380, alignment: .top)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.elevated.opacity(0.85))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.query.isEmpty {
                recentGroup
            } else {
                suggestionGroups
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    /// Landen en plaatsen bij de zoekterm
    @ViewBuilder private var suggestionGroups: some View {
        if !search.countries.isEmpty {
            groupHeader(L("map.search.countries"))
            ForEach(search.countries) { c in
                suggestionRow(flag: c.flag, icon: "flag", title: c.localizedName,
                              subtitle: L("stations.count", formattedNumber(c.stationCount))) {
                    choose(.country(c))
                }
            }
        }
        if !search.places.isEmpty || search.isSearching {
            groupHeader(L("map.search.places"), loading: search.isSearching)
            ForEach(search.places, id: \.self) { p in
                suggestionRow(flag: Country.flag(for: search.countryCode(for: p)), icon: "mappin.circle",
                              title: p.title, subtitle: p.subtitle) {
                    choose(.place(p))
                }
            }
        }
        if search.showsNoResults {
            Text(L("map.search.noResults", search.trimmed))
                .font(Theme.body)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, tvScaled(14))
                .padding(.vertical, tvScaled(12))
        }
    }

    /// Recente kaartzoekopdrachten (max 5)
    @ViewBuilder private var recentGroup: some View {
        if !library.recentMapSearches.isEmpty {
            groupHeader(L("map.search.recent"), actionTitle: L("action.clear")) {
                withAnimation { library.clearMapSearches() }
            }
            ForEach(library.recentMapSearches) { item in
                suggestionRow(flag: item.flag, icon: "clock.arrow.circlepath", title: item.displayTitle,
                              subtitle: item.kind == .country
                                ? L("stations.count", formattedNumber(item.stationCount))
                                : item.subtitle) {
                    choose(.item(item))
                }
                #if os(tvOS)
                .focused($searchFocus, equals: .recent(item.id))
                #endif
            }
        }
    }

    private func groupHeader(_ title: String, loading: Bool = false, actionTitle: String? = nil,
                             action: (() -> Void)? = nil) -> some View {
        HStack(spacing: tvScaled(8)) {
            Text(title.uppercased())
                .font(.system(size: tvScaled(11), weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.secondary)
            if loading {
                ProgressView().smallControl()
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: tvScaled(12), weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    #if os(tvOS)
                    .buttonStyle(TVLiftStyle(scale: 1.05, border: false))
                    #else
                    .buttonStyle(.plain)
                    #endif
            }
        }
        .padding(.horizontal, tvScaled(14))
        .padding(.top, tvScaled(10))
        .padding(.bottom, tvScaled(4))
    }

    private func suggestionRow(flag: String, icon: String, title: String, subtitle: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: tvScaled(10)) {
                Group {
                    if flag.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: tvScaled(16), weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text(flag).font(.system(size: tvScaled(20)))
                    }
                }
                .frame(width: tvScaled(28))
                VStack(alignment: .leading, spacing: tvScaled(1)) {
                    Text(title)
                        .font(.system(size: tvScaled(15), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, tvScaled(14))
            .padding(.vertical, tvScaled(7))
            .contentShape(Rectangle())
            #if os(tvOS)
            .background(RowFocusBackground())
            #endif
        }
        .plainTVButton()
        .accessibilityLabel(subtitle.isEmpty ? title : title + ", " + subtitle)
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
            #if os(tvOS)
            tvSearchField
                .padding(.horizontal, tvScaled(16))
                .padding(.top, tvScaled(14))
            if search.hasQuery {
                tvSuggestionList
            } else {
                stationList
            }
            #else
            stationList
            #endif
        }
        .background(Theme.surface)
    }

    @ViewBuilder private var stationList: some View {
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
                #if os(tvOS)
                // recente kaartzoekopdrachten zolang het (lege) zoekveld of een van deze rijen focus heeft
                if search.query.isEmpty, searchFocus != nil, !library.recentMapSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) { recentGroup }
                        .padding(.bottom, tvScaled(8))
                }
                #endif
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
    #endif

    #if os(tvOS)
    /// Apple TV: het zoekveld opent het systeemtoetsenbord; de suggesties verschijnen daarna als lijst
    private var tvSearchField: some View {
        HStack(spacing: tvScaled(10)) {
            TextField(L("map.search.prompt"), text: $search.query)
                .focused($searchFocus, equals: .field)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(L("a11y.mapSearch"))
            if search.resolving {
                ProgressView()
            } else if !search.query.isEmpty {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: tvScaled(14), weight: .bold))
                        .padding(tvScaled(10))
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: tvScaled(20)))
                .accessibilityLabel(L("action.clear"))
            }
        }
        .focusSection()
    }

    private var tvSuggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: tvScaled(2)) {
                suggestionGroups
            }
            .padding(.horizontal, tvScaled(6))
            .padding(.vertical, tvScaled(8))
        }
        .focusSection()
    }
    #endif

    // MARK: Acties

    private var currentDistance: Double {
        guard let r = model.region else { return 400_000 }
        return max(30_000, min(2_000_000, r.span.latitudeDelta * 111_000 * 1.2))
    }

    private func select(_ s: Station, recenter: Bool = false) {
        Haptics.tap()
        #if !os(tvOS)
        searchFocus = nil
        #endif
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

    /// Wereld aan/uit; beide eindigen de tijdelijke zoekweergave (uit = terug naar het eigen land)
    private func setWorld(_ world: Bool) {
        tempCountry = nil
        placeItem = nil
        model.world = world
        model.selected = nil
        Task {
            await model.load(country: country, world: world)
            focusOnData()
        }
    }

    private func retryLoad() {
        if let p = placeItem {
            Task { await loadPlace(p) }
        } else {
            Task { await model.load(country: activeCountry, world: model.world, force: true) }
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

    // MARK: Zoeken: kiezen

    private func clearSearch() {
        search.clear()
        searchFocus = nil
    }

    /// Enter: eerste suggestie (zonder resultaat blijft het veld open met "Niets gevonden")
    private func chooseFirst() async {
        guard search.hasQuery else { return }
        #if os(tvOS)
        // Apple TV: na het toetsenbord eerst de suggesties tonen
        return
        #else
        if let first = await search.firstSuggestion() {
            choose(first)
        } else if search.hasQuery {
            searchFocus = .field
        }
        #endif
    }

    private func choose(_ suggestion: MapSuggestion) {
        Haptics.tap()
        switch suggestion {
        case .country(let c):
            showCountry(.country(c))
        case .item(let item):
            if item.kind == .country { showCountry(item) } else { showPlace(item) }
        case .place(let p):
            searchFocus = nil
            Task {
                guard let item = await search.resolve(p) else { return }
                showPlace(item)
            }
        }
    }

    /// Land gekozen: zenders van dat land, kaart erop; de landknop toont dat land tijdelijk
    private func showCountry(_ item: MapSearchItem) {
        library.addMapSearch(item)
        search.clear()
        searchFocus = nil
        placeItem = nil
        tempCountry = item.countryCode == country ? nil : item.countryCode
        model.world = false
        model.selected = nil
        let code = item.countryCode
        Task {
            await model.load(country: code, world: false)
            guard placeItem == nil, activeCountry == code else { return }
            focusOnData()
        }
    }

    /// Plaats gekozen: erheen vliegen (±25 km), zenders in de buurt laden en het kaartje openen
    private func showPlace(_ item: MapSearchItem) {
        guard let c = item.coordinate else { return }
        library.addMapSearch(item)
        search.clear()
        searchFocus = nil
        placeItem = item
        tempCountry = item.countryCode.isEmpty ? nil : item.countryCode
        model.world = false
        model.selected = nil
        let region = MKCoordinateRegion(center: c, latitudinalMeters: 25_000, longitudinalMeters: 25_000)
        withAnimation(.easeInOut(duration: 1.2)) {
            camera = .region(region)
        }
        // meteen bijwerken: clustering en kaartje rekenen met de nieuwe zoom
        model.regionChanged(region)
        Task { await loadPlace(item) }
    }

    private func loadPlace(_ item: MapSearchItem) async {
        guard let c = item.coordinate else { return }
        let result = await model.loadNear(c, countryCode: item.countryCode)
        guard let result, placeItem?.id == item.id, let nearest = model.nearestStation(to: c) else { return }
        // dichtstbijzijnde zender + 7 in de buurt
        cardQueue = model.nearest(to: nearest, limit: 8)
        model.selected = nearest
        if result == .country, let sc = nearest.coordinate {
            // niets binnen 150 km: naar de dichtstbijzijnde zender in het land
            withAnimation(.easeInOut(duration: 1.0)) {
                camera = .camera(MapCamera(centerCoordinate: sc, distance: 180_000))
            }
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
