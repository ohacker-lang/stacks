import PhotosUI
import SwiftUI
import UIKit

private enum AccountInfoDestination: Identifiable {
    case support
    case privacy
    case terms
    case affiliateDisclosure
    case privacyChoices

    var id: Self { self }

    var title: String {
        switch self {
        case .support: "Help & support"
        case .privacy: "Privacy policy"
        case .terms: "Terms of service"
        case .affiliateDisclosure: "Affiliate disclosure"
        case .privacyChoices: "Privacy choices"
        }
    }

    var symbol: String {
        switch self {
        case .support: "questionmark.circle"
        case .privacy: "hand.raised"
        case .terms: "doc.text"
        case .affiliateDisclosure: "dollarsign.arrow.circlepath"
        case .privacyChoices: "lock"
        }
    }

    var detail: String {
        switch self {
        case .support:
            "Get help with saving products, sharing a Stack, Collabs, or your account."
        case .privacy:
            "Stacks explains what information we collect, why we use it, how long we keep it, and how to request deletion."
        case .terms:
            "These terms cover use of Stacks, shared collections, product links, and community content."
        case .affiliateDisclosure:
            "Learn when Stacks may earn a commission, how qualifying links are labeled, and what that means for you."
        case .privacyChoices:
            "Manage how your information is used and request access, correction, or deletion of your account data."
        }
    }
}

