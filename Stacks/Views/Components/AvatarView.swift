import SwiftUI

struct AvatarView: View {
    let profile: UserProfile
    var size: CGFloat = 44
    var localImageData: Data? = nil

    var body: some View {
        Group {
            if let localImageData, let image = UIImage(data: localImageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let avatarURL = profile.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: max(1, size * 0.04))
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityLabel(profile.displayName)
    }

    private var initials: some View {
        Text(profile.initials)
            .font(.stacksText(size: size * 0.34, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.stacksInk)
    }
}
