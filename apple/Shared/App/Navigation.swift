import SwiftUI

/// Bron van een zenderlijst (rasterpagina's en rijen)
enum StationSource: Hashable {
    case popular(country: String)
    case trending(country: String)
    case genre(tag: String, country: String?)
    case region(country: String, name: String)
    case language(name: String, title: String)
    case top100
    case favorites
    case recents

    var title: String {
        switch self {
        case .popular(let c): return L("row.popularIn", Country.localizedName(code: c, fallback: c))
        case .trending: return L("row.trending")
        case .genre(let tag, _): return Genre.forTag(tag).title
        case .region(_, let name): return name
        case .language(_, let title): return title
        case .top100: return L("browse.top100")
        case .favorites: return L("library.favorites")
        case .recents: return L("library.recent")
        }
    }

    /// Lokale lijsten komen uit de bibliotheek, niet van het netwerk
    var isLocal: Bool {
        switch self {
        case .favorites, .recents: return true
        default: return false
        }
    }

    /// Genummerde lijst (Top 100)
    var isRanked: Bool { self == .top100 }

    func fetch() async throws -> [Station] {
        let api = RadioBrowser.shared
        switch self {
        case .popular(let c): return try await api.popular(country: c, limit: 100)
        case .trending(let c): return try await api.trending(country: c, limit: 100)
        case .genre(let tag, let c): return try await api.byTag(tag, country: c, limit: 100)
        case .region(let c, let name): return try await api.stations(country: c, state: name)
        case .language(let name, _): return try await api.stations(language: name)
        case .top100: return try await api.top100()
        case .favorites: return await MainActor.run { Library.shared.favorites }
        case .recents: return await MainActor.run { Library.shared.recents }
        }
    }
}

/// Bestemmingen binnen een tabblad
enum Route: Hashable {
    case station(Station)
    case list(StationSource)
    case regions
    case languages
    case music
    case newsTalk
    case sports
}

/// Navigeren vanuit elke view (ook vanuit contextmenu's): `navigate(.station(s))`
struct RouteNavigator {
    var push: (Route) -> Void = { _ in }
    func callAsFunction(_ route: Route) { push(route) }
}

private struct RouteNavigatorKey: EnvironmentKey {
    static let defaultValue = RouteNavigator()
}

extension EnvironmentValues {
    var navigate: RouteNavigator {
        get { self[RouteNavigatorKey.self] }
        set { self[RouteNavigatorKey.self] = newValue }
    }
}

/// NavigationStack met een eigen pad en alle bestemmingen
struct NavStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
        .environment(\.navigate, RouteNavigator(push: { route in path.append(route) }))
    }
}

/// Het scherm bij een bestemming
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .station(let s): StationDetailView(station: s)
        case .list(let source): StationGridView(source: source)
        case .regions: LocalRegionsView()
        case .languages: LanguagesView()
        case .music: MusicGenresView()
        case .newsTalk: NewsTalkView()
        case .sports: StationGridView(source: .genre(tag: "sports", country: Library.shared.countryCode))
        }
    }
}

/// Generieke laadtoestand
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        switch self {
        case .idle, .loading: return true
        default: return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
