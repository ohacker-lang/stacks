import SwiftUI

struct DiscoverView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appServices) private var services
    @State private var viewModel = DiscoverViewModel()
    @State private var isShowingSearch = false

    let onOpenStack: (Stack) -> Void
    let onOpenProfile: (UserProfile) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center) {
                    Text("Discover")
                        .font(.stacksHeader(size: 44))
                        .tracking(-0.35)
                        .foregroundStyle(Color.stacksInk)

                    Spacer()

                    GlassCircleButton(systemImage: "magnifyingglass", accessibilityLabel: "Search Discover", size: 42, iconSize: 17) {
                        services.haptics.impact(.light)
                        withAnimation(.snappy) {
                            isShowingSearch.toggle()
                        }
                    }
                }

                if isShowingSearch {
                    DiscoverSearchField(query: $viewModel.query) {
                        Task { await viewModel.refresh(services: services, query: viewModel.query) }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                savedStacks
                stackFeed
                suggestedCreators
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Color.stacksCream.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.query) { _, newValue in
            guard newValue.isEmpty else { return }
            Task { await viewModel.refresh(services: services) }
        }
        .task {
            await viewModel.load(services: services)
        }
        .refreshable {
            await viewModel.load(services: services)
        }
    }

    private var savedStacks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Saved")
                .font(.stacksHeader(size: 20))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksInk)

            LazyVStack(spacing: 16) {
                ForEach(viewModel.stacks.filter(\.isBookmarked)) { stack in
                    SavedStackScrollCard(stack: stack) {
                        onOpenStack(stack)
                    }
                }
            }
        }
    }

    private var stackFeed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stacks")
                .font(.stacksHeader(size: 20))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksInk)

            if viewModel.isLoading {
                LoadingRowsView()
            } else if viewModel.stacks.isEmpty {
                EmptyStateView(title: "No Stacks found", message: "Try another creator name or Stack title.", systemImage: "magnifyingglass")
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.stacks) { stack in
                        DiscoverStackRow(
                            stack: stack,
                            onOpen: { onOpenStack(stack) },
                            onProfile: { onOpenProfile(stack.author) },
                            onFollow: {
                                guard let user = session.currentUser else { return }
                                Task {
                                    await viewModel.toggleFollow(authorID: stack.author.id, services: services, user: user)
                                }
                            },
                            onBookmark: {
                                guard let user = session.currentUser else { return }
                                Task {
                                    await viewModel.toggleBookmark(stack: stack, services: services, user: user)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var suggestedCreators: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suggested Users")
                .font(.stacksHeader(size: 20))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksInk)

            ForEach(viewModel.suggestedCreators) { creator in
                Button {
                    onOpenProfile(creator)
                } label: {
                    HStack(spacing: 14) {
                        AvatarView(profile: creator, size: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(creator.displayName)
                                .font(.stacksHeader(size: 17))
                                .tracking(-0.2)
                                .foregroundStyle(Color.stacksInk)
                            Text("@\(creator.username)")
                                .font(.stacksText(size: 14))
                                .tracking(-0.15)
                                .foregroundStyle(Color.stacksMutedInk)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                    .padding(16)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DiscoverStackRow: View {
    let stack: Stack
    let onOpen: () -> Void
    let onProfile: () -> Void
    let onFollow: () -> Void
    let onBookmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onOpen) {
                GeometryReader { proxy in
                    ZStack {
                        Color.white
                        ForEach(stack.items.prefix(5)) { item in
                            StickerImageView(item: item, size: 64)
                                .rotationEffect(.degrees(item.placement.rotationDegrees))
                                .position(
                                    x: proxy.size.width * item.placement.xRatio,
                                    y: proxy.size.height * item.placement.yRatio
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 12) {
                Button(action: onProfile) {
                    AvatarView(profile: stack.author, size: 44)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    Text(stack.displayTitle)
                        .font(.stacksHeader(size: 26))
                        .tracking(-0.3)
                        .foregroundStyle(Color.stacksInk)
                    Text("@\(stack.author.username) • \(stack.items.count) items")
                        .font(.stacksText(size: 14))
                        .tracking(-0.15)
                        .foregroundStyle(Color.stacksMutedInk)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: onBookmark) {
                        Image(systemName: stack.isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.stacksInk)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onFollow) {
                        Text(stack.isFollowingAuthor ? "Following" : "Follow")
                            .font(.stacksHeader(size: 14))
                            .tracking(-0.15)
                            .foregroundStyle(stack.isFollowingAuthor ? Color.stacksInk : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(stack.isFollowingAuthor ? .white.opacity(0.85) : Color.stacksInk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

private struct DiscoverSearchField: View {
    @Binding var query: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.stacksMutedInk)

            TextField("Username or Stack title", text: $query)
                .font(.stacksText(size: 17))
                .tracking(-0.15)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit(onSubmit)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.stacksMutedInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.white.opacity(0.82), in: Capsule())
        .stacksGlass(cornerRadius: 25, interactive: true)
    }
}

private struct SavedStackScrollCard: View {
    let stack: Stack
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { proxy in
                    ZStack {
                        Color.white
                        ForEach(stack.items.prefix(7)) { item in
                            StickerImageView(item: item, size: 72)
                                .rotationEffect(.degrees(item.placement.rotationDegrees))
                                .position(
                                    x: proxy.size.width * item.placement.xRatio,
                                    y: proxy.size.height * item.placement.yRatio
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 10) {
                    AvatarView(profile: stack.author, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stack.displayTitle)
                            .font(.stacksHeader(size: 25))
                            .tracking(-0.3)
                            .foregroundStyle(Color.stacksInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("@\(stack.author.username)")
                            .font(.stacksText(size: 14))
                            .tracking(-0.15)
                            .foregroundStyle(Color.stacksMutedInk)
                    }

                    Spacer()

                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(Color.stacksInk)
                }
            }
            .padding(14)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