private struct ProfileURLShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(StacksPro.self) private var pro
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var isEditingProfile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var showsDeleteConfirmation = false
    @State private var showsDeletionNotice = false
    @State private var accountDestination: AccountInfoDestination?
    @State private var isShowingSettings = false
    @State private var editableProfile: UserProfile
    @State private var isFollowing = false
    @State private var heroItems: [StackItem] = []
    @State private var safetyMessage: String?
    @State private var profileShareURL: URL?
    @State private var isShowingProfileShare = false

    let profile: UserProfile
    let onOpenStack: (Stack) -> Void
    let onNavigateBack: () -> Void

    init(
        profile: UserProfile,
        onOpenStack: @escaping (Stack) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.profile = profile
        self.onOpenStack = onOpenStack
        self.onNavigateBack = onNavigateBack
        _editableProfile = State(initialValue: profile)
    }

    private var isCurrentProfile: Bool {
        session.currentUser?.id == profile.id
    }

    private var presentedProfile: UserProfile {
        isCurrentProfile ? editableProfile : profile
    }

    var body: some View {
        ProfileRedesignScreen(
            profile: presentedProfile,
            avatarData: avatarData,
            stacks: viewModel.stacks,
            heroItems: heroItems,
            followerCount: viewModel.followerCount,
            productCount: viewModel.productCount,
            isCurrentProfile: isCurrentProfile,
            isFollowing: isFollowing,
            onBack: {
                services.haptics.impact(.light)
                onNavigateBack()
            },
            onEdit: { isEditingProfile = true },
            onOpenSettings: { isShowingSettings = true },
            onShareProfile: {
                // Every account has a public page at stacks.spot/username.
                guard let url = URL(string: "https://stacks.spot/\(presentedProfile.username.lowercased())") else { return }
                profileShareURL = url
                isShowingProfileShare = true
                Analytics.capture("profile_shared", ["own": true])
            },
            onOpenStack: onOpenStack,
            onToggleFollow: toggleFollow,
            onReport: { reason in
                Task {
                    do {
                        try await services.safety.reportProfile(id: profile.id, reason: reason)
                        safetyMessage = "Thanks. This profile has been reported for review."
                    } catch {
                        safetyMessage = error.localizedDescription
                    }
                }
            },
            onBlock: {
                Task {
                    do {
                        try await services.safety.blockUser(id: profile.id)
                        onNavigateBack()
                    } catch {
                        safetyMessage = error.localizedDescription
                    }
                }
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: profile.id) {
            avatarData = AvatarStore.data(for: profile.id)
            await viewModel.load(services: services, profile: profile, currentUser: session.currentUser)
            heroItems = Array(viewModel.stacks.flatMap(\.items).shuffled().prefix(6))
            isFollowing = profile.isFollowing
        }
        .task(id: photoItem) {
            guard let photoItem,
                  let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            avatarData = data
            AvatarStore.save(data, for: profile.id)
            services.haptics.notification(.success)
        }
        .sheet(isPresented: $isEditingProfile) {
            ProfileEditSheet(profile: presentedProfile, avatarData: avatarData) { displayName, username, bio, newAvatarData in
                if let newAvatarData {
                    avatarData = newAvatarData
                    AvatarStore.save(newAvatarData, for: profile.id)
                }
                guard let updated = session.updateCurrentProfile(
                    displayName: displayName,
                    username: username,
                    bio: bio
                ) else { return }
                editableProfile = updated
                Task {
                    if let saved = try? await services.profiles.updateProfile(updated, avatarData: newAvatarData) {
                        editableProfile = saved
                        session.replaceCurrentProfile(with: saved)
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingSettings) {
            ProfileSettingsSheet(
                isPro: pro.isPro,
                onPro: {
                    isShowingSettings = false
                    if pro.isPro {
                        UIApplication.shared.open(URL(string: "https://apps.apple.com/account/subscriptions")!)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pro.present(.settings) }
                    }
                },
                onEditProfile: {
                    isShowingSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isEditingProfile = true
                    }
                },
                onOpenInfo: { destination in
                    isShowingSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        accountDestination = destination
                    }
                },
                onSignOut: {
                    isShowingSettings = false
                    Task { await session.signOut() }
                },
                onDeleteAccount: {
                    isShowingSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showsDeleteConfirmation = true
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingProfileShare) {
            if let profileShareURL {
                ProfileURLShareSheet(url: profileShareURL)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Delete account?", isPresented: $showsDeleteConfirmation) {
            Button("Delete Account", role: .destructive) {
                Task {
                    showsDeletionNotice = await session.requestAccountDeletion()
                    if !showsDeletionNotice {
                        safetyMessage = session.lastError ?? "Account deletion failed. Please try again."
                    }
                }
            }
            Button("Manage Apple Subscription") {
                UIApplication.shared.open(URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, Stacks, saved products, and profile data. Deleting your Stacks account does not cancel an active Apple subscription, so manage it first if needed. This cannot be undone.")
        }
        .alert("Account deleted", isPresented: $showsDeletionNotice) {
            Button("Done") {}
        } message: {
            Text("Your Stacks account has been deleted.")
        }
        .sheet(item: $accountDestination) { destination in
            AccountInfoSheet(destination: destination) {
                if destination == .privacyChoices {
                    showsDeleteConfirmation = true
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Profile", isPresented: Binding(
            get: { safetyMessage != nil },
            set: { if !$0 { safetyMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(safetyMessage ?? "")
        }
    }

    private func toggleFollow() {
        guard !isCurrentProfile, let user = session.currentUser else { return }
        let previous = isFollowing
        isFollowing.toggle()
        let event = isFollowing ? "creator_followed" : "creator_unfollowed"
        viewModel.followerCount = max(0, viewModel.followerCount + (isFollowing ? 1 : -1))
        services.haptics.impact(.light)

        Task {
            do {
                _ = try await services.stacks.toggleFollow(authorID: profile.id, userID: user.id)
                Analytics.capture(event)
            } catch {
                isFollowing = previous
                viewModel.followerCount = max(0, viewModel.followerCount + (previous ? 1 : -1))
            }
        }
    }

    private var accountHeader: some View {
        HStack {
            Button {
                services.haptics.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.68), in: Circle())
                    .overlay {
                        Circle().stroke(Color.black.opacity(0.07), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
        }
    }

    private var identity: some View {
        let avatar = AvatarView(profile: presentedProfile, size: 92, localImageData: avatarData)

        return HStack(alignment: .center, spacing: 18) {
            if isCurrentProfile {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    avatar
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 30, height: 30)
                                .background(Color.stacksInk, in: Circle())
                                .overlay { Circle().stroke(Color.white, lineWidth: 2) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change profile photo")
            } else {
                avatar
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(presentedProfile.displayName)
                    .font(.system(size: 30, weight: .semibold, design: .default))
                    .tracking(-0.7)
                    .foregroundStyle(Color.stacksInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("@\(presentedProfile.username)")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .tracking(-0.25)
                    .foregroundStyle(Color.stacksMutedInk)
            }

            Spacer(minLength: 0)
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            AccountStat(value: viewModel.stackCount, title: "Stacks")
            AccountStatDivider()
            AccountStat(value: viewModel.followerCount, title: "followers")
            AccountStatDivider()
            AccountStat(value: viewModel.bookmarkCount, title: "bookmarks")
        }
        .padding(.vertical, 21)
        .padding(.horizontal, 18)
        .stacksGlass(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Achievements")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .tracking(-0.35)
                .foregroundStyle(Color.stacksInk)

            HStack(spacing: 10) {
                AchievementBadge(
                    symbol: "square.stack.3d.up.fill",
                    title: "First Stack",
                    subtitle: viewModel.stackCount > 0 ? "Unlocked" : "Create one"
                )
                AchievementBadge(
                    symbol: "bookmark.fill",
                    title: "Keeper",
                    subtitle: viewModel.bookmarkCount > 0 ? "Unlocked" : "Save one"
                )
                AchievementBadge(
                    symbol: "person.2.fill",
                    title: "In Good Company",
                    subtitle: viewModel.followerCount > 0 ? "Unlocked" : "Build a following"
                )
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .tracking(-0.35)
                .foregroundStyle(Color.stacksInk)

            VStack(spacing: 0) {
                if isCurrentProfile {
                    AccountRow(symbol: "person.crop.circle", title: "Edit profile") {
                        isEditingProfile = true
                    }
                    AccountRow(symbol: "bell", title: "Notifications") {}
                }
                AccountRow(symbol: "questionmark.circle", title: "Help & support") {
                    accountDestination = .support
                }
                AccountRow(symbol: "hand.raised", title: "Privacy policy") {
                    accountDestination = .privacy
                }
                AccountRow(symbol: "doc.text", title: "Terms of service") {
                    accountDestination = .terms
                }
                AccountRow(symbol: "dollarsign.arrow.circlepath", title: "Affiliate disclosure") {
                    accountDestination = .affiliateDisclosure
                }
                AccountRow(symbol: "lock", title: "Privacy choices") {
                    accountDestination = .privacyChoices
                }

                if isCurrentProfile {
                    AccountRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out", isDestructive: true) {
                        Task { await session.signOut() }
                    }
                    AccountRow(symbol: "trash", title: "Delete account", isDestructive: true, showsDivider: false) {
                        showsDeleteConfirmation = true
                    }
                }
            }
            .stacksGlass(cornerRadius: 24, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
        }
    }
}

private struct ProfileRedesignScreen: View {
    @State private var isShowingReportReasons = false
    @State private var isConfirmingBlock = false
    let profile: UserProfile
    let avatarData: Data?
    let stacks: [Stack]
    let heroItems: [StackItem]
    let followerCount: Int
    let productCount: Int
    let isCurrentProfile: Bool
    let isFollowing: Bool
    let onBack: () -> Void
    let onEdit: () -> Void
    let onOpenSettings: () -> Void
    let onShareProfile: () -> Void
    let onOpenStack: (Stack) -> Void
    let onToggleFollow: () -> Void
    let onReport: (String) -> Void
    let onBlock: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Short enough that the name and Edit profile / Follow sit above
                // the floating tab bar on a 6.1" iPhone without scrolling.
                ProfileHeroCollage(items: heroItems)
                    .frame(height: 430)
                    .overlay(alignment: .topLeading) {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Color.stacksInk)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.88), in: Circle())
                                .overlay { Circle().stroke(Color.stacksInk.opacity(0.08), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.top, 7)
                        .accessibilityLabel("Back")
                    }
                    .overlay(alignment: .topTrailing) {
                        if isCurrentProfile {
                            Menu {
                                Button("Settings", action: onOpenSettings)
                                Button("Share profile", systemImage: "square.and.arrow.up", action: onShareProfile)
                            } label: {
                                ProfileMoreButton()
                            }
                            .padding(20)
                        } else {
                            Menu {
                                if let profileURL = URL(string: "https://stacks.spot/\(profile.username)") {
                                    ShareLink(item: profileURL) {
                                        Label("Share profile", systemImage: "square.and.arrow.up")
                                    }
                                    .simultaneousGesture(TapGesture().onEnded { Analytics.capture("profile_shared", ["own": false]) })
                                }
                                if !CuratedStackCatalog.isCuratedProfile(profile.id) {
                                    Button("Report profile", systemImage: "flag") {
                                        isShowingReportReasons = true
                                    }
                                    Button("Block @\(profile.username)", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                                        isConfirmingBlock = true
                                    }
                                }
                            } label: {
                                ProfileMoreButton()
                            }
                            .padding(20)
                            .accessibilityLabel("More options for \(profile.displayName)")
                        }
                    }

                VStack(spacing: 0) {
                    AvatarView(profile: profile, size: 92, localImageData: avatarData)
                        .padding(.top, 18)
                        .padding(.bottom, 14)

                    VStack(spacing: 2) {
                        Text(profile.displayName)
                            .font(.system(size: 36, weight: .bold, design: .default))
                            .tracking(-1.45)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("@\(profile.username)")
                            .font(.system(size: 18, weight: .regular, design: .default))
                            .tracking(-0.35)
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                    .foregroundStyle(Color.stacksInk)
                    .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: 10) {
                        if isCurrentProfile {
                            Button("Edit profile", action: onEdit)
                                .buttonStyle(ProfilePillButtonStyle(isPrimary: false))
                                .frame(maxWidth: 330)
                        } else if !CuratedStackCatalog.isCuratedProfile(profile.id) {
                            Button(isFollowing ? "Following" : "Follow", action: onToggleFollow)
                                .buttonStyle(ProfilePillButtonStyle(isPrimary: !isFollowing))
                        } else {
                            Text("Curated by Stacks")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.stacksMutedInk)
                        }
                    }
                    .padding(.top, 19)

                    HStack(spacing: 0) {
                        ProfileStat(value: followerCount, singularTitle: "Follower", pluralTitle: "Followers")
                        ProfileStat(value: stacks.count, singularTitle: "Stack", pluralTitle: "Stacks")
                        ProfileStat(value: productCount, singularTitle: "Add", pluralTitle: "Adds")
                    }
                    .padding(.top, 31)

                    if !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(profile.bio)
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .tracking(-0.25)
                            .foregroundStyle(Color.stacksInk.opacity(0.84))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 18)
                            .padding(.top, 26)
                    }

                    HStack {
                        Text("Stacks")
                            .font(.system(size: 23, weight: .bold, design: .default))
                            .tracking(-0.7)
                        Spacer()
                        Text("\(stacks.count)")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                    .foregroundStyle(Color.stacksInk)
                    .padding(.top, 34)

                    if stacks.isEmpty {
                        ContentUnavailableView(
                            "No public Stacks yet",
                            systemImage: "square.stack.3d.up",
                            description: Text(isCurrentProfile ? "Make your first Stack to see it here." : "Check back soon.")
                        )
                        .frame(height: 190)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(stacks) { stack in
                                Button { onOpenStack(stack) } label: {
                                    ProfileFolderStackCard(stack: stack)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                // Clears the floating Stacks / Add tab bar.
                .padding(.bottom, 120)
            }
        }
        .confirmationDialog("Why are you reporting this profile?", isPresented: $isShowingReportReasons) {
            Button("Spam") { onReport("Spam") }
            Button("Harassment") { onReport("Harassment") }
            Button("Inappropriate content") { onReport("Inappropriate content") }
        }
        .confirmationDialog("Block @\(profile.username)?", isPresented: $isConfirmingBlock) {
            Button("Block", role: .destructive, action: onBlock)
        } message: {
            Text("You won't see this person's public Stacks.")
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private struct ProfileHeroCollage: View {
    let items: [StackItem]

    private let placements: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.22, 0.27, 152, -8), (0.68, 0.25, 124, 6), (0.84, 0.48, 140, 9),
        (0.29, 0.62, 160, -5), (0.63, 0.68, 145, 7), (0.16, 0.86, 110, -7)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white

                if items.isEmpty {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 74, weight: .light))
                        .foregroundStyle(Color.stacksInk.opacity(0.14))
                } else {
                    ForEach(Array(items.prefix(placements.count).enumerated()), id: \.element.id) { index, item in
                        let placement = placements[index]
                        StickerImageView(
                            item: item,
                            size: placement.2,
                            requiresCutout: true,
                            shadowOpacity: 0.07,
                            shadowRadius: 8,
                            shadowYOffset: 5
                        )
                        .rotationEffect(.degrees(placement.3))
                        .position(x: proxy.size.width * placement.0, y: proxy.size.height * placement.1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 92)
            .allowsHitTesting(false)
        }
    }
}

private struct ProfileMoreButton: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Color.stacksInk)
            .frame(width: 42, height: 42)
            .background(.white.opacity(0.88), in: Circle())
            .overlay { Circle().stroke(Color.stacksInk.opacity(0.08), lineWidth: 1) }
    }
}

private struct ProfilePillButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .default))
            .foregroundStyle(isPrimary ? .white : Color.stacksInk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isPrimary ? Color.stacksInk : Color.white, in: Capsule())
            .overlay {
                if !isPrimary {
                    Capsule().stroke(Color.stacksInk.opacity(0.10), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(isPrimary ? 0 : 0.04), radius: isPrimary ? 0 : 12, x: 0, y: 6)
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct ProfileCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.stacksInk)
            .background(Color.stacksInk.opacity(0.045), in: Circle())
            .overlay { Circle().stroke(Color.stacksInk.opacity(0.12), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct ProfileStat: View {
    let value: Int
    let singularTitle: String
    let pluralTitle: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value.formatted(.number.notation(.compactName)))
                .font(.system(size: 28, weight: .bold, design: .default))
                .tracking(-0.8)
            Text(value == 1 ? singularTitle : pluralTitle)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(Color.stacksMutedInk)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProfileFolderStackCard: View {
    let stack: Stack

    private let placements: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.25, 0.42, 0.84, -9), (0.55, 0.35, 1.0, 5), (0.78, 0.49, 0.74, 9), (0.40, 0.57, 0.66, -5)
    ]

    var body: some View {
        GeometryReader { proxy in
            let itemSize = min(proxy.size.width * 0.68, 100)
            ZStack {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.stacksInk.opacity(0.055))
                    .frame(height: proxy.size.width * 0.70)
                    .position(x: proxy.size.width / 2, y: proxy.size.width * 0.39)

                ForEach(Array(stack.items.prefix(placements.count).enumerated()), id: \.element.id) { index, item in
                    let placement = placements[index]
                    StickerImageView(item: item, size: itemSize * placement.2, requiresCutout: false, shadowOpacity: 0.10, shadowRadius: 6, shadowYOffset: 4)
                        .rotationEffect(.degrees(placement.3))
                        .position(x: proxy.size.width * placement.0, y: proxy.size.width * placement.1)
                }

                VStack(spacing: 3) {
                    Text(stack.title)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .tracking(-0.35)
                        .lineLimit(1)
                    Text("\(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(Color.stacksMutedInk)
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height - 27)
            }
        }
        .frame(height: 218)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open \(stack.displayTitle)")
    }
}

private struct AccountStat: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)")
                .font(.system(size: 29, weight: .semibold, design: .default))
                .tracking(-0.7)
            Text(title)
                .font(.system(size: 14, weight: .regular, design: .default))
                .tracking(-0.18)
                .foregroundStyle(Color.stacksMutedInk)
        }
        .foregroundStyle(Color.stacksInk)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.stacksInk.opacity(0.13))
            .frame(width: 1, height: 48)
            .padding(.horizontal, 10)
    }
}

