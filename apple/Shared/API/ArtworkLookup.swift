import Foundation

/// Albumhoes bij "nu speelt": ICY-titel "Artiest - Titel" → iTunes Search API (zonder sleutel),
/// `artworkUrl100` → 600x600bb. Gecachet per titel (ook "niets gevonden").
final class ArtworkLookup: @unchecked Sendable {
    static let shared = ArtworkLookup()

    private let lock = NSLock()
    private var cache: [String: URL?] = [:]

    /// Splits een ICY-titel in artiest en titel. Lege titels, reclame en zendernamen leveren nil op.
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

    func artwork(for streamTitle: String) async -> URL? {
        guard let parts = Self.split(streamTitle) else { return nil }
        let key = (parts.artist + " " + parts.title).lowercased()
        if let hit = lock.withLock({ cache[key] }) { return hit }

        var comps = URLComponents(string: "https://itunes.apple.com/search")
        comps?.queryItems = [
            URLQueryItem(name: "term", value: parts.artist + " " + parts.title),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")

        struct Response: Decodable {
            struct Item: Decodable { let artworkUrl100: String? }
            let results: [Item]
        }
        var found: URL?
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let r = try? JSONDecoder().decode(Response.self, from: data),
           let art = r.results.first?.artworkUrl100 {
            found = URL(string: art.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
        }
        lock.withLock {
            if cache.count > 300 { cache.removeAll() }
            cache[key] = .some(found)
        }
        return found
    }
}
