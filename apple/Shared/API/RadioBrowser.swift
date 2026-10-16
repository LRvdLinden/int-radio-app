import Foundation

/// Fouten van de zenderdatabase
enum RadioBrowserError: Error {
    case noServer
    case badResponse(Int)
}

/// Client voor Radio Browser (community-database, geen sleutel). Kiest een willekeurige server uit
/// `all.api.radio-browser.info`, bewaart die voor de sessie en gaat bij een fout naar de volgende.
/// Antwoorden worden in het geheugen en op schijf bewaard (landen 7 dagen, zenderlijsten 30 minuten).
final class RadioBrowser: @unchecked Sendable {
    static let shared = RadioBrowser()

    static let countriesTTL: TimeInterval = 7 * 24 * 3600
    static let listTTL: TimeInterval = 30 * 60

    private let lock = NSLock()
    private var servers: [URL] = []
    private var serverIndex = 0
    private var discovery: Task<[URL], Never>?
    private var memory: [String: (date: Date, data: Data)] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    private let fallbackServers = ["de1", "de2", "fi1"].compactMap { URL(string: "https://\($0).api.radio-browser.info") }

    private let cacheDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("RadioBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Servers

    private func serverList() async -> [URL] {
        let existing: [URL]? = lock.withLock { servers.isEmpty ? nil : servers }
        if let existing { return existing }
        let task: Task<[URL], Never> = lock.withLock {
            if let d = discovery { return d }
            let fallback = fallbackServers
            let session = self.session
            let t = Task<[URL], Never> {
                var list: [URL] = []
                if let url = URL(string: "https://all.api.radio-browser.info/json/servers") {
                    var req = URLRequest(url: url, timeoutInterval: 6)
                    req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
                    struct Server: Decodable { let name: String }
                    if let (data, _) = try? await session.data(for: req),
                       let decoded = try? JSONDecoder().decode([Server].self, from: data) {
                        var names = Set<String>()
                        for s in decoded where !names.contains(s.name) {
                            names.insert(s.name)
                            if let u = URL(string: "https://\(s.name)") { list.append(u) }
                        }
                    }
                }
                list.shuffle()
                for f in fallback.shuffled() where !list.contains(f) { list.append(f) }
                return list
            }
            discovery = t
            return t
        }
        let list = await task.value
        lock.withLock {
            if servers.isEmpty { servers = list; serverIndex = 0 }
        }
        return list
    }

    private func currentServer(_ list: [URL]) -> URL {
        let i = lock.withLock { serverIndex }
        return list[i % list.count]
    }

    private func markFailed(_ list: [URL]) {
        lock.withLock { serverIndex = (serverIndex + 1) % max(1, list.count) }
    }

    // MARK: - Verzoeken

    /// GET met cache. `ttl == 0` = nooit uit de cache.
    private func get(_ path: String, _ query: [URLQueryItem], ttl: TimeInterval) async throws -> Data {
        let sortedQuery = query.sorted { $0.name < $1.name }
        let key = path + "?" + sortedQuery.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")

        if ttl > 0, let hit = cached(key, ttl: ttl) { return hit }

        let list = await serverList()
        guard !list.isEmpty else { throw RadioBrowserError.noServer }
        var lastError: Error = RadioBrowserError.noServer
        for _ in 0..<min(3, list.count) {
            // na een fout schuift markFailed de server op; dus steeds de huidige nemen
            let base = currentServer(list)
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
            comps?.path = path
            comps?.queryItems = sortedQuery.isEmpty ? nil : sortedQuery
            guard let url = comps?.url else { continue }
            var req = URLRequest(url: url)
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard (200..<300).contains(code) else { throw RadioBrowserError.badResponse(code) }
                if ttl > 0 { store(key, data) }
                return data
            } catch {
                if (error as? URLError)?.code == .cancelled || Task.isCancelled { throw error }
                lastError = error
                markFailed(list)
            }
        }
        // offline: dan maar een verlopen kopie
        if ttl > 0, let stale = cached(key, ttl: .infinity) { return stale }
        throw lastError
    }

