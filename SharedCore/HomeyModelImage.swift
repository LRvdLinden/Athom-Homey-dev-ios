import SwiftUI
import UIKit

/// Memory cache for remote raster images (Homey product images).
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache(memoryCapacity: 10 << 20, diskCapacity: 50 << 20)
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()

    func cached(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: url as NSURL)
    }

    func image(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let task = tasks[url] { return await task.value }
        let session = self.session
        let task = Task { () -> UIImage? in
            guard let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
            return UIImage(data: data)
        }
        tasks[url] = task
        let img = await task.value
        tasks[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// Product image of a Homey (black Homey Pro, Homey Cloud house, Self-Hosted
/// Server box, …): the same images my.homey.app shows, light or dark.
struct HomeyModelImage: View {
    let homey: HomeyRef
    var size: CGFloat = 52

    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage?

    private var url: URL? {
        scheme == .dark ? (homey.imageDark ?? homey.imageLight) : (homey.imageLight ?? homey.imageDark)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: homey.fallbackSymbol)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = RemoteImageCache.shared.cached(url) { image = hit; return }
            let img = await RemoteImageCache.shared.image(url)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}
