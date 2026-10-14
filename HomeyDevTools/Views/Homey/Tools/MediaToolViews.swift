import SwiftUI
import AVKit

// MARK: - Images

struct ImagesToolView: View {
    let client: HomeyClient
    @State private var images: [JSON] = []
    @State private var loading = true
    @State private var error: String?
    @State private var reloadToken = UUID()

    var body: some View {
        ScrollView {
            if let error { ErrorBanner(message: error) { Task { await load() } }.padding() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                    VStack(alignment: .leading, spacing: 6) {
                        HomeyImage(client: client, path: img.firstString("url", "imageUrl"), reloadToken: reloadToken)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(titleOrID(img))
                            .font(.caption.weight(.medium)).lineLimit(1)
                        Text(img.firstString("ownerUri", "ownerName")).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    .homeyCard(padding: 8)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if loading && images.isEmpty { ProgressView() }
            else if images.isEmpty && error == nil { ContentUnavailableView("Geen afbeeldingen", systemImage: "photo") }
        }
        .navigationTitle("Images")
        .toolbar { Button { reloadToken = UUID() } label: { Image(systemName: "arrow.clockwise") } }
        .refreshable { await load(); reloadToken = UUID() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { images = try await client.request("/api/manager/images/image").items; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// Image served by Homey (needs the session token, so AsyncImage can't be used).
struct HomeyImage: View {
    let client: HomeyClient
    let path: String
    var reloadToken = UUID()
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task(id: "\(path)\(reloadToken)") {
            guard !path.isEmpty else { failed = true; return }
            let sep = path.contains("?") ? "&" : "?"
            if let data = try? await client.data(at: "\(path)\(sep)_r=\(Int(Date().timeIntervalSince1970))"), let img = UIImage(data: data) {
                image = img; failed = false
            } else { failed = true }
        }
    }
}

// MARK: - Videos

struct VideosToolView: View {
    let client: HomeyClient
    @State private var videos: [JSON] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } }.listRowBackground(Color.clear) }
            ForEach(Array(videos.enumerated()), id: \.offset) { _, v in
                NavigationLink { VideoPlayerToolView(client: client, video: v) } label: {
                    HStack {
                        Image(systemName: "video.fill").foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleOrID(v))
                            Text(detailLine(v.firstString("type"), v.firstString("ownerUri")))
                                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay {
            if loading && videos.isEmpty { ProgressView() }
            else if videos.isEmpty && error == nil { ContentUnavailableView("Geen video's", systemImage: "video.slash") }
        }
        .navigationTitle("Videos")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { videos = try await client.request("/api/manager/videos/video").items; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct VideoPlayerToolView: View {
    let client: HomeyClient
    let video: JSON
    @State private var player: AVPlayer?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onAppear { player.play() }
            } else if let error {
                ContentUnavailableView {
                    Label("Kan video niet afspelen", systemImage: "video.slash")
                } description: { Text(error) }
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(titleOrID(video))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if video.firstString("type").lowercased().contains("webrtc") {
                error = L("WebRTC-camera's worden alleen in de Homey-app ondersteund."); return
            }
            do {
                let r = try await client.request("/api/manager/videos/video/\(video.firstString("id"))/video-url")
                let s = r.string ?? r.firstString("url")
                guard let url = URL(string: s, relativeTo: client.baseURL) else { throw APIError(status: 0, message: L("Geen video-URL"), url: "") }
                player = AVPlayer(url: url.absoluteURL)
            } catch { self.error = error.localizedDescription }
        }
    }
}