private struct AchievementBadge: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.stacksInk)
                .frame(width: 37, height: 37)
                .background(Color.white.opacity(0.58), in: Circle())

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .default))
                .tracking(-0.2)
                .lineLimit(2)
                .foregroundStyle(Color.stacksInk)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .default))
                .tracking(-0.12)
                .foregroundStyle(Color.stacksMutedInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
        .padding(14)
        .stacksGlass(cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct AccountRow: View {
    let symbol: String
    let title: String
    var isDestructive = false
    var showsDivider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: 24)
                    Text(title)
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .tracking(-0.3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.stacksMutedInk)
                }
                .foregroundStyle(isDestructive ? Color.red : Color.stacksInk)
                .padding(.horizontal, 18)
                .frame(height: 56)

                if showsDivider {
                    Rectangle()
                        .fill(Color.stacksInk.opacity(0.09))
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    let avatarData: Data?
    let profile: UserProfile
    let onSave: (String, String, String, Data?) -> Void

    init(profile: UserProfile, avatarData: Data?, onSave: @escaping (String, String, String, Data?) -> Void) {
        self.profile = profile
        self.avatarData = avatarData
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName)
        _username = State(initialValue: profile.username)
        _bio = State(initialValue: profile.bio)
        _selectedAvatarData = State(initialValue: avatarData)
    }

    var body: some View {
        let avatarPreviewData = selectedAvatarData
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack(spacing: 14) {
                            AvatarView(profile: profile, size: 52, localImageData: avatarPreviewData)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Profile photo")
                                    .font(.system(size: 17, weight: .semibold, design: .default))
                                    .foregroundStyle(Color.stacksInk)
                                Text("Choose a photo from Camera Roll")
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                    .foregroundStyle(Color.stacksMutedInk)
                            }
                            Spacer()
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.stacksInk)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    profileField(
                        title: "Display name",
                        hint: "The name people see on your profile",
                        placeholder: "Your name",
                        text: $displayName,
                        capitalization: .words
                    )

                    profileField(
                        title: "Username",
                        hint: "Your unique @handle and profile link",
                        placeholder: "username",
                        text: $username,
                        capitalization: .never,
                        autocorrectionDisabled: true
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bio")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundStyle(Color.stacksInk)
                        Text("A short line about you (optional)")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(Color.stacksMutedInk)
                        TextField("Tell people what you collect", text: $bio, axis: .vertical)
                            .lineLimit(3...5)
                            .accessibilityLabel("Bio")
                    }
                }
                .listRowSpacing(12)
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: photoItem) {
                guard let photoItem,
                      let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                selectedAvatarData = data
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayName, username, bio, selectedAvatarData)
                        dismiss()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func profileField(
        title: String,
        hint: String,
        placeholder: String,
        text: Binding<String>,
        capitalization: TextInputAutocapitalization,
        autocorrectionDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(Color.stacksInk)
            Text(hint)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(Color.stacksMutedInk)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .accessibilityLabel(title)
        }
    }
}

