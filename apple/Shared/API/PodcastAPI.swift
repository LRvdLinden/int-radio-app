import Foundation

/// Fouten van de podcastbronnen
enum PodcastAPIError: Error {
    case badURL
    case badResponse(Int)
}

/// Podcasts zonder sleutels (SPEC §8):
/// - toplijst per land: rss.applemarketingtools.com (v2 JSON), valt terug op `us`;
/// - toplijst per genre: oude iTunes-RSS (JSON) met `genre=<id>`;
/// - zoeken: itunes.apple.com/search (media=podcast);
/// - podcast + afleveringen: itunes.apple.com/lookup (entity=podcastEpisode, limit 100).
/// Antwoorden in het geheugen en op schijf (toplijsten 6 uur, afleveringen 30 minuten, zoeken 10 minuten).
final class PodcastAPI: @unchecked Sendable {
    static let shared = PodcastAPI()

    static let chartsTTL: TimeInterval = 6 * 3600
    static let episodesTTL: TimeInterval = 30 * 60
    static let searchTTL: TimeInterval = 10 * 60

    private let lock = NSLock()
    private var memory: [String: (date: Date, data: Data)] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    private let cacheDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Podcasts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Verzoeken

    private func get(_ url: URL, ttl: TimeInterval) async throws -> Data {
        let key = url.absoluteString
        if ttl > 0, let hit = cached(key, ttl: ttl) { return hit }
        var req = URLRequest(url: url)
        req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(code) else { throw PodcastAPIError.badResponse(code) }
            if ttl > 0 { store(key, data) }
            return data
        } catch {
            if (error as? URLError)?.code == .cancelled || Task.isCancelled { throw error }
            // offline: dan maar een verlopen kopie
            if ttl > 0, let stale = cached(key, ttl: .infinity) { return stale }
            throw error
        }
    }

    private func fileURL(for key: String) -> URL? {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return cacheDir?.appendingPathComponent(String(h, radix: 16) + ".json")
    }

    private func cached(_ key: String, ttl: TimeInterval) -> Data? {
        if let m = lock.withLock({ memory[key] }), Date().timeIntervalSince(m.date) < ttl { return m.data }
        guard let file = fileURL(for: key),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let date = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < ttl,
              let data = try? Data(contentsOf: file) else { return nil }
        lock.withLock { memory[key] = (date, data) }
        return data
    }

    private func store(_ key: String, _ data: Data) {
        lock.withLock {
            memory[key] = (Date(), data)
            if memory.count > 120 { memory.removeAll(keepingCapacity: true) }
        }
        if let file = fileURL(for: key) { try? data.write(to: file, options: .atomic) }
    }

    private func itunesURL(_ path: String, _ query: [String: String]) -> URL? {
        var comps = URLComponents(string: "https://itunes.apple.com" + path)
        comps?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps?.url
    }

    // MARK: - Endpoints

    /// Top 50 van het land (genummerd), anders die van de VS
    func topPodcasts(country: String) async throws -> [Podcast] {
        let cc = country.lowercased()
        if let list = try? await charts(cc), !list.isEmpty { return list }
        if cc != "us" { return try await charts("us") }
        return []
    }

    private func charts(_ cc: String) async throws -> [Podcast] {
        guard let url = URL(string: "https://rss.applemarketingtools.com/api/v2/\(cc)/podcasts/top/50/podcasts.json") else {
            throw PodcastAPIError.badURL
        }
        let data = try await get(url, ttl: Self.chartsTTL)
        let feed = try JSONDecoder().decode(ChartsResponse.self, from: data)
        return feed.feed.results.items.compactMap(\.podcast)
    }

    /// Toplijst per genre (oude iTunes-RSS), terugval `us`
    func topPodcasts(genre: Int, country: String) async throws -> [Podcast] {
        let cc = country.lowercased()
        if let list = try? await genreChart(genre, cc), !list.isEmpty { return list }
        if cc != "us" { return try await genreChart(genre, "us") }
        return []
    }

    private func genreChart(_ genre: Int, _ cc: String) async throws -> [Podcast] {
        guard let url = URL(string: "https://itunes.apple.com/\(cc)/rss/toppodcasts/limit=50/genre=\(genre)/json") else {
            throw PodcastAPIError.badURL
        }
        let data = try await get(url, ttl: Self.chartsTTL)
        let feed = try JSONDecoder().decode(OldRSSResponse.self, from: data)
        return feed.feed.entries.compactMap(\.podcast)
    }

    /// Zoeken in iTunes
    func search(_ term: String, country: String) async throws -> [Podcast] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        guard let url = itunesURL("/search", ["media": "podcast", "entity": "podcast", "term": q,
                                              "country": country.lowercased(), "limit": "50"]) else {
            throw PodcastAPIError.badURL
        }
        let data = try await get(url, ttl: Self.searchTTL)
        let r = try JSONDecoder().decode(LookupResponse.self, from: data)
        var seen = Set<String>()
        return r.results.items.compactMap(\.podcast).filter { seen.insert($0.id).inserted }
    }

    /// Podcast + (max. 100) afleveringen, nieuwste eerst
    func lookup(_ podcastId: String, country: String) async throws -> (podcast: Podcast?, episodes: [Episode]) {
        guard let url = itunesURL("/lookup", ["id": podcastId, "entity": "podcastEpisode", "limit": "100",
                                              "country": country.lowercased()]) else {
            throw PodcastAPIError.badURL
        }
        let data = try await get(url, ttl: Self.episodesTTL)
        let r = try JSONDecoder().decode(LookupResponse.self, from: data)
        let podcast = r.results.items.first(where: { $0.isPodcast })?.podcast
        let name = podcast?.name ?? ""
        var seen = Set<String>()
        let episodes = r.results.items
            .compactMap { $0.episode(podcastId: podcastId, podcastName: name, fallbackArt: podcast?.artworkURL) }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return (podcast, episodes)
    }

    /// Alleen de nieuwste aflevering (voor "Nieuwe afleveringen")
    func latestEpisode(_ podcastId: String, country: String) async -> Episode? {
        (try? await lookup(podcastId, country: country))?.episodes.first
    }

    /// Beschrijving van de podcast uit de RSS-feed (iTunes lookup levert die niet). Leest alleen het kanaal,
    /// tot de eerste `<item>`. Gecachet (6 uur); lege tekst als het niet lukt.
    func feedDescription(_ feedURL: String) async -> String {
        guard let url = URL(string: feedURL.trimmingCharacters(in: .whitespaces)), feedURL.hasPrefix("http") else { return "" }
        let key = "feed-desc|" + url.absoluteString
        if let hit = cached(key, ttl: Self.chartsTTL) { return String(decoding: hit, as: UTF8.self) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        // de eerste ~256 kB is genoeg voor het kanaal
        req.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
        guard let (data, _) = try? await session.data(for: req) else { return "" }
        let text = PodcastFormat.plainText(ChannelDescriptionParser.parse(data))
        store(key, Data(text.utf8))
        return text
    }

    // MARK: - Hulpjes

    /// `100x100bb` / `600x600bb` e.d. → `600x600bb`
    static func artwork(_ raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("http") else { return nil }
        s = s.replacingOccurrences(of: "[0-9]{2,4}x[0-9]{2,4}(bb|cc|-[0-9]+)?(\\.[a-z]+)$",
                                   with: "600x600bb$2", options: .regularExpression)
        return URL(string: s)
    }

    static let isoDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let d = isoDate.date(from: s) { return d }
        return dayDate.date(from: String(s.prefix(10)))
    }
}

