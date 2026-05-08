import SwiftUI

final class ImageMemoryCache {
    static let shared = NSCache<NSURL, UIImage>()
}

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder
    @State private var image: UIImage?
    @State private var didFail = false

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
                    .overlay(alignment: .bottomLeading) {
                        if didFail {
                            Text("Изображение недоступно")
                                .font(BeautyFont.caption2)
                                .foregroundStyle(BeautyColor.taupe)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(BeautyColor.milk.opacity(0.92), in: Capsule())
                                .padding(8)
                        }
                    }
                    .task(id: url) { await load() }
            }
        }
        .onChange(of: url) { _, _ in
            image = nil
            didFail = false
        }
    }

    private func load() async {
        didFail = false
        guard let url else { return }
        let key = url as NSURL
        if let cached = ImageMemoryCache.shared.object(forKey: key) {
            image = cached
            return
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 18
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                didFail = true
                return
            }
            guard let uiImage = await decodeImage(data: data) else {
                didFail = true
                return
            }
            ImageMemoryCache.shared.setObject(uiImage, forKey: key)
            image = uiImage
        } catch {
            didFail = true
        }
    }

    private func decodeImage(data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
        }.value
    }
}