private struct ProfileSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isPro: Bool
    let onPro: () -> Void
    let onEditProfile: () -> Void
    let onOpenInfo: (AccountInfoDestination) -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(StacksPro.isEnabled ? "Stacks Pro" : "Price tracking") {
                    if StacksPro.isEnabled {
                        settingsRow(isPro ? "Manage Stacks Pro" : "Get Pro", symbol: "sparkles", action: onPro)
                    }
                    NavigationLink {
                        PriceAlertsSettingsView()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "bell.badge").frame(width: 22)
                            Text("Price Alerts")
                            Spacer()
                            if !isPro {
                                Text("PRO")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                    }
                }
                Section("Profile") {
                    settingsRow("Edit profile", symbol: "person.crop.circle", action: onEditProfile)
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        settingsLabel("Notifications", symbol: "bell", showsChevron: false)
                    }
                }

                Section("Safety") {
                    NavigationLink {
                        ContentUnavailableView(
                            "No blocked accounts",
                            systemImage: "hand.raised.slash",
                            description: Text("Accounts you block will appear here.")
                        )
                        .navigationTitle("Blocked accounts")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        settingsLabel("Blocked accounts", symbol: "hand.raised.slash", showsChevron: false)
                    }
                    settingsRow("Privacy choices", symbol: "lock") { onOpenInfo(.privacyChoices) }
                }

                Section("Support & legal") {
                    settingsRow("Help & support", symbol: "questionmark.circle") { onOpenInfo(.support) }
                    settingsRow("Privacy policy", symbol: "hand.raised") { onOpenInfo(.privacy) }
                    settingsRow("Terms of service", symbol: "doc.text") { onOpenInfo(.terms) }
                    settingsRow("Affiliate disclosure", symbol: "dollarsign.arrow.circlepath") { onOpenInfo(.affiliateDisclosure) }
                }

                Section {
                    settingsRow("Sign out", symbol: "rectangle.portrait.and.arrow.right", isDestructive: true, action: onSignOut)
                    settingsRow("Delete account", symbol: "trash", isDestructive: true, action: onDeleteAccount)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { Analytics.screen("Settings") }
    }

    private func settingsRow(
        _ title: String,
        symbol: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsLabel(title, symbol: symbol, isDestructive: isDestructive)
        }
    }

    /// NavigationLink rows already get a system chevron, so they pass
    /// `showsChevron: false` to avoid drawing two.
    private func settingsLabel(_ title: String, symbol: String, isDestructive: Bool = false, showsChevron: Bool = true) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .frame(width: 22)
            Text(title)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stacksMutedInk)
            }
        }
        .font(.system(size: 16, weight: .regular, design: .default))
        .foregroundStyle(isDestructive ? Color.red : Color.stacksInk)
        .contentShape(Rectangle())
    }
}

