import Foundation

/// Radio Browser op de Apple Watch: populair per land en zoeken op naam. Altijd met de eigen User-Agent
/// (`Brand.userAgent`, verplicht bij Radio Browser). Servers uit all.api.radio-browser.info, met terugval.
actor WatchRadioBrowser {
    static let shared = WatchRadioBrowser()

    private var servers: [String] = []
    private let fallback = ["de1.api.radio-browser.info", "de2.api.radio-browser.info", "fi1.api.radio-browser.info"]

    private func serverList() async -> [String] {
        if !servers.isEmpty { return servers }
        var list: [String] = []
        if let url = URL(string: "https://all.api.radio-browser.info/json/servers") {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                list = Array(Set(raw.compactMap { $0["name"] as? String })).sorted()
            }
        }
        servers = (list.isEmpty ? fallback : list.shuffled())
        return servers
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> [WStation] {
        var lastError: Error = URLError(.cannotFindHost)
        for host in await serverList().prefix(3) {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = host
            comps.path = path
            comps.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = comps.url else { continue }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                return WJSON.stations(data).filter { $0.lastCheckOK && $0.streamURL != nil }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func popular(country: String, limit: Int = 40) async throws -> [WStation] {
        try await get("/json/stations/search", ["countrycode": country, "order": "clickcount", "reverse": "true",
                                                "hidebroken": "true", "limit": String(limit)])
    }

    func search(name: String, country: String?) async throws -> [WStation] {
        var q = ["name": name, "order": "clickcount", "reverse": "true", "hidebroken": "true", "limit": "40"]
        if let country, !country.isEmpty { q["countrycode"] = country }
        let local = try await get("/json/stations/search", q)
        if !local.isEmpty || country == nil { return local }
        return try await search(name: name, country: nil)
    }

    func top(limit: Int = 40) async throws -> [WStation] {
        try await get("/json/stations/topclick/\(limit)", ["hidebroken": "true"])
    }

    func click(_ id: String) async {
        _ = try? await get("/json/url/\(id)", [:])
    }
}

/// Zenderlogo's: eerst het app-icoon uit de vaste tabel van tunr.online (per land, zelfde bron als de andere
/// apps, SPEC §1), dan het favicon van Radio Browser (alleen https). Tabellen 6 uur in het geheugen.
actor WatchIcons {
    static let shared = WatchIcons()

    private var tables: [String: (date: Date, map: [String: String])] = [:]
    private var loading: [String: Task<[String: String], Never>] = [:]

    func url(for s: WStation) async -> URL? {
        let cc = s.countryCode.isEmpty ? "_world" : s.countryCode
        let map = await table(cc)
        if let u = map[s.id], let url = URL(string: u) { return url }
        let fav = s.favicon
        if fav.lowercased().hasPrefix("https://") { return URL(string: fav) }
        if fav.lowercased().hasPrefix("http://") { return URL(string: "https://" + fav.dropFirst(7)) }
        return nil
    }

    private func table(_ cc: String) async -> [String: String] {
        if let t = tables[cc], Date().timeIntervalSince(t.date) < 6 * 3600 { return t.map }
        if let task = loading[cc] { return await task.value }
        let task = Task<[String: String], Never> {
            guard let url = URL(string: "https://tunr.online/assets/data/icons/\(cc).json") else { return [:] }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let u = obj["u"] as? [String: String] else { return [:] }
            return u
        }
        loading[cc] = task
        let map = await task.value
        loading[cc] = nil
        tables[cc] = (Date(), map)
        return map
    }
}
