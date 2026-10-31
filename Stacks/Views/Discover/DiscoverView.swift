import SwiftUI

struct DiscoverView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appServices) private var services
    @State private var viewModel = DiscoverViewModel()
    @State private var safetyMessage: String?

    @Binding var isShowingSearch: Bool
    let onOpenStack: (Stack) -> Void
    let onOpenProfile: (UserProfile) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isShowingSearch {
                    DiscoverSearchField(
                        query: $viewModel.query,
                        scope: $viewModel.searchScope,
                        selectedGenre: $viewModel.selectedGenre
                    ) {
                        Task { await viewModel.search(services: services, query: viewModel.query) }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))

                    if viewModel.searchScope == .genres && viewModel.selectedGenre == nil {
                        Text("Choose a genre to explore Stacks.")
                            .font(.stacksText(size: 15))
                            .foregroundStyle(Color.stacksMutedInk)
                    }

                    if viewModel.searchScope == .usernames,
                       !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        creatorResults
                            .transition(.opacity)
                    }
                }

                if !isShowingSearch
                    || (viewModel.searchScope == .genres && viewModel.selectedGenre != nil)
                    || (viewModel.searchScope != .genres && viewModel.searchScope != .usernames)
                    || (viewModel.searchScope == .usernames
                        && viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    stackFeed
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load(services: services)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                let cleanQuery = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                await viewModel.refresh(
                    services: services,
                    query: cleanQuery.isEmpty ? nil : cleanQuery,
                    showsLoading: false
                )
            }
        }
        .task(id: "\(isShowingSearch)-\(viewModel.searchScope.rawValue)-\(viewModel.selectedGenre?.rawValue ?? "none")-\(viewModel.query)") {
            guard isShowingSearch else { return }
            if viewModel.searchScope != .genres {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await viewModel.search(services: services, query: viewModel.query)
        }
        .onChange(of: isShowingSearch) { _, showing in
            guard !showing else { return }
            viewModel.query = ""
            viewModel.searchScope = .usernames
            viewModel.selectedGenre = nil
            Task { await viewModel.refresh(services: services) }
        }
        .refreshable {
            await viewModel.load(services: services)
        }
        .alert("Discover", isPresented: Binding(
            get: { safetyMessage != nil },
            set: { if !$0 { safetyMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(safetyMessage ?? "")
        }
    }

    private var creatorResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stacksMutedInk)

            if viewModel.matchingCreators.isEmpty {
                Text("No users found. Try another username.")
                    .font(.stacksText(size: 15))
                    .foregroundStyle(Color.stacksMutedInk)
            } else {
                ForEach(viewModel.matchingCreators.prefix(20)) { creator in
                    DiscoverCreatorRow(
                        creator: creator,
                        onOpen: { onOpenProfile(creator) },
                        onFollow: {
                            guard let user = session.currentUser else { return }
                            Task {
                                await viewModel.toggleFollow(authorID: creator.id, services: services, user: user)
                            }
                        }
                    )
                }
            }
        }
    }

    private var stackFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoading {
                LoadingRowsView()
            } else if viewModel.stacks.isEmpty {
                EmptyStateView(
                    title: "No Stacks found",
                    message: "Try another \(viewModel.searchScope.title.lowercased()) search.",
                    systemImage: "magnifyingglass"
                )
            } else {
                LazyVStack(spacing: 26) {
                    ForEach(viewModel.stacks) { stack in
                        DiscoverStackRow(
                            stack: stack,
                            onOpen: { onOpenStack(stack) },
                            onProfile: { onOpenProfile(stack.author) },
                            onFollow: {
                                guard let user = session.currentUser else { return }
                                Task {
                                    await viewModel.toggleFollow(
                                        authorID: stack.author.id,
                                        services: services,
                                        user: user
                                    )
                                }
                            },
                            onReport: { reason in
                                Task {
                                    do {
                                        try await services.safety.reportStack(id: stack.id, reason: reason)
                                        safetyMessage = "Thanks. This Stack has been reported for review."
                                    } catch {
                                        safetyMessage = error.localizedDescription
                                    }
                                }
                            },
                            onBlock: {
                                Task {
                                    do {
                                        try await services.safety.blockUser(id: stack.author.id)
                                        viewModel.stacks.removeAll { $0.author.id == stack.author.id }
                                        safetyMessage = "You won't see this person's Stacks."
                                    } catch {
                                        safetyMessage = error.localizedDescription
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

}

struct DiscoverCreatorRow: View {
    let creator: UserProfile
    var showsFollow = true
    let onOpen: () -> Void
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onOpen) {
                AvatarView(profile: creator, size: 42)
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(creator.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.stacksInk)
                    Text("@\(creator.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.stacksMutedInk)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if !showsFollow {
                EmptyView()
            } else if CuratedStackCatalog.isCuratedProfile(creator.id) {
                Text("Curated")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.stacksMutedInk)
            } else {
                Button(action: onFollow) {
                    Text(creator.isFollowing ? "Following" : "Follow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(creator.isFollowing ? Color.stacksInk : .white)
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                        .background(
                            creator.isFollowing ? Color.stacksInk.opacity(0.08) : Color.stacksInk,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(Color.stacksCream.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DiscoverStackRow: View {
    let stack: Stack
    let onOpen: () -> Void
    let onProfile: () -> Void
    let onFollow: () -> Void
    let onReport: (String) -> Void
    let onBlock: () -> Void
    @State private var isShowingReportReasons = false
    @State private var isConfirmingBlock = false
    @AppStorage("stacks.pinnedStackIDs") private var pinnedStackIDStore = ""

    private var isPinned: Bool {
        pinnedStackIDs.contains(stack.id.uuidString)
    }

    private var pinnedStackIDs: Set<String> {
        Set(pinnedStackIDStore.split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onOpen) {
                VStack(spacing: 3) {
                    Text(stack.title)
                        .font(.system(size: 29, weight: .regular, design: .default))
                        .tracking(-1.15)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text("\(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                DiscoverStackPreview(stack: stack)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button(action: onProfile) {
                    AvatarView(profile: stack.author, size: 34)
                }
                .buttonStyle(.plain)

                Button(action: onProfile) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("@\(stack.author.username)")
                            .font(.system(size: 13, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(Color.stacksInk)
                            .lineLimit(1)
                        Text(recencyText)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 0) {
                    Button(action: togglePin) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPinned ? "Unpin \(stack.title) from Home" : "Pin \(stack.title) to Home")

                    if !CuratedStackCatalog.isCuratedProfile(stack.author.id) {
                        Rectangle()
                            .fill(Color.white.opacity(0.24))
                            .frame(width: 0.75, height: 14)

                        Button(action: onFollow) {
                            Image(systemName: stack.isFollowingAuthor ? "person.badge.minus" : "person.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(stack.isFollowingAuthor ? "Unfollow \(stack.author.displayName)" : "Follow \(stack.author.displayName)")
                    }
                }
                .background(Color.stacksInk.opacity(0.94), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 7, x: 0, y: 3)

                if !CuratedStackCatalog.isCuratedStack(stack.id) {
                    Menu {
                        Button("Report Stack", systemImage: "flag") {
                            isShowingReportReasons = true
                        }
                        Button("Block @\(stack.author.username)", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                            isConfirmingBlock = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.stacksInk)
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("More options for \(stack.title)")
                }
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 31, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 31, style: .continuous)
                .stroke(Color.stacksInk.opacity(0.045), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.11), radius: 22, x: 0, y: 13)
        .frame(maxWidth: 390)
        .frame(maxWidth: .infinity)
        .confirmationDialog("Why are you reporting this Stack?", isPresented: $isShowingReportReasons) {
            Button("Spam") { onReport("Spam") }
            Button("Harassment") { onReport("Harassment") }
            Button("Inappropriate content") { onReport("Inappropriate content") }
        }
        .confirmationDialog("Block @\(stack.author.username)?", isPresented: $isConfirmingBlock) {
            Button("Block", role: .destructive, action: onBlock)
        } message: {
            Text("You won't see this person's public Stacks.")
        }
    }

    private func togglePin() {
        var ids = pinnedStackIDs
        if ids.contains(stack.id.uuidString) {
            ids.remove(stack.id.uuidString)
            Analytics.capture("stack_unpinned")
        } else {
            ids.insert(stack.id.uuidString)
            Analytics.capture("stack_pinned")
        }
        pinnedStackIDStore = ids.sorted().joined(separator: ",")
    }

    private var recencyText: String {
        let interval = max(0, Date().timeIntervalSince(stack.updatedAt))
        if interval < 60 { return "Just now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        return stack.updatedAt.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct DiscoverStackPreview: View {
    let stack: Stack

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(stack.items.prefix(6).enumerated()), id: \.element.id) { index, item in
                    StickerImageView(item: item, size: previewSize(for: index, width: proxy.size.width))
                        .rotationEffect(.degrees(previewRotation(for: index)))
                        .position(
                            x: proxy.size.width * previewPosition(for: index).x,
                            y: proxy.size.height * previewPosition(for: index).y
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func previewPosition(for index: Int) -> CGPoint {
        let positions = [
            CGPoint(x: 0.27, y: 0.27), CGPoint(x: 0.69, y: 0.24),
            CGPoint(x: 0.50, y: 0.49), CGPoint(x: 0.77, y: 0.65),
            CGPoint(x: 0.25, y: 0.72), CGPoint(x: 0.52, y: 0.81)
        ]
        return positions[index % positions.count]
    }

    private func previewSize(for index: Int, width: CGFloat) -> CGFloat {
        let scales: [CGFloat] = [0.35, 0.31, 0.37, 0.29, 0.34, 0.30]
        return min(width * scales[index % scales.count], 136)
    }

    private func previewRotation(for index: Int) -> Double {
        [-7, 6, -2, 8, 5, -6][index % 6]
    }
}

private struct DiscoverSearchField: View {
    @Binding var query: String
    @Binding var scope: DiscoverSearchScope
    @Binding var selectedGenre: DiscoverGenre?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Menu {
                ForEach(DiscoverSearchScope.allCases) { option in
                    Button {
                        scope = option
                        query = ""
                    } label: {
                        if scope == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text("Search in: \(scope.title)")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.stacksText(size: 13, weight: .medium))
                .foregroundStyle(Color.stacksInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.stacksInk.opacity(0.055), in: Capsule())
            }
            .accessibilityLabel("Search category: \(scope.title)")

            if scope == .genres {
                Menu {
                    ForEach(DiscoverGenre.allCases) { genre in
                        Button {
                            selectedGenre = genre
                        } label: {
                            if selectedGenre == genre {
                                Label(genre.title, systemImage: "checkmark")
                            } else {
                                Text(genre.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 16, weight: .semibold))
                        Text(selectedGenre?.title ?? "Choose a genre")
                            .font(.stacksText(size: 17))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.stacksInk)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(.white.opacity(0.82), in: Capsule())
                    .stacksGlass(cornerRadius: 25, interactive: true)
                }
                .accessibilityLabel("Genre: \(selectedGenre?.title ?? "Choose a genre")")
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.stacksMutedInk)

                    TextField(scope.prompt, text: $query)
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