// MARK: - Antwoorden (tolerant)

/// rss.applemarketingtools.com v2
private struct ChartsResponse: Decodable {
    struct Feed: Decodable {
        var results: LossyArray<Item>
        enum CodingKeys: String, CodingKey { case results }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            results = (try? c.decode(LossyArray<Item>.self, forKey: .results)) ?? LossyArray(items: [])
        }
    }
    struct Genre: Decodable { var name: String? }
    struct Item: Decodable {
        var id: String
        var name: String
        var artistName: String
        var artworkUrl100: String
        var genre: String
        var url: String

        enum CodingKeys: String, CodingKey { case id, name, artistName, artworkUrl100, genres, url }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.flexString(.id)
            name = c.flexString(.name)
            artistName = c.flexString(.artistName)
            artworkUrl100 = c.flexString(.artworkUrl100)
            url = c.flexString(.url)
            let genres = (try? c.decode([Genre].self, forKey: .genres)) ?? []
            genre = genres.compactMap(\.name).first { $0 != "Podcasts" } ?? ""
        }

        var podcast: Podcast? {
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return Podcast(id: id, name: name, artist: artistName, artworkURL: PodcastAPI.artwork(artworkUrl100),
                           genre: genre, pageURL: URL(string: url))
        }
    }
    var feed: Feed
}

