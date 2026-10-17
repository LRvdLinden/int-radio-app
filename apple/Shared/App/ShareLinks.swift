import Foundation

/// Deelknoppen in de app delen altijd een vaste link naar de webspeler op tunr.online (zelfde routes als
/// website/assets/js/ui.js → T.ui.share), zodat iedereen het kan openen, ook zonder de app.
enum ShareLinks {
    private static let allowed: CharacterSet = {
        var c = CharacterSet.alphanumerics
        c.insert(charactersIn: "-._~")
        return c
    }()
    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
    private static func web(_ route: String) -> URL {
        URL(string: Brand.website.absoluteString + "/web/#/" + route) ?? Brand.website
    }

    /// https://tunr.online/web/#/station/<stationuuid>
    static func station(_ id: String) -> URL { web("station/" + enc(id)) }
    /// https://tunr.online/web/#/podcast/<iTunes collectionId>
    static func podcast(_ id: String) -> URL { web("podcast/" + enc(id)) }
    /// https://tunr.online/web/#/episode/<collectionId>/<trackId>
    static func episode(podcastID: String, episodeID: String) -> URL { web("episode/" + enc(podcastID) + "/" + enc(episodeID)) }
}