    private func fileURL(for key: String) -> URL? {
        // stabiele FNV-1a-hash als bestandsnaam
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
            if memory.count > 200 { memory.removeAll(keepingCapacity: true) }
        }
        if let file = fileURL(for: key) { try? data.write(to: file, options: .atomic) }
    }

    private func decodeStations(_ data: Data) -> [Station] {
        ((try? JSONDecoder().decode(LossyArray<Station>.self, from: data))?.items ?? []).deduplicated()
    }

    /// `/json/stations/search` met standaard `hidebroken=true`
    func search(_ params: [String: String], ttl: TimeInterval = RadioBrowser.listTTL) async throws -> [Station] {
        var p = params
        if p["hidebroken"] == nil { p["hidebroken"] = "true" }
        let data = try await get("/json/stations/search", p.map { URLQueryItem(name: $0.key, value: $0.value) }, ttl: ttl)
        return decodeStations(data)
    }

    private func ranked(_ extra: [String: String], order: String = "clickcount", limit: Int = 60) -> [String: String] {
        var p = extra
        p["order"] = order
        p["reverse"] = "true"
        p["limit"] = String(limit)
        p["offset"] = p["offset"] ?? "0"
        return p
    }

    // MARK: - Endpoints

    func countries() async throws -> [Country] {
        let data = try await get("/json/countries",
                                 [URLQueryItem(name: "hidebroken", value: "true"), URLQueryItem(name: "order", value: "name")],
                                 ttl: Self.countriesTTL)
        let list = (try? JSONDecoder().decode(LossyArray<Country>.self, from: data))?.items ?? []
        var seen = Set<String>()
        var out: [Country] = []
        for c in list where c.stationCount >= 1 && c.code.count == 2 {
            if let i = out.firstIndex(where: { $0.code == c.code }) {
                // soms staat een land er twee keer in (andere schrijfwijze): tellen samen
                out[i].stationCount += c.stationCount
                continue
            }
            if seen.insert(c.code).inserted { out.append(c) }
        }
        return out
    }

    func popular(country: String, limit: Int = 60) async throws -> [Station] {
        try await search(ranked(["countrycode": country], limit: limit))
    }

    func trending(country: String, limit: Int = 60) async throws -> [Station] {
        try await search(ranked(["countrycode": country], order: "clicktrend", limit: limit))
    }

    /// Per genre; `country == nil` = wereldwijd
    func byTag(_ tag: String, country: String?, limit: Int = 60) async throws -> [Station] {
        var p = ["tag": tag, "tagExact": "true"]
        if let country { p["countrycode"] = country }
        return try await search(ranked(p, limit: limit))
    }

    /// Zoeken op naam; `country == nil` = wereldwijd
    func search(name: String, country: String?) async throws -> [Station] {
        var p = ["name": name]
        if let country { p["countrycode"] = country }
        return try await search(ranked(p, limit: 60), ttl: 5 * 60)
    }

    /// Favorieten verversen
    func byUUIDs(_ ids: [String]) async throws -> [Station] {
        guard !ids.isEmpty else { return [] }
        var out: [Station] = []
        // in blokken, zodat de URL niet te lang wordt
        var start = 0
        while start < ids.count {
            let chunk = ids[start..<min(ids.count, start + 50)]
            let data = try await get("/json/stations/byuuid", [URLQueryItem(name: "uuids", value: chunk.joined(separator: ","))], ttl: 0)
            out += (try? JSONDecoder().decode(LossyArray<Station>.self, from: data))?.items ?? []
            start += 50
        }
        return out
    }

    /// Klik tellen bij afspelen (fire-and-forget)
    func click(_ id: String) {
        Task.detached(priority: .background) { [weak self] in
            _ = try? await self?.get("/json/url/\(id)", [], ttl: 0)
        }
    }

    /// Regio's (provincies/staten) van een land; `countryName` = Engelse naam uit /json/countries
    func states(countryName: String) async throws -> [RegionState] {
        // URLComponents codeert het pad zelf (spaties e.d.)
        let data = try await get("/json/states/\(countryName)/",
                                 [URLQueryItem(name: "hidebroken", value: "true"),
                                  URLQueryItem(name: "order", value: "stationcount"),
                                  URLQueryItem(name: "reverse", value: "true")],
                                 ttl: Self.countriesTTL)
        let list = (try? JSONDecoder().decode(LossyArray<RegionState>.self, from: data))?.items ?? []
        var seen = Set<String>()
        return list.filter { !$0.name.isEmpty && $0.stationCount > 0 && seen.insert($0.name.lowercased()).inserted }
    }

    func stations(country: String, state: String) async throws -> [Station] {
        try await search(ranked(["countrycode": country, "state": state, "stateExact": "true"], limit: 100))
    }

    func languages() async throws -> [LanguageInfo] {
        let data = try await get("/json/languages",
                                 [URLQueryItem(name: "hidebroken", value: "true"),
                                  URLQueryItem(name: "order", value: "stationcount"),
                                  URLQueryItem(name: "reverse", value: "true"),
                                  URLQueryItem(name: "limit", value: "60")],
                                 ttl: Self.countriesTTL)
        return ((try? JSONDecoder().decode(LossyArray<LanguageInfo>.self, from: data))?.items ?? [])
            .filter { !$0.name.isEmpty && $0.stationCount > 0 }
    }

    /// Op taal (wereldwijd)
    func stations(language: String) async throws -> [Station] {
        try await search(ranked(["language": language, "languageExact": "true"], limit: 100))
    }

    func top100() async throws -> [Station] {
        try await search(ranked([:], limit: 100), ttl: Self.listTTL)
    }

    /// Zenders met coördinaten voor de kaart: land (500) of wereld (top 1500)
    func geoStations(country: String?) async throws -> [Station] {
        var p = ["has_geo_info": "true"]
        if let country { p["countrycode"] = country }
        return try await search(ranked(p, limit: country == nil ? 1500 : 500)).filter { $0.coordinate != nil }
    }

    /// Een willekeurige zender wereldwijd (met coördinaten) uit de top 5000
    func randomStation() async throws -> Station? {
        for _ in 0..<3 {
            let offset = Int.random(in: 0..<5000)
            let list = try await search(ranked(["has_geo_info": "true", "offset": String(offset)], limit: 1), ttl: 0)
            if let s = list.first(where: { $0.coordinate != nil }) { return s }
        }
        return nil
    }

    /// De twee genres (uit de vaste lijst) met de meeste zenders in de top 500 van het land
    func topGenres(country: String, count: Int = 2) async throws -> [String] {
        let list = try await search(ranked(["countrycode": country], limit: 500), ttl: Self.countriesTTL / 7)
        let known = Set(Genre.all.map(\.tag)).subtracting(["news", "talk", "sports"])
        var counts: [String: Int] = [:]
        for s in list {
            for t in s.tagList where known.contains(t) { counts[t, default: 0] += 1 }
        }
        let sorted = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        let top = Array(sorted.prefix(count))
        return top.count == count ? top : Array((top + ["pop", "rock"].filter { !top.contains($0) }).prefix(count))
    }
}