/// Oude iTunes-RSS (`feed.entry[]` met `label`-objecten)
private struct OldRSSResponse: Decodable {
    struct Label: Decodable {
        var label: String?
        var attributes: [String: String]?
    }
    struct Entry: Decodable {
        var name: String
        var artist: String
        var image: String
        var id: String
        var genre: String
        var link: String

        enum CodingKeys: String, CodingKey {
            case name = "im:name", artist = "im:artist", image = "im:image", id, category, link
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decode(Label.self, forKey: .name))?.label ?? ""
            artist = (try? c.decode(Label.self, forKey: .artist))?.label ?? ""
            let images = (try? c.decode([Label].self, forKey: .image)) ?? []
            image = images.last?.label ?? ""
            let idLabel = try? c.decode(Label.self, forKey: .id)
            id = idLabel?.attributes?["im:id"] ?? ""
            link = idLabel?.label ?? ""
            genre = (try? c.decode(Label.self, forKey: .category))?.attributes?["label"] ?? ""
        }

        var podcast: Podcast? {
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return Podcast(id: id, name: name, artist: artist, artworkURL: PodcastAPI.artwork(image), genre: genre,
                           pageURL: URL(string: link))
        }
    }
    struct Feed: Decodable {
        var entries: [Entry]
        enum CodingKeys: String, CodingKey { case entry }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // bij één resultaat is `entry` soms een object in plaats van een lijst
            if let list = try? c.decode(LossyArray<Entry>.self, forKey: .entry) {
                entries = list.items
            } else if let one = try? c.decode(Entry.self, forKey: .entry) {
                entries = [one]
            } else {
                entries = []
            }
        }
    }
    var feed: Feed
}

/// itunes.apple.com/search en /lookup
private struct LookupResponse: Decodable {
    struct Item: Decodable {
        var wrapperType: String
        var kind: String
        var collectionId: String
        var collectionName: String
        var trackId: String
        var trackName: String
        var artistName: String
        var artworkUrl600: String
        var artworkUrl100: String
        var artworkUrl160: String
        var primaryGenreName: String
        var trackCount: Int
        var feedUrl: String
        var releaseDate: String
        var trackTimeMillis: Double
        var episodeUrl: String
        var description: String
        var shortDescription: String
        var collectionViewUrl: String
        var trackViewUrl: String

