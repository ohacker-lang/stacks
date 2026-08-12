import PhotosUI
import SwiftUI

private enum AccountInfoDestination: Identifiable {
    case support
    case privacy
    case terms
    case privacyChoices

    var id: Self { self }

    var title: String {
        switch self {
        case .support: "Help & support"
        case .privacy: "Privacy policy"
        case .terms: "Terms of service"
        case .privacyChoices: "Privacy choices"
        }
    }

    var symbol: String {
        switch self {
        case .support: "questionmark.circle"
        case .privacy: "hand.raised"
        case .terms: "doc.text"
        case .privacyChoices: "lock"
        }
    }

    var detail: String {
        switch self {
        case .support:
            "Get help with saving products, sharing a Stack, collaboration, or your account."
        case .privacy:
            "Stacks explains what information we collect, why we use it, how long we keep it, and how to request deletion."
        case .terms:
            "These terms cover use of Stacks, shared collections, product links, and community content."
        case .privacyChoices:
            "Manage how your information is used and request access, correction, or deletion of your account data."
        }
    }
}

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var isEditingProfile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var showsDeleteConfirmation = false
    @State private var showsDeletionNotice = false
    @State private var accountDestination: AccountInfoDestination?
    @State private var editableProfile: UserProfile

    let profile: UserProfile
    let onOpenStack: (Stack) -> Void

    init(profile: UserProfile, onOpenStack: @escaping (Stack) -> Void) {
        self.profile = profile
        self.onOpenStack = onOpenStack
        _editableProfile = State(initialValue: profile)
    }

    private var isCurrentProfile: Bool {
        session.currentUser?.id == profile.id
    }

    private var presentedProfile: UserProfile {
        isCurrentProfile ? editableProfile : profile
    }

    private var avatarStorageKey: String {
        "stacks.profile.avatar.\(profile.id.uuidString)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                accountHeader
                identity
                stats
                achievements
                settings
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 52)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: profile.id) {
            avatarData = UserDefaults.standard.data(forKey: avatarStorageKey)
            await viewModel.load(services: services, profile: profile, currentUser: session.currentUser)
        }
        .task(id: photoItem) {
            guard let photoItem,
                  let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            avatarData = data
            UserDefaults.standard.set(data, forKey: avatarStorageKey)
            services.haptics.notification(.success)
        }
        .sheet(isPresented: $isEditingProfile) {
            ProfileEditSheet(profile: presentedProfile, avatarData: avatarData) { displayName, username in
                session.updateCurrentProfile(displayName: displayName, username: username)
                editableProfile.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                editableProfile.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete account?", isPresented: $showsDeleteConfirmation) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await session.requestAccountDeletion()
                    showsDeletionNotice = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This starts deletion of your account, Stacks, saved products, and profile data. This cannot be undone.")
        }
        .alert("Deletion requested", isPresented: $showsDeletionNotice) {
            Button("Done") {}
        } message: {
            Text("Your account deletion request has been started.")
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
    let avatarData: Data?
    let profile: UserProfile
    let onSave: (String, String) -> Void

    init(profile: UserProfile, avatarData: Data?, onSave: @escaping (String, String) -> Void) {
        self.profile = profile
        self.avatarData = avatarData
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName)
        _username = State(initialValue: profile.username)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(profile: profile, size: 48, localImageData: avatarData)
                        Text("Choose a profile photo from your account page.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                }

                Section("Profile") {
                    TextField("Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayName, username)
                        dismiss()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AccountInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: AccountInfoDestination
    let onRequestDeletion: () -> Void

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

                if destination == .privacyChoices {
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
