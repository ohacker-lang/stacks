import SwiftUI

enum AvatarStore {
    static let didChangeNotification = Notification.Name("stacks.profile.avatar.didChange")

    static func data(for profileID: UUID) -> Data? {
        UserDefaults.standard.data(forKey: storageKey(for: profileID))
    }

    static func save(_ data: Data, for profileID: UUID) {
        UserDefaults.standard.set(data, forKey: storageKey(for: profileID))
        NotificationCenter.default.post(name: didChangeNotification, object: profileID)
    }

    private static func storageKey(for profileID: UUID) -> String {
        "stacks.profile.avatar.\(profileID.uuidString)"
    }
}

struct AvatarView: View {
    let profile: UserProfile
    var size: CGFloat = 44
    var localImageData: Data? = nil
    @State private var storedImageData: Data?

    var body: some View {
        Group {
            if let imageData = storedImageData ?? localImageData ?? AvatarStore.data(for: profile.id),
               let image = UIImage(data: imageData) {
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
        .task(id: profile.id) {
            storedImageData = localImageData ?? AvatarStore.data(for: profile.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: AvatarStore.didChangeNotification)) { notification in
            guard let changedProfileID = notification.object as? UUID,
                  changedProfileID == profile.id else { return }
            storedImageData = AvatarStore.data(for: profile.id)
        }
    }

    private var initials: some View {
        Text(profile.initials)
            .font(.stacksText(size: size * 0.34, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.stacksInk)
    }
}