        enum CodingKeys: String, CodingKey {
            case wrapperType, kind, collectionId, collectionName, trackId, trackName, artistName
            case artworkUrl600, artworkUrl100, artworkUrl160, primaryGenreName, trackCount, feedUrl, releaseDate
            case trackTimeMillis, episodeUrl, description, shortDescription, collectionViewUrl, trackViewUrl
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            wrapperType = c.flexString(.wrapperType)
            kind = c.flexString(.kind)
            collectionId = c.flexString(.collectionId)
            collectionName = c.flexString(.collectionName)
            trackId = c.flexString(.trackId)
            trackName = c.flexString(.trackName)
            artistName = c.flexString(.artistName)
            artworkUrl600 = c.flexString(.artworkUrl600)
            artworkUrl100 = c.flexString(.artworkUrl100)
            artworkUrl160 = c.flexString(.artworkUrl160)
            primaryGenreName = c.flexString(.primaryGenreName)
            trackCount = c.flexInt(.trackCount)
            feedUrl = c.flexString(.feedUrl)
            releaseDate = c.flexString(.releaseDate)
            trackTimeMillis = c.flexDouble(.trackTimeMillis) ?? 0
            episodeUrl = c.flexString(.episodeUrl)
            description = c.flexString(.description)
            shortDescription = c.flexString(.shortDescription)
            collectionViewUrl = c.flexString(.collectionViewUrl)
            trackViewUrl = c.flexString(.trackViewUrl)
        }

        var isPodcast: Bool { wrapperType != "podcastEpisode" && (kind == "podcast" || wrapperType == "track" || wrapperType == "collection") }

        private var bestArt: String {
            [artworkUrl600, artworkUrl160, artworkUrl100].first { !$0.isEmpty } ?? ""
        }

        var podcast: Podcast? {
            guard isPodcast, !collectionId.isEmpty, !collectionName.isEmpty else { return nil }
            return Podcast(id: collectionId, name: collectionName, artist: artistName,
                           artworkURL: PodcastAPI.artwork(bestArt), genre: primaryGenreName == "Podcasts" ? "" : primaryGenreName,
                           feedURL: feedUrl, trackCount: trackCount,
                           pageURL: URL(string: collectionViewUrl))
        }

        func episode(podcastId: String, podcastName: String, fallbackArt: URL?) -> Episode? {
            guard wrapperType == "podcastEpisode" || kind == "podcast-episode", !trackId.isEmpty,
                  let audio = URL(string: episodeUrl.trimmingCharacters(in: .whitespaces)), episodeUrl.hasPrefix("http") else { return nil }
            let text = description.isEmpty ? shortDescription : description
            return Episode(id: trackId,
                           podcastId: podcastId,
                           podcastName: collectionName.isEmpty ? podcastName : collectionName,
                           title: trackName,
                           summary: PodcastFormat.plainText(text),
                           date: PodcastAPI.parseDate(releaseDate),
                           duration: trackTimeMillis > 0 ? trackTimeMillis / 1000 : 0,
                           audioURL: audio,
                           artworkURL: PodcastAPI.artwork(bestArt) ?? fallbackArt,
                           pageURL: URL(string: trackViewUrl))
        }
    }
    var results: LossyArray<Item>
    enum CodingKeys: String, CodingKey { case results }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decode(LossyArray<Item>.self, forKey: .results)) ?? LossyArray(items: [])
    }
}

// MARK: - RSS-kanaalbeschrijving

/// Haalt `<itunes:summary>` of `<description>` van het kanaal uit een RSS-feed (stopt bij de eerste `<item>`).
private final class ChannelDescriptionParser: NSObject, XMLParserDelegate {
    private var depthInItem = false
    private var current = ""
    private var element = ""
    private var summary = ""
    private var description = ""

    static func parse(_ data: Data) -> String {
        let p = ChannelDescriptionParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        let s = p.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = p.description.trimmingCharacters(in: .whitespacesAndNewlines)
        // de langste van de twee is meestal de volledige tekst
        return d.count >= s.count ? d : s
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" {
            depthInItem = true
            parser.abortParsing()
            return
        }
        element = elementName
        current = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !depthInItem else { return }
        if element == "description" || element == "itunes:summary" { current += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !depthInItem else { return }
        if element == "description" || element == "itunes:summary" { current += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard !depthInItem else { return }
        if elementName == "description", description.isEmpty { description = current }
        if elementName == "itunes:summary", summary.isEmpty { summary = current }
        element = ""
        current = ""
    }
}
