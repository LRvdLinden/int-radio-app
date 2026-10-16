import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// Kleine vertalingen tussen UIKit (iPhone, iPad, Apple TV) en AppKit (Mac).

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

enum DeviceKind {
    static var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    static var isTV: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

/// Lichte trilling bij tikken (alleen iPhone/iPad)
enum Haptics {
    @MainActor static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @MainActor static func soft() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    @MainActor static func rigid() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    @MainActor static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

extension PlatformImage {
    /// Maakt een platformafbeelding van ruwe data
    static func fromData(_ data: Data) -> PlatformImage? { PlatformImage(data: data) }
}

/// Afbeeldingen voor Now Playing / CarPlay (logo of hoes), met een eenvoudige geheugencache.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, PlatformImage>()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    func cached(_ url: URL) -> PlatformImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> PlatformImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        var req = URLRequest(url: url)
        req.setValue(Brand.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: req), let img = PlatformImage(data: data) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}