private struct AccountInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: AccountInfoDestination
    let onRequestDeletion: () -> Void
    @State private var sharesUsageAnalytics = Analytics.isSharingEnabled

    private var publicPageURL: URL? {
        let page: String
        switch destination {
        case .support: page = "support"
        case .privacy: page = "privacy"
        case .terms: page = "terms"
        case .affiliateDisclosure: page = "affiliate"
        case .privacyChoices: page = "privacy-choices"
        }
        return URL(string: "https://stacks.spot/\(page)")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 56, height: 56)
                    .stacksGlass(cornerRadius: 18)

                Text(destination.detail)
                    .font(.system(size: 18, weight: .regular, design: .default))
                    .tracking(-0.32)
                    .foregroundStyle(Color.stacksInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let publicPageURL {
                    Link(destination: publicPageURL) {
                        Label("Read the full \(destination.title.lowercased())", systemImage: "arrow.up.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.stacksInk)
                    }
                }

                if destination == .privacyChoices {
                    Toggle(isOn: $sharesUsageAnalytics) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Share usage analytics")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Anonymous app usage tied to your account ID, never sold or used for ads.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.stacksMutedInk)
                        }
                    }
                    .tint(Color.stacksInk)
                    .onChange(of: sharesUsageAnalytics) { _, isOn in
                        Analytics.isSharingEnabled = isOn
                    }

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onRequestDeletion()
                        }
                    } label: {
                        Text("Request account deletion")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
