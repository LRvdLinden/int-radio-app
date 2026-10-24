import Foundation

/// Zender op de Apple Watch. Zelfde JSON-indeling als `Station` in de iPhone-app (sleutels van Radio Browser),
/// zodat favorieten en recent uit iCloud en via WatchConnectivity zonder omzetten gelezen en teruggestuurd kunnen
/// worden. Bewust los van Shared/Models (die hangt aan de logo- en UI-code van de grote app).
struct WStation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var url: String
    var urlResolved: String = ""
    var homepage: String = ""
    var favicon: String = ""
    var tags: String = ""
    var country: String = ""
    var countryCode: String = ""
    var state: String = ""
    var language: String = ""
    var codec: String = ""
    var bitrate: Int = 0
    var hls: Bool = false
    var votes: Int = 0
    var clickCount: Int = 0
    var clickTrend: Int = 0
    var lastCheckOK: Bool = true
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String {
            if let s = try? c.decode(String.self, forKey: k) { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let i = try? c.decode(Int.self, forKey: k) { return String(i) }
            return ""
        }
        func int(_ k: CodingKeys) -> Int {
            if let i = try? c.decode(Int.self, forKey: k) { return i }
            if let b = try? c.decode(Bool.self, forKey: k) { return b ? 1 : 0 }
            if let s = try? c.decode(String.self, forKey: k), let i = Int(s) { return i }
            if let d = try? c.decode(Double.self, forKey: k) { return Int(d) }
            return 0
        }
        func dbl(_ k: CodingKeys) -> Double? {
            if let d = try? c.decode(Double.self, forKey: k) { return d }
            if let s = try? c.decode(String.self, forKey: k) { return Double(s) }
            return nil
        }
        id = str(.id)
        name = str(.name)
        url = str(.url)
        urlResolved = str(.urlResolved)
        homepage = str(.homepage)
        favicon = str(.favicon)
        tags = str(.tags)
        country = str(.country)
        countryCode = str(.countryCode).uppercased()
        state = str(.state)
        language = str(.language)
        codec = str(.codec)
        bitrate = int(.bitrate)
        hls = int(.hls) != 0
        votes = int(.votes)
        clickCount = int(.clickCount)
        clickTrend = int(.clickTrend)
        lastCheckOK = (c.contains(.lastCheckOK) ? int(.lastCheckOK) : 1) != 0
        geoLat = dbl(.geoLat)
        geoLong = dbl(.geoLong)
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

    var displayName: String { name.isEmpty ? "Radio" : name }
    var streamURL: URL? { URL(string: urlResolved.isEmpty ? url : urlResolved) ?? URL(string: url) }
    var fallbackURL: URL? {
        guard !urlResolved.isEmpty, urlResolved != url else { return nil }
        return URL(string: url)
    }
    var genreLine: String {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .prefix(2).map { $0.capitalized }.joined(separator: " · ")
    }
    /// Tweede regel in lijsten: genres, anders het land
    var subtitle: String { genreLine.isEmpty ? country : genreLine }
    var monogram: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "-" })
        let m = words.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        return m.isEmpty ? "R" : m
    }

    static func == (a: WStation, b: WStation) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum WJSON {
    static func stations(_ data: Data?) -> [WStation] {
        guard let data else { return [] }
        if let list = try? JSONDecoder().decode([WStation].self, from: data) { return list }
        // los per item, zodat één kapotte zender de rest niet tegenhoudt
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { item in
            guard let d = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(WStation.self, from: d)
        }
    }

    static func station(_ data: Data?) -> WStation? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WStation.self, from: data)
    }

    static func data(_ value: some Encodable) -> Data? { try? JSONEncoder().encode(value) }
}

/// "Artiest - Titel" uit de stream → (artiest, titel); zelfde regel als ArtworkLookup.split in de iPhone-app
enum WTrack {
    static func split(_ raw: String) -> (artist: String, title: String)? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 3 else { return nil }
        let parts = t.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        let artist = parts[0].trimmingCharacters(in: .whitespaces)
        let title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        return (artist, title)
    }

    /// "Titel - Artiest" (zoals Nu speelt in de iPhone-app), of de ruwe titel
    static func line(_ raw: String) -> String {
        if let p = split(raw) { return p.title + " - " + p.artist }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
