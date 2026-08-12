import SwiftUI
import UIKit

struct StickerImageView: View {
    let item: StackItem
    var size: CGFloat = 118
    /// Stack canvases only reveal transparent imagery. A raw source photo stays
    /// out of the collage until background removal produces a cutout.
    var requiresCutout = false
    var shadowOpacity: Double = 0.16
    var shadowRadius: CGFloat = 10
    var shadowYOffset: CGFloat = 8

    var body: some View {
        ZStack {
            stickerContent
                .frame(width: size, height: size)
                .padding(4)
                .background {
                    stickerHalo
                }
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowYOffset)
                .shadow(color: .white.opacity(0.85), radius: 2, x: 0, y: 0)

            if item.removalStatus.isWorking {
                RemovalShimmerView()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(width: size + 20, height: size + 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.removalStatus.isWorking ? "Removing background" : "Open product")
    }

    @ViewBuilder
    private var stickerContent: some View {
        if let imageURL = item.removedBackgroundImageURL {
            if imageURL.isFileURL, let image = UIImage(contentsOfFile: imageURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(Color.stacksInk)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallbackObject
                    @unknown default:
                        fallbackObject
                    }
                }
            }
        } else if let assetName = DemoProductImageCatalog.assetName(for: item.title) {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else if !requiresCutout, let imageURL = item.originalImageURL {
            if imageURL.isFileURL, let image = UIImage(contentsOfFile: imageURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(Color.stacksInk)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallbackObject
                    @unknown default:
                        fallbackObject
                    }
                }
            }
        } else if !requiresCutout, let imageURL = DemoProductImageCatalog.url(for: item.title) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .empty:
                    ProgressView()
                        .tint(Color.stacksInk)
                case .failure:
                    fallbackObject
                @unknown default:
                    fallbackObject
                }
            }
        } else {
            fallbackObject
        }
    }

    private var fallbackObject: some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(Color.stacksInk.opacity(0.72))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stickerHalo: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.white.opacity(item.removalStatus.isWorking ? 0.82 : 0.01))
            .blur(radius: item.removalStatus.isWorking ? 4 : 0)
    }
}

enum DemoProductImageCatalog {
    static func assetName(for title: String) -> String? {
        let lower = title.lowercased()

        // The mock Stack intentionally uses the bundled transparent cutouts so
        // it reads like a real collection even when the app is offline.
        let curatedMockAssets: [String: String] = [
            "graphic t-shirt": "OnboardingTShirt",
            "gallery tee": "OnboardingWallet",
            "denim shorts": "OnboardingShorts",
            "charcoal sweatshirt": "OnboardingWatch",
            "puffer jacket": "OnboardingWine",
            "black trench": "OnboardingKeys",
            "patterned jacket": "OnboardingTote",
            "slip dress": "OnboardingEarrings",
            "white robe": "OnboardingSneaker",
            "black robe": "OnboardingTShirt",
            "red sneaker": "OnboardingSneaker",
            "black tote bag": "OnboardingTote"
        ]

        if let asset = curatedMockAssets[lower] {
            return asset
        }

        if lower.contains("shirt") || lower.contains("tee") || lower.contains("sweatshirt") || lower.contains("jacket") || lower.contains("robe") {
            return "OnboardingTShirt"
        } else if lower.contains("shorts") {
            return "OnboardingShorts"
        } else if lower.contains("earring") {
            return "OnboardingEarrings"
        } else if lower.contains("watch") {
            return "OnboardingWatch"
        } else if lower.contains("wine") || lower.contains("bottle") {
            return "OnboardingWine"
        } else if lower.contains("wallet") {
            return "OnboardingWallet"
        } else if lower.contains("key") {
            return "OnboardingKeys"
        } else if lower.contains("shoe") || lower.contains("sneaker") {
            return "OnboardingSneaker"
        } else if lower.contains("tote") || lower.contains("bag") {
            return "OnboardingTote"
        }

        return nil
    }

    static func url(for title: String) -> URL? {
        let lower = title.lowercased()
        let rawURL: String

        if lower.contains("shirt") || lower.contains("t-shirt") || lower.contains("tshirt") {
            rawURL = "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("shorts") || lower.contains("gingham") {
            rawURL = "https://images.unsplash.com/photo-1591195853828-11db59a44f6b?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("earring") || lower.contains("pearl") {
            rawURL = "https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("wine") || lower.contains("bottle") {
            rawURL = "https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("wallet") {
            rawURL = "https://images.unsplash.com/photo-1627123424574-724758594e93?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("keys") || lower.contains("keychain") {
            rawURL = "https://images.unsplash.com/photo-1582139329536-e7284fece509?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("tote") || lower.contains("bag") {
            rawURL = "https://images.unsplash.com/photo-1590874103328-eac38a683ce7?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("shoe") || lower.contains("sneaker") || lower.contains("studio edition") {
            rawURL = "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("lamp") {
            rawURL = "https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("notebook") || lower.contains("book") {
            rawURL = "https://images.unsplash.com/photo-1517842645767-c639042777db?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("pen") {
            rawURL = "https://images.unsplash.com/photo-1583485088034-697b5bc54ccd?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("ball") {
            rawURL = "https://images.unsplash.com/photo-1519861531473-9200262188bf?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("banana") {
            rawURL = "https://images.unsplash.com/photo-1528825871115-3581a5387919?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("watch") {
            rawURL = "https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("camera") || lower.contains("photo") {
            rawURL = "https://images.unsplash.com/photo-1526170375885-4d8ecf77b99f?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("patch") || lower.contains("pin") || lower.contains("button") || lower.contains("badge") {
            rawURL = "https://images.unsplash.com/photo-1523293182086-7651a899d37f?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("card") || lower.contains("license") {
            rawURL = "https://images.unsplash.com/photo-1556745757-8d76bdb6984b?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("dice") {
            rawURL = "https://images.unsplash.com/photo-1605870445919-838d190e8e1b?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("head") || lower.contains("toy") {
            rawURL = "https://images.unsplash.com/photo-1581235720704-06d3acfcb36f?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("man") || lower.contains("fashion") {
            rawURL = "https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=520&q=80"
        } else if lower.contains("donkey") || lower.contains("charm") {
            rawURL = "https://images.unsplash.com/photo-1549366021-9f761d040a94?auto=format&fit=crop&w=520&q=80"
        } else {
            rawURL = "https://images.unsplash.com/photo-1544441893-675973e31985?auto=format&fit=crop&w=520&q=80"
        }

        return URL(string: rawURL)
    }
}

struct RemovalShimmerView: View {
    @State private var offset: CGFloat = -80

    var body: some View {
        LinearGradient(
            colors: [
                .white.opacity(0),
                .white.opacity(0.88),
                .white.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 70)
        .offset(y: offset)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                offset = 80
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}
