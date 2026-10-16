import Foundation

// MARK: - Podcast

/// Een podcast uit de iTunes-/Apple-toplijsten of iTunes Search (SPEC §8). `id` = iTunes `collectionId`.
/// Velden die een bron niet levert blijven leeg (de toplijst heeft bv. geen feedURL of aantal afleveringen).
struct Podcast: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var artist: String
    var artworkURL: URL?
    var genre: String
    var feedURL: String
    var trackCount: Int
    /// Pagina in Apple Podcasts (om te delen)
    var pageURL: URL?

    init(id: String, name: String, artist: String = "", artworkURL: URL? = nil, genre: String = "",
         feedURL: String = "", trackCount: Int = 0, pageURL: URL? = nil) {
        self.id = id; self.name = name; self.artist = artist; self.artworkURL = artworkURL; self.genre = genre
        self.feedURL = feedURL; self.trackCount = trackCount; self.pageURL = pageURL
    }

    /// Weergavenaam (nooit leeg)
    var displayName: String { name.isEmpty ? "Podcast" : name }

    /// "Maker · Genre"
    var detailLine: String { [artist, genre].filter { !$0.isEmpty }.joined(separator: " · ") }

    var monogram: String { PodcastFormat.initials(displayName) }

    /// Lege velden aanvullen met die van een andere bron (bv. toplijst + lookup)
    func merged(with other: Podcast) -> Podcast {
        var p = self
        if p.name.isEmpty { p.name = other.name }
        if p.artist.isEmpty { p.artist = other.artist }
        if p.artworkURL == nil { p.artworkURL = other.artworkURL }
        if p.genre.isEmpty { p.genre = other.genre }
        if p.feedURL.isEmpty { p.feedURL = other.feedURL }
        if p.trackCount == 0 { p.trackCount = other.trackCount }
        if p.pageURL == nil { p.pageURL = other.pageURL }
        return p
    }

    static func == (a: Podcast, b: Podcast) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Aflevering

/// Eén aflevering (iTunes lookup, `wrapperType: "podcastEpisode"`). `id` = `trackId`.
struct Episode: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var podcastId: String
    var podcastName: String
    var title: String
    var summary: String
    var date: Date?
    /// Duur in seconden (0 = onbekend)
    var duration: Double
    var audioURL: URL?
    var artworkURL: URL?
    var pageURL: URL?

    init(id: String, podcastId: String, podcastName: String, title: String, summary: String = "", date: Date? = nil,
         duration: Double = 0, audioURL: URL? = nil, artworkURL: URL? = nil, pageURL: URL? = nil) {
        self.id = id; self.podcastId = podcastId; self.podcastName = podcastName; self.title = title
        self.summary = summary; self.date = date; self.duration = duration; self.audioURL = audioURL
        self.artworkURL = artworkURL; self.pageURL = pageURL
    }

    var displayTitle: String { title.isEmpty ? podcastName : title }

    /// Korte omschrijving (eerste regels, max. 220 tekens)
    var shortSummary: String {
        let flat = summary.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 220 ? String(flat.prefix(220)) + "…" : flat
    }

    /// Kleine kopie om te bewaren (iCloud KV is beperkt): omschrijving ingekort
    var compact: Episode {
        var e = self
        if e.summary.count > 300 { e.summary = String(e.summary.prefix(300)) + "…" }
        return e
    }

    /// Een minimale podcast om naar de podcastpagina te gaan
    var podcastStub: Podcast { Podcast(id: podcastId, name: podcastName, artworkURL: artworkURL) }

    static func == (a: Episode, b: Episode) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Afspeelpositie van een aflevering (seconden, duur, beluisterd)
struct EpisodePosition: Codable, Hashable, Sendable {
    var seconds: Double
    var duration: Double
    var finished: Bool
    var updated: Date

    /// 0…1
    var fraction: Double { duration > 0 ? min(1, max(0, seconds / duration)) : 0 }
}

/// Sorteren van de afleveringenlijst
enum EpisodeSort: String, CaseIterable, Identifiable {
    case newest, oldest
    var id: String { rawValue }
    var title: String { self == .newest ? L("podcast.sortNewest") : L("podcast.sortOldest") }
}

// MARK: - Podcastgenres

/// Genre-tegels (iTunes genre-id's, SPEC §8)
struct PodcastGenre: Identifiable, Hashable, Sendable {
    let id: Int
    let key: String
    let symbol: String
    var title: String { L(key) }

    static let all: [PodcastGenre] = [
        PodcastGenre(id: 1489, key: "pgenre.news", symbol: "newspaper.fill"),
        PodcastGenre(id: 1303, key: "pgenre.comedy", symbol: "theatermasks.fill"),
        PodcastGenre(id: 1545, key: "pgenre.sports", symbol: "sportscourt.fill"),
        PodcastGenre(id: 1488, key: "pgenre.trueCrime", symbol: "magnifyingglass"),
        PodcastGenre(id: 1324, key: "pgenre.society", symbol: "person.3.fill"),
        PodcastGenre(id: 1321, key: "pgenre.business", symbol: "briefcase.fill"),
        PodcastGenre(id: 1512, key: "pgenre.health", symbol: "heart.text.square.fill"),
        PodcastGenre(id: 1487, key: "pgenre.history", symbol: "building.columns.fill"),
        PodcastGenre(id: 1533, key: "pgenre.science", symbol: "atom"),
        PodcastGenre(id: 1318, key: "pgenre.technology", symbol: "cpu"),
        PodcastGenre(id: 1305, key: "pgenre.kids", symbol: "figure.2.and.child.holdinghands"),
        PodcastGenre(id: 1310, key: "pgenre.music", symbol: "music.note.list"),
    ]
}

// MARK: - Opmaak

enum PodcastFormat {
    /// Initialen voor het monogram
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).filter { !$0.isEmpty }
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    /// "1:02:03" of "2:03"
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1 u 5 min" / "45 min" (leeg als onbekend)
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? L("time.hours", h) : L("time.hoursMinutes", h, m)
        }
        return L("time.minutes", minutes)
    }

    /// "Vandaag", "Gisteren", "12 okt" of "12 okt 2024"
    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("date.today") }
        if cal.isDateInYesterday(date) { return L("date.yesterday") }
        let locale = Localizer.shared.locale
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale))
        }
        return date.formatted(Date.FormatStyle().day().month(.abbreviated).year().locale(locale))
    }

    /// "1,25×"
    static func rate(_ r: Float) -> String {
        let f = NumberFormatter()
        f.locale = Localizer.shared.locale
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: Double(r))) ?? String(r)) + "×"
    }

    /// HTML (beschrijvingen uit feeds/iTunes) naar platte tekst
    static func plainText(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var s = raw.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</p>|</li>|</div>|</h[1-6]>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&rdquo;", "”"), ("&ldquo;", "“"), ("&hellip;", "…"), ("&ndash;", "–"), ("&mdash;", "—"),
            ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        // numerieke entiteiten (&#8217; en &#x2019;)
        if s.contains("&#"), let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = s as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let digits = ns.substring(with: m.range(at: 2))
                if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    out.unicodeScalars.append(scalar)
                }
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            s = out
        }
        s = s.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
