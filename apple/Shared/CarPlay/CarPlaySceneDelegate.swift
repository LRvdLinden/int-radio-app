#if os(iOS) && canImport(CarPlay)
import UIKit
import CarPlay
import Combine

/// CarPlay (audio-app): tabbladen Favorieten, Recent, Populair ({land}), Podcasts (gevolgde podcasts →
/// afleveringen) en Genres.
/// Kiezen speelt af via RadioPlayer en toont CPNowPlayingTemplate.shared (knoppen via remote commands:
/// favoriet, vorige/volgende zender). Werkt pas op een echt toestel als Apple de entitlement
/// com.apple.developer.carplay-audio toekent (zie project.yml); de app bouwt en draait ook zonder.
///
/// De klasse staat in Info-iOS.plist als `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var favoritesTemplate: CPListTemplate?
    private var recentsTemplate: CPListTemplate?
    private var popularTemplate: CPListTemplate?
    private var genresTemplate: CPListTemplate?
    private var podcastsTemplate: CPListTemplate?
    private var rateButton: CPNowPlayingPlaybackRateButton?
    private var popular: [Station] = []
    private var bag = Set<AnyCancellable>()

    // MARK: Verbinden

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        // voor de anonieme statistieken: "ooit CarPlay gebruikt"
        UserDefaults.standard.set(true, forKey: StatsKey.carplayUsed)
        MainActor.assumeIsolated { self.connect() }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        bag.removeAll()
    }

    @MainActor private func connect() {
        let favorites = CPListTemplate(title: L("library.favorites"), sections: [])
        favorites.tabTitle = L("library.favorites")
        favorites.tabImage = UIImage(systemName: "heart.fill")
        favorites.emptyViewTitleVariants = [L("library.emptyFavorites")]
        favorites.emptyViewSubtitleVariants = [L("library.emptyFavoritesHint")]

        let recents = CPListTemplate(title: L("library.recent"), sections: [])
        recents.tabTitle = L("library.recent")
        recents.tabImage = UIImage(systemName: "clock.fill")
        recents.emptyViewTitleVariants = [L("library.emptyRecent")]

        let country = Library.shared.countryCode ?? "NL"
        let popularTitle = L("carplay.popular")
        let popularList = CPListTemplate(title: L("row.popularIn", Country.localizedName(code: country, fallback: country)), sections: [])
        popularList.tabTitle = popularTitle
        popularList.tabImage = UIImage(systemName: "flame.fill")
        popularList.emptyViewTitleVariants = [L("carplay.loading")]

        let genres = CPListTemplate(title: L("row.genres"), sections: [genreSection()])
        genres.tabTitle = L("row.genres")
        genres.tabImage = UIImage(systemName: "square.grid.2x2.fill")

        let podcasts = CPListTemplate(title: L("library.podcasts"), sections: [])
        podcasts.tabTitle = L("library.podcasts")
        podcasts.tabImage = UIImage(systemName: "mic.fill")
        podcasts.emptyViewTitleVariants = [L("library.emptyPodcasts")]
        podcasts.emptyViewSubtitleVariants = [L("carplay.podcastsHint")]

        favoritesTemplate = favorites
        recentsTemplate = recents
        popularTemplate = popularList
        genresTemplate = genres
        podcastsTemplate = podcasts

        // het aantal tabbladen is begrensd (maximumTabCount); Podcasts vóór Genres, zodat bij een limiet van 4
        // Genres afvalt en niet de podcasts
        let all: [CPTemplate] = [favorites, recents, popularList, podcasts, genres]
        let tabBar = CPTabBarTemplate(templates: Array(all.prefix(max(1, CPTabBarTemplate.maximumTabCount))))
        interfaceController?.setRootTemplate(tabBar, animated: false, completion: nil)

        refreshLibraryLists()
        Task { await loadPopular() }

        // bijwerken als favorieten/recent veranderen (ook via iCloud)
        Library.shared.changed
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLibraryLists() }
            }
            .store(in: &bag)
    }

    // MARK: Lijsten

    @MainActor private func refreshLibraryLists() {
        let lib = Library.shared
        favoritesTemplate?.updateSections([CPListSection(items: items(for: lib.favorites))])
        recentsTemplate?.updateSections([CPListSection(items: items(for: lib.recents))])
        podcastsTemplate?.updateSections(podcastSections())
    }

    // MARK: Podcasts

    @MainActor private func podcastSections() -> [CPListSection] {
        let lib = Library.shared
        var sections: [CPListSection] = []
        let continuing = Array(lib.continueListening.prefix(8))
        if !continuing.isEmpty {
            sections.append(CPListSection(items: episodeItems(continuing, showPodcast: true),
                                          header: L("row.continueEpisodes"), sectionIndexTitle: nil))
        }
        let max = min(lib.followedPodcasts.count, CPListTemplate.maximumItemCount)
        let podcastItems: [CPListItem] = lib.followedPodcasts.prefix(max).map { p in
            let item = CPListItem(text: p.displayName, detailText: p.artist, image: placeholder(name: p.displayName, monogram: p.monogram))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated { self?.openPodcast(p) }
                completion()
            }
            if let url = p.artworkURL {
                Task { @MainActor in
                    if let img = await ImageLoader.shared.load(url) { item.setImage(img) }
                }
            }
            return item
        }
        if !podcastItems.isEmpty {
            sections.append(CPListSection(items: podcastItems, header: L("podcasts.following"), sectionIndexTitle: nil))
        }
        return sections
    }

    @MainActor private func openPodcast(_ p: Podcast) {
        let template = CPListTemplate(title: p.displayName, sections: [])
        template.emptyViewTitleVariants = [L("carplay.loading")]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
        Task { @MainActor in
            let country = Library.shared.countryCode ?? "NL"
            let list = (try? await PodcastAPI.shared.lookup(p.id, country: country))?.episodes ?? []
            if list.isEmpty { template.emptyViewTitleVariants = [L("podcast.noEpisodes")] }
            template.updateSections([CPListSection(items: self.episodeItems(list, showPodcast: false))])
        }
    }

    @MainActor private func episodeItems(_ episodes: [Episode], showPodcast: Bool) -> [CPListItem] {
        let max = min(episodes.count, CPListTemplate.maximumItemCount)
        let list = Array(episodes.prefix(max))
        let lib = Library.shared
        return list.map { e in
            var detail = [showPodcast ? e.podcastName : PodcastFormat.date(e.date), PodcastFormat.duration(e.duration)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            if lib.position(for: e.id)?.finished == true { detail = "✓ " + detail }
            let item = CPListItem(text: e.displayTitle, detailText: detail,
                                  image: placeholder(name: e.podcastName, monogram: PodcastFormat.initials(e.podcastName)))
            item.isPlaying = RadioPlayer.shared.episode?.id == e.id
            if let p = lib.position(for: e.id), !p.finished, p.seconds > 0 {
                item.playbackProgress = CGFloat(p.fraction)
            }
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated {
                    RadioPlayer.shared.play(episode: e, queue: list)
                    self?.showNowPlaying()
                }
                completion()
            }
            if let url = e.artworkURL {
                Task { @MainActor in
                    if let img = await ImageLoader.shared.load(url) { item.setImage(img) }
                }
            }
            return item
        }
    }

    @MainActor private func loadPopular() async {
        let country = Library.shared.countryCode ?? "NL"
        guard let list = try? await RadioBrowser.shared.popular(country: country, limit: 40) else {
            popularTemplate?.emptyViewTitleVariants = [L("error.short")]
            return
        }
        popular = list
        popularTemplate?.updateSections([CPListSection(items: items(for: list))])
    }

    @MainActor private func items(for stations: [Station]) -> [CPListItem] {
        let max = min(stations.count, CPListTemplate.maximumItemCount)
        let list = Array(stations.prefix(max))
        return list.map { s in
            let detail = s.genreLine.isEmpty ? s.placeLine : s.genreLine
            let item = CPListItem(text: s.displayName, detailText: detail, image: placeholder(for: s))
            item.isPlaying = RadioPlayer.shared.station?.id == s.id
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated {
                    RadioPlayer.shared.play(s, queue: list)
                    self?.showNowPlaying()
                }
                completion()
            }
            if let url = s.logoURL {
                Task { @MainActor in
                    if let img = await ImageLoader.shared.load(url) { item.setImage(img) }
                }
            }
            return item
        }
    }

    @MainActor private func genreSection() -> CPListSection {
        let country = Library.shared.countryCode
        let items: [CPListItem] = Genre.all.map { g in
            let item = CPListItem(text: g.title, detailText: nil, image: UIImage(systemName: g.symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated { self?.openGenre(g, country: country) }
                completion()
            }
            return item
        }
        return CPListSection(items: items)
    }

    @MainActor private func openGenre(_ g: Genre, country: String?) {
        let template = CPListTemplate(title: g.title, sections: [])
        template.emptyViewTitleVariants = [L("carplay.loading")]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
        Task { @MainActor in
            let list = (try? await RadioBrowser.shared.byTag(g.tag, country: country, limit: 40)) ?? []
            if list.isEmpty { template.emptyViewTitleVariants = [L("empty.noStations")] }
            template.updateSections([CPListSection(items: self.items(for: list))])
        }
    }

    @MainActor private func showNowPlaying() {
        let np = CPNowPlayingTemplate.shared
        np.isUpNextButtonEnabled = false
        np.isAlbumArtistButtonEnabled = false
        // aflevering: snelheidsknop (0,8× … 2×); radio: geen extra knoppen
        if RadioPlayer.shared.isEpisode {
            if rateButton == nil {
                rateButton = CPNowPlayingPlaybackRateButton(handler: { _ in
                    MainActor.assumeIsolated { RadioPlayer.shared.cycleRate() }
                })
            }
            if let button = rateButton { np.updateNowPlayingButtons([button]) }
        } else {
            np.updateNowPlayingButtons([])
        }
        guard let ic = interfaceController else { return }
        if ic.topTemplate === np { return }
        ic.pushTemplate(np, animated: true, completion: nil)
    }

    /// Monogram-tegel in de zenderkleuren zolang het logo laadt
    @MainActor private func placeholder(for s: Station) -> UIImage {
        placeholder(name: s.displayName, monogram: s.monogram)
    }

    @MainActor private func placeholder(name: String, monogram: String) -> UIImage {
        let size = CGSize(width: 88, height: 88)
        let colors = Self.paletteColors(for: name)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
            path.addClip()
            let cg = ctx.cgContext
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let text = monogram as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
        }
    }

    private static let paletteHex: [(UInt32, UInt32)] = [
        (0xFF5A1F, 0xFFB020), (0x7C3AED, 0xDB2777), (0x0EA5E9, 0x22D3EE), (0x10B981, 0x84CC16),
        (0xF43F5E, 0xFB923C), (0x6366F1, 0x06B6D4), (0xEAB308, 0xF97316), (0x14B8A6, 0x3B82F6),
    ]

    private static func paletteColors(for name: String) -> (UIColor, UIColor) {
        var h: UInt32 = 2166136261
        for b in name.lowercased().utf8 { h ^= UInt32(b); h = h &* 16777619 }
        let p = paletteHex[Int(h % UInt32(paletteHex.count))]
        return (uiColor(p.0), uiColor(p.1))
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif
