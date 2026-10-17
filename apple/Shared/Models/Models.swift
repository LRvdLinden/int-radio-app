import Foundation
import CoreLocation

// MARK: - Zender

/// Eén radiozender uit Radio Browser. Tolerant gedecodeerd: velden mogen ontbreken, getallen kunnen als tekst
/// komen (en omgekeerd), `geo_lat`/`geo_long` zijn vaak `null`.
struct Station: Codable, Identifiable, Hashable, Sendable {
    var id: String              // stationuuid
    var name: String
    var url: String
    var urlResolved: String
    var homepage: String
    var favicon: String
    var tags: String
    var country: String
    var countryCode: String
    var state: String
    var language: String
    var codec: String
    var bitrate: Int
    var hls: Bool
    var votes: Int
    var clickCount: Int
    var clickTrend: Int
    var lastCheckOK: Bool
    var geoLat: Double?
    var geoLong: Double?

    enum CodingKeys: String, CodingKey {
        case id = "stationuuid", name, url
        case urlResolved = "url_resolved"
        case homepage, favicon, tags, country
        case countryCode = "countrycode"
        case state, language, codec, bitrate, hls, votes
        case clickCount = "clickcount"
        case clickTrend = "clicktrend"
        case lastCheckOK = "lastcheckok"
        case geoLat = "geo_lat"
        case geoLong = "geo_long"
    }

    init(id: String, name: String, url: String, urlResolved: String = "", homepage: String = "", favicon: String = "",
         tags: String = "", country: String = "", countryCode: String = "", state: String = "", language: String = "",
         codec: String = "", bitrate: Int = 0, hls: Bool = false, votes: Int = 0, clickCount: Int = 0, clickTrend: Int = 0,
         lastCheckOK: Bool = true, geoLat: Double? = nil, geoLong: Double? = nil) {
        self.id = id; self.name = name; self.url = url; self.urlResolved = urlResolved; self.homepage = homepage
        self.favicon = favicon; self.tags = tags; self.country = country; self.countryCode = countryCode
        self.state = state; self.language = language; self.codec = codec; self.bitrate = bitrate; self.hls = hls
        self.votes = votes; self.clickCount = clickCount; self.clickTrend = clickTrend; self.lastCheckOK = lastCheckOK
        self.geoLat = geoLat; self.geoLong = geoLong
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id)
        name = c.flexString(.name).trimmingCharacters(in: .whitespacesAndNewlines)
        url = c.flexString(.url).trimmingCharacters(in: .whitespacesAndNewlines)
        urlResolved = c.flexString(.urlResolved).trimmingCharacters(in: .whitespacesAndNewlines)
        homepage = c.flexString(.homepage).trimmingCharacters(in: .whitespacesAndNewlines)
        favicon = c.flexString(.favicon).trimmingCharacters(in: .whitespacesAndNewlines)
        tags = c.flexString(.tags)
        country = c.flexString(.country)
        countryCode = c.flexString(.countryCode).uppercased()
        state = c.flexString(.state).trimmingCharacters(in: .whitespacesAndNewlines)
        language = c.flexString(.language)
        codec = c.flexString(.codec)
        bitrate = c.flexInt(.bitrate)
        hls = c.flexInt(.hls) != 0
        votes = c.flexInt(.votes)
        clickCount = c.flexInt(.clickCount)
        clickTrend = c.flexInt(.clickTrend)
        lastCheckOK = (c.flexIntOptional(.lastCheckOK) ?? 1) != 0
        geoLat = c.flexDouble(.geoLat)
        geoLong = c.flexDouble(.geoLong)
        if id.isEmpty { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "geen stationuuid") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encode(urlResolved, forKey: .urlResolved)
        try c.encode(homepage, forKey: .homepage)
        try c.encode(favicon, forKey: .favicon)
        try c.encode(tags, forKey: .tags)
        try c.encode(country, forKey: .country)
        try c.encode(countryCode, forKey: .countryCode)
        try c.encode(state, forKey: .state)
        try c.encode(language, forKey: .language)
        try c.encode(codec, forKey: .codec)
        try c.encode(bitrate, forKey: .bitrate)
        try c.encode(hls ? 1 : 0, forKey: .hls)
        try c.encode(votes, forKey: .votes)
        try c.encode(clickCount, forKey: .clickCount)
        try c.encode(clickTrend, forKey: .clickTrend)
        try c.encode(lastCheckOK ? 1 : 0, forKey: .lastCheckOK)
        try c.encodeIfPresent(geoLat, forKey: .geoLat)
        try c.encodeIfPresent(geoLong, forKey: .geoLong)
    }

    // MARK: Afgeleide waarden

    /// Weergavenaam (nooit leeg)
    var displayName: String { name.isEmpty ? "Radio" : name }

    /// `url_resolved`, anders `url`
    var streamURL: URL? { URL(string: urlResolved.isEmpty ? url : urlResolved) ?? URL(string: url) }
    /// Terugval als `url_resolved` niet speelt
    var fallbackURL: URL? {
        guard !urlResolved.isEmpty, urlResolved != url else { return nil }
        return URL(string: url)
    }

    /// Logo uit Radio Browser (`favicon`), zoals opgegeven. Voor weergave: `logoCandidates` (met terugval).
    var logoURL: URL? {
        guard !favicon.isEmpty, favicon.hasPrefix("http") else { return nil }
        return URL(string: favicon)
    }

    /// Logo-bronnen in volgorde (favicon, Google- en DuckDuckGo-favicondienst op het domein van de homepage);
    /// zie `LogoSources`.
    var logoCandidates: [URL] { LogoSources.candidates(for: self) }

    var homepageURL: URL? {
        guard !homepage.isEmpty, homepage.hasPrefix("http") else { return nil }
        return URL(string: homepage)
    }

    /// Genres, opgeschoond (max. 6, uniek, zonder lege of extreem lange tags)
    var tagList: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags.split(separator: ",") {
            let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !t.isEmpty, t.count <= 24, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
            if out.count == 6 { break }
        }
        return out
    }

    /// "pop · rock · hits"
    var genreLine: String { tagList.prefix(3).map { $0.capitalized }.joined(separator: " · ") }

    var flag: String { Country.flag(for: countryCode) }

    /// "Utrecht · Nederland 🇳🇱"
    var placeLine: String {
        let land = Country.localizedName(code: countryCode, fallback: country)
        let parts = [state, land].filter { !$0.isEmpty }
        let text = parts.joined(separator: " · ")
        return flag.isEmpty ? text : "\(text) \(flag)"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = geoLat, let lon = geoLong, abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// "128 kbps" of leeg
    var bitrateText: String { bitrate > 0 ? "\(bitrate) kbps" : "" }

    /// Sleutel voor het samenvoegen van dubbele zenders (zelfde naam + zelfde stream)
    var dedupKey: String { name.lowercased() + "|" + (urlResolved.isEmpty ? url : urlResolved).lowercased() }

    /// Initialen voor het monogram ("Radio 538" → "R5", "NPO Radio 1" → "NR")
    var monogram: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).filter { !$0.isEmpty }
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]).uppercased() }
        return String(displayName.prefix(2)).uppercased()
    }

    static func == (a: Station, b: Station) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension Array where Element == Station {
    /// Dubbele zenders (zelfde naam + zelfde stream of zelfde uuid) eruit, volgorde behouden.
    func deduplicated() -> [Station] {
        var keys = Set<String>()
        var ids = Set<String>()
        var out: [Station] = []
        out.reserveCapacity(count)
        for s in self where !s.name.isEmpty && s.streamURL != nil {
            guard !ids.contains(s.id), !keys.contains(s.dedupKey) else { continue }
            ids.insert(s.id)
            keys.insert(s.dedupKey)
            out.append(s)
        }
        return out
    }
}

// MARK: - Land

struct Country: Codable, Identifiable, Hashable, Sendable {
    var name: String          // Engelse naam uit Radio Browser (nodig voor /json/states/{naam})
    var code: String          // ISO 3166-1
    var stationCount: Int

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case name, code = "iso_3166_1", stationCount = "stationcount"
    }

    init(name: String, code: String, stationCount: Int) {
        self.name = name; self.code = code.uppercased(); self.stationCount = stationCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexString(.name)
        code = c.flexString(.code).uppercased()
        stationCount = c.flexInt(.stationCount)
    }

    var flag: String { Country.flag(for: code) }
    var localizedName: String { Country.localizedName(code: code, fallback: name) }

    /// Vlag-emoji uit de ISO-code ("NL" → 🇳🇱)
    static func flag(for code: String) -> String {
        let c = code.uppercased()
        guard c.count == 2, c.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "" }
        var out = ""
        for scalar in c.unicodeScalars {
            if let s = UnicodeScalar(127397 + scalar.value) { out.unicodeScalars.append(s) }
        }
        return out
    }

    /// Landnaam in de taal van de app
    static func localizedName(code: String, fallback: String) -> String {
        guard !code.isEmpty else { return fallback }
        return Localizer.shared.locale.localizedString(forRegionCode: code.uppercased()) ?? fallback
    }

    /// Het land van het toestel ("NL")
    static var deviceCode: String {
        Locale.current.region?.identifier.uppercased() ?? "NL"
    }
}

// MARK: - Regio (provincie / staat)

struct RegionState: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var country: String
    var stationCount: Int
    var id: String { country + "|" + name }

    enum CodingKeys: String, CodingKey { case name, country, stationCount = "stationcount" }

    init(name: String, country: String, stationCount: Int) {
        self.name = name; self.country = country; self.stationCount = stationCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexString(.name).trimmingCharacters(in: .whitespacesAndNewlines)
        country = c.flexString(.country)
        stationCount = c.flexInt(.stationCount)
    }
}

/// De gekozen "Lokaal"-regio (opgeslagen met landcode, zodat hij bij een ander land vervalt)
struct LocalRegion: Codable, Hashable, Sendable {
    var countryCode: String
    var name: String
}

// MARK: - Kaart-zoekopdracht

/// Een gekozen land of plaats op de kaart (SPEC §9); bewaard als recente kaartzoekopdracht (max 5).
/// Een plaats bewaart zijn coördinaat, zodat hij later zonder geocoder opnieuw gekozen kan worden.
struct MapSearchItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case country, place }

    var kind: Kind
    /// Land: Engelse naam (weergave gelokaliseerd via de code); plaats: naam ("Berlijn")
    var title: String
    /// Plaats: regio/land ("Duitsland"); land: leeg
    var subtitle: String
    /// ISO 3166-1 ("DE"); kan leeg zijn bij een plaats
    var countryCode: String
    /// Alleen bij een land
    var stationCount: Int
    var latitude: Double?
    var longitude: Double?

    var id: String { kind.rawValue + "|" + countryCode + "|" + title.lowercased() + "|" + subtitle.lowercased() }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var flag: String { Country.flag(for: countryCode) }

    /// Naam in de taal van de app
    var displayTitle: String {
        kind == .country ? Country.localizedName(code: countryCode, fallback: title) : title
    }

    static func country(_ c: Country) -> MapSearchItem {
        MapSearchItem(kind: .country, title: c.name, subtitle: "", countryCode: c.code, stationCount: c.stationCount,
                      latitude: nil, longitude: nil)
    }
}

// MARK: - Taal

struct LanguageInfo: Codable, Identifiable, Hashable, Sendable {
    var name: String          // "dutch", "english" (Radio Browser: Engelse namen in kleine letters)
    var code: String          // "nl" (iso_639, soms leeg)
    var stationCount: Int
    var id: String { name }

    enum CodingKeys: String, CodingKey { case name, code = "iso_639", stationCount = "stationcount" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexString(.name)
        code = c.flexString(.code)
        stationCount = c.flexInt(.stationCount)
    }

    /// Gelokaliseerd waar mogelijk ("dutch" → "Nederlands")
    var displayName: String {
        if !code.isEmpty, let s = Localizer.shared.locale.localizedString(forLanguageCode: code) {
            return s.prefix(1).uppercased() + s.dropFirst()
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

// MARK: - Genres

/// Vaste genrelijst (SPEC §4): label-sleutel + Radio Browser-tag + SF Symbol
struct Genre: Identifiable, Hashable, Sendable {
    let tag: String
    let key: String
    let symbol: String
    var id: String { tag }
    var title: String { L(key) }

    static let all: [Genre] = [
        Genre(tag: "pop", key: "genre.pop", symbol: "music.mic"),
        Genre(tag: "news", key: "genre.news", symbol: "newspaper"),
        Genre(tag: "rock", key: "genre.rock", symbol: "guitars"),
        Genre(tag: "dance", key: "genre.dance", symbol: "figure.dance"),
        Genre(tag: "jazz", key: "genre.jazz", symbol: "music.quarternote.3"),
        Genre(tag: "classical", key: "genre.classical", symbol: "music.note.house"),
        Genre(tag: "hits", key: "genre.hits", symbol: "star"),
        Genre(tag: "talk", key: "genre.talk", symbol: "bubble.left.and.bubble.right"),
        Genre(tag: "sports", key: "genre.sports", symbol: "sportscourt"),
        Genre(tag: "oldies", key: "genre.oldies", symbol: "opticaldisc"),
        Genre(tag: "hiphop", key: "genre.hiphop", symbol: "headphones"),
        Genre(tag: "country", key: "genre.country", symbol: "music.note"),
        Genre(tag: "ambient", key: "genre.ambient", symbol: "leaf"),
        Genre(tag: "christian", key: "genre.christian", symbol: "sparkles"),
    ]

    /// Muziekgenres (zonder nieuws/talk/sport) voor Bladeren → Muziek
    static var music: [Genre] { all.filter { !["news", "talk", "sports"].contains($0.tag) } }

    static func forTag(_ tag: String) -> Genre {
        all.first { $0.tag == tag.lowercased() } ?? Genre(tag: tag.lowercased(), key: tag.capitalized, symbol: "music.note")
    }
}

// MARK: - Tolerant decoderen

extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "true" : "false" }
        return ""
    }

    func flexIntOptional(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? 1 : 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespaces).lowercased()
            if t == "true" { return 1 }
            if t == "false" { return 0 }
            return Int(t) ?? Double(t).map { Int($0) }
        }
        return nil
    }

    func flexInt(_ key: Key) -> Int { flexIntOptional(key) ?? 0 }

    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

/// Lijst die kapotte elementen overslaat in plaats van alles te laten mislukken
struct LossyArray<Element: Decodable>: Decodable {
    var items: [Element]
    /// Slaat één element over, wat het ook is (zodat de lijst altijd verder kan)
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
    init(items: [Element]) { self.items = items }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [Element] = []
        if let n = c.count { out.reserveCapacity(n) }
        while !c.isAtEnd {
            if let e = try? c.decode(Element.self) { out.append(e) } else { _ = try? c.decode(Skip.self) }
        }
        items = out
    }
}
