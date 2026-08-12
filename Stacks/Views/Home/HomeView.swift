import SwiftUI

private enum HomeSheet: Identifiable {
    case addOptions
    case createStack
    case importLink
    case importPhoto

    var id: String { rawValue }

    private var rawValue: String {
        switch self {
        case .addOptions: "addOptions"
        case .createStack: "createStack"
        case .importLink: "importLink"
        case .importPhoto: "importPhoto"
        }
    }
}

enum HomeLibrarySection: Hashable {
    case stacks
    case discover

    var title: String {
        switch self {
        case .stacks: "Me"
        case .discover: "Discover"
        }
    }
}

struct HomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appServices) private var services
    @State private var viewModel = HomeViewModel()
    @State private var sheet: HomeSheet?
    @State private var showsFirstStackCoachmark = false
    @State private var isCreatingFirstStack = false
    @AppStorage("stacks.hasSeenFirstStackCoachmark") private var hasSeenFirstStackCoachmark = false
    @AppStorage("stacks.lastOpenedStackID") private var lastOpenedStackID = ""
    @AppStorage("stacks.pinnedStackIDs") private var pinnedStackIDStore = ""
    @AppStorage("stacks.didSeedPinnedStacks") private var didSeedPinnedStacks = false

    @Binding var selectedSection: HomeLibrarySection
    let onOpenStack: (Stack) -> Void
    let onOpenProfile: (UserProfile) -> Void
    let onOpenDiscover: () -> Void
    let onAddProduct: () -> Void
    let onFirstStackCreated: (Stack) -> Void
    let stackTransition: Namespace.ID

    var body: some View {
        folderCarousel
        .safeAreaInset(edge: .top, spacing: 0) {
            homeSectionSwitcher
        }
        .overlay(alignment: .topTrailing) {
            if showsFirstStackCoachmark {
                FirstStackCoachmark {
                    beginFirstStackCreation()
                }
                .padding(.top, 58)
                .padding(.trailing, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadHome()
        }
        .refreshable {
            await loadHome()
        }
        .sheet(item: $sheet) { destination in
            if let user = session.currentUser {
                switch destination {
                case .addOptions:
                    HomeAddOptionsSheet { selection in
                        switch selection {
                        case .newStack:
                            sheet = .createStack
                        case .importLink:
                            sheet = .importLink
                        case .cameraRoll:
                            sheet = .importPhoto
                        case .takePicture:
                            sheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onAddProduct()
                            }
                        }
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                case .createStack:
                    CreateStackSheet(viewModel: viewModel, user: user) { stack in
                        openCreatedStack(stack)
                    }
                case .importLink:
                    ProductLinkImportSheet(user: user) { stack in
                        storeImportedStack(stack)
                    }
                case .importPhoto:
                    PhotoProductImportSheet(
                        navigationTitle: "Camera Roll",
                        startingSource: .photoLibrary,
                        user: user
                    ) { stack in
                        storeImportedStack(stack)
                    }
                }
            }
        }
    }

    private var folderCarousel: some View {
        ScrollView(showsIndicators: false) {
            if viewModel.isLoading {
                FolderCarouselLoadingState()
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Could not load Stacks",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .padding(.top, 80)
            } else if libraryStacks.isEmpty {
                StackLibraryEmptyState(section: .stacks)
            } else {
                let stacks = prioritizedStacks

                LazyVStack(spacing: 28) {
                    if let featuredStack = stacks.first {
                        Button {
                            openStack(featuredStack)
                        } label: {
                            GlassFolderStackCard(stack: featuredStack)
                                .matchedTransitionSource(id: featuredStack.id, in: stackTransition)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            pinAction(for: featuredStack)
                        }
                    }

                    if stacks.count > 1 || !visiblePinnedStacks.isEmpty {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)
                            ],
                            spacing: 22
                        ) {
                            if !visiblePinnedStacks.isEmpty {
                                Button {
                                    openPinnedStacks()
                                } label: {
                                    PinnedHomeFolderCard(stacks: visiblePinnedStacks)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open pinned Stacks")
                            }

                            ForEach(stacks.dropFirst()) { stack in
                                Button {
                                    openStack(stack)
                                } label: {
                                    CompactHomeStackCard(stack: stack)
                                        .matchedTransitionSource(id: stack.id, in: stackTransition)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    pinAction(for: stack)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 118)
            }
        }
    }

    private var homeSectionSwitcher: some View {
        ZStack {
            HStack(spacing: 18) {
                Text("Me")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .tracking(-0.35)
                    .foregroundStyle(selectedSection == .stacks ? Color.stacksInk : Color.stacksMutedInk)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        services.haptics.impact(.light)
                        withAnimation(.snappy) {
                            selectedSection = .stacks
                        }
                    }

                Button {
                    services.haptics.impact(.light)
                    onOpenDiscover()
                } label: {
                    Text("Discover")
                        .font(.system(size: 20, weight: .regular, design: .default))
                        .tracking(-0.35)
                        .foregroundStyle(selectedSection == .discover ? Color.stacksInk : Color.stacksMutedInk)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                if let user = session.currentUser {
                    Button {
                        services.haptics.impact(.light)
                        onOpenProfile(user)
                    } label: {
                        AvatarView(profile: user, size: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open profile")
                }

                Spacer()

                Button {
                    services.haptics.impact(.medium)
                    dismissFirstStackCoachmark()
                    sheet = .addOptions
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.stacksInk)
                        .frame(width: 36, height: 36)
                        .stacksGlass(cornerRadius: 18, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add product")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 7)
        .padding(.bottom, 10)
        .background(Color.white)
    }

    private var libraryStacks: [Stack] {
        selectedSection == .stacks ? viewModel.myStacks : viewModel.discoverStacks
    }

    private var prioritizedStacks: [Stack] {
        guard let lastOpened = libraryStacks.first(where: { $0.id.uuidString == lastOpenedStackID }) else {
            return libraryStacks
        }
        return [lastOpened] + libraryStacks.filter { $0.id != lastOpened.id }
    }

    private var pinnedStackIDs: Set<String> {
        Set(pinnedStackIDStore.split(separator: ",").map(String.init))
    }

    private var visiblePinnedStacks: [Stack] {
        return libraryStacks.filter {
            pinnedStackIDs.contains($0.id.uuidString)
        }
    }

    private func openStack(_ stack: Stack) {
        lastOpenedStackID = stack.id.uuidString
        services.haptics.impact(.light)
        onOpenStack(stack)
    }

    private func openPinnedStacks() {
        guard let stack = visiblePinnedStacks.first else { return }
        openStack(stack)
    }

    @ViewBuilder
    private func pinAction(for stack: Stack) -> some View {
        let isPinned = pinnedStackIDs.contains(stack.id.uuidString)
        Button(isPinned ? "Unpin from Home" : "Pin to Home") {
            togglePin(for: stack)
        }
    }

    private func togglePin(for stack: Stack) {
        var ids = pinnedStackIDs
        if ids.contains(stack.id.uuidString) {
            ids.remove(stack.id.uuidString)
        } else {
            ids.insert(stack.id.uuidString)
        }
        pinnedStackIDStore = ids.sorted().joined(separator: ",")
        services.haptics.impact(.light)
    }

    private func loadHome() async {
        guard let user = session.currentUser else { return }
        await viewModel.load(services: services, user: user)
        seedPinnedStacksIfNeeded()
        guard viewModel.myStacks.isEmpty,
              !hasSeenFirstStackCoachmark else { return }
        withAnimation(.snappy.delay(0.28)) {
            showsFirstStackCoachmark = true
        }
    }

    private func seedPinnedStacksIfNeeded() {
        guard !didSeedPinnedStacks,
              !viewModel.myStacks.isEmpty else { return }
        pinnedStackIDStore = viewModel.myStacks.prefix(3).map(\.id.uuidString).joined(separator: ",")
        didSeedPinnedStacks = true
    }

    private func beginFirstStackCreation() {
        services.haptics.impact(.medium)
        isCreatingFirstStack = true
        dismissFirstStackCoachmark()
        sheet = .createStack
    }

    private func dismissFirstStackCoachmark() {
        hasSeenFirstStackCoachmark = true
        withAnimation(.snappy) {
            showsFirstStackCoachmark = false
        }
    }

    private func openCreatedStack(_ stack: Stack) {
        let isFirstStack = isCreatingFirstStack || viewModel.myStacks.count == 1
        isCreatingFirstStack = false
        if isFirstStack {
            onFirstStackCreated(stack)
        } else {
            onOpenStack(stack)
        }
    }

    private func storeImportedStack(_ stack: Stack) {
        if let index = viewModel.myStacks.firstIndex(where: { $0.id == stack.id }) {
            viewModel.myStacks[index] = stack
        } else {
            viewModel.myStacks.insert(stack, at: 0)
        }

        if viewModel.myStacks.count == 1 {
            onFirstStackCreated(stack)
        } else {
            onOpenStack(stack)
        }
    }
}

private struct FirstStackCoachmark: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(action: onCreate) {
                Text("Create your first Stack")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Color.stacksInk, in: Capsule())
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.stacksInk)
                .padding(.trailing, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Create your first Stack with the plus button")
    }
}

private enum HomeAddSelection {
    case newStack
    case importLink
    case cameraRoll
    case takePicture
}

private struct HomeAddOptionsSheet: View {
    let onSelect: (HomeAddSelection) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(.newStack)
                } label: {
                    Label("New Stack", systemImage: "square.stack.3d.up")
                }
                Button {
                    onSelect(.importLink)
                } label: {
                    Label("Paste Product Link", systemImage: "link")
                }
                Button {
                    onSelect(.cameraRoll)
                } label: {
                    Label("Choose From Camera Roll", systemImage: "photo.on.rectangle")
                }
                Button {
                    onSelect(.takePicture)
                } label: {
                    Label("Take a Picture", systemImage: "camera")
                }
            }
            .navigationTitle("Add to Stacks")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CreateStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Bindable var viewModel: HomeViewModel

    let user: UserProfile
    let onCreated: (Stack) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Stack") {
                    TextField("Title", text: $viewModel.createTitle)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                    Toggle("Wishlist mode", isOn: $viewModel.createWishlistMode)
                }
            }
            .navigationTitle("New Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let stack = await viewModel.createStack(services: services, user: user) {
                                dismiss()
                                onCreated(stack)
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct StackRailRow: View {
    let stack: Stack
    let usesQuietBand: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StackRailHeader(title: stack.title)
            StackProductRail(stack: stack, onOpen: onOpen)
        }
        .padding(.vertical, 5)
        .background(usesQuietBand ? Color.stacksQuietSurface : Color.white)
    }
}

private struct PinnedStacksRail: View {
    let stacks: [Stack]
    let onOpen: (Stack) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pinned")
                .font(.system(size: 17, weight: .semibold, design: .default))
                .tracking(-0.35)
                .foregroundStyle(Color.stacksInk)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(stacks) { stack in
                        Button {
                            onOpen(stack)
                        } label: {
                            PinnedStackCard(stack: stack)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

private struct PinnedStackCard: View {
    let stack: Stack

    private let placements: [FolderItemPlacement] = [
        .init(x: 0.30, y: 0.52, scale: 0.92, rotation: -7),
        .init(x: 0.58, y: 0.43, scale: 1.03, rotation: 6),
        .init(x: 0.74, y: 0.59, scale: 0.72, rotation: 10)
    ]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let items = Array(stack.items.prefix(placements.count))
                let productSize = min(proxy.size.width * 0.78, 88)

                ZStack {
                    FolderGlassBack()
                        .frame(width: proxy.size.width * 0.96, height: 108)
                        .position(x: proxy.size.width / 2, y: 63)

                    if items.isEmpty {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Color.stacksInk.opacity(0.20))
                            .position(x: proxy.size.width / 2, y: 50)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let placement = placements[index]
                            StickerImageView(
                                item: item,
                                size: productSize * placement.scale,
                                requiresCutout: false,
                                shadowOpacity: 0.10,
                                shadowRadius: 6,
                                shadowYOffset: 4
                            )
                            .allowsHitTesting(false)
                            .frame(width: productSize * placement.scale, height: productSize * placement.scale)
                            .rotationEffect(.degrees(placement.rotation))
                            .position(
                                x: proxy.size.width * placement.x,
                                y: proxy.size.height * placement.y
                            )
                            .zIndex(Double(index + 1))
                        }
                    }

                    FolderGlassFront()
                        .frame(width: proxy.size.width * 0.96, height: 74)
                        .position(x: proxy.size.width / 2, y: 83)
                        .zIndex(20)
                }
            }
            .frame(height: 118)

            Text(stack.title)
                .font(.system(size: 15, weight: .regular, design: .default))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 146)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open pinned \(stack.displayTitle)")
    }
}

private struct GlassFolderStackCard: View {
    let stack: Stack

    private let placements: [FolderItemPlacement] = [
        // Start at the bottom of the box, then build a contained pile upward.
        .init(x: 0.18, y: 0.69, scale: 1.00, rotation: -9),
        .init(x: 0.46, y: 0.63, scale: 1.18, rotation: 4),
        .init(x: 0.74, y: 0.67, scale: 1.02, rotation: 9),
        .init(x: 0.83, y: 0.50, scale: 0.78, rotation: -7),
        .init(x: 0.27, y: 0.51, scale: 0.80, rotation: 7),
        .init(x: 0.56, y: 0.43, scale: 0.88, rotation: -4),
        .init(x: 0.72, y: 0.35, scale: 0.76, rotation: 6),
        .init(x: 0.39, y: 0.31, scale: 0.74, rotation: -6),
        .init(x: 0.12, y: 0.37, scale: 0.70, rotation: 8),
        .init(x: 0.89, y: 0.24, scale: 0.68, rotation: -5)
    ]

    var body: some View {
        GeometryReader { proxy in
            let folderWidth = min(proxy.size.width * 0.90, 250)
            let folderHeight = min(max(folderWidth * 0.74, 166), 204)
            let folderCenterY = proxy.size.height * 0.46
            let folderTop = folderCenterY - folderHeight / 2
            let itemSize = min(max(folderWidth * 0.40, 72), 104)
            let items = Array(stack.items.prefix(placements.count))

            ZStack {
                FolderGlassBack()
                    .frame(width: folderWidth, height: folderHeight)
                    .position(x: proxy.size.width / 2, y: folderCenterY - 8)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: folderWidth * 0.58, height: 56)
                    .position(x: proxy.size.width * 0.42, y: folderTop + 34)
                    .blur(radius: 0.2)

                if items.isEmpty {
                    FolderEmptyContents()
                        .frame(width: folderWidth, height: folderHeight)
                        .position(x: proxy.size.width / 2, y: folderCenterY - 32)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let placement = placements[index]
                        StickerImageView(
                            item: item,
                            size: itemSize * placement.scale,
                            requiresCutout: false,
                            shadowOpacity: 0.14,
                            shadowRadius: 9,
                            shadowYOffset: 7
                        )
                        .frame(width: itemSize * placement.scale, height: itemSize * placement.scale)
                        .rotationEffect(.degrees(placement.rotation))
                        .position(
                            x: (proxy.size.width - folderWidth) / 2 + folderWidth * placement.x,
                            y: folderTop + folderHeight * placement.y
                        )
                        .zIndex(Double(index + 1))
                    }
                }

                FolderGlassFront()
                    .frame(width: folderWidth, height: folderHeight * 0.78)
                    .position(x: proxy.size.width / 2, y: folderCenterY + folderHeight * 0.11)
                    .zIndex(100)

                VStack(spacing: 7) {
                    Text(stack.title)
                        .font(.system(size: 22, weight: .regular, design: .default))
                        .tracking(-0.45)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(stack.items.isEmpty ? "Ready for your first item" : "\(stack.items.count) stacked item\(stack.items.count == 1 ? "" : "s")")
                        .font(.stacksText(size: 15, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                }
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: folderCenterY + folderHeight / 2 + 42)
                .zIndex(11)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open \(stack.displayTitle)")
        }
        .frame(height: 332)
    }
}

private struct PinnedHomeFolderCard: View {
    let stacks: [Stack]

    private let placements: [FolderItemPlacement] = [
        .init(x: 0.28, y: 0.46, scale: 0.92, rotation: -9),
        .init(x: 0.53, y: 0.38, scale: 1.02, rotation: 5),
        .init(x: 0.74, y: 0.54, scale: 0.76, rotation: 10),
        .init(x: 0.45, y: 0.62, scale: 0.68, rotation: -4)
    ]

    var body: some View {
        GeometryReader { proxy in
            let items = Array(stacks.flatMap(\.items).prefix(placements.count))
            let productSize = min(proxy.size.width * 0.66, 104)

            VStack(spacing: 10) {
                ZStack {
                    FolderGlassBack()
                        .frame(width: proxy.size.width * 0.96, height: proxy.size.width * 0.72)
                        .position(x: proxy.size.width / 2, y: proxy.size.width * 0.45)

                    if items.isEmpty {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color.stacksInk.opacity(0.20))
                            .position(x: proxy.size.width / 2, y: proxy.size.width * 0.38)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            let placement = placements[index]
                            StickerImageView(
                                item: item,
                                size: productSize * placement.scale,
                                requiresCutout: false,
                                shadowOpacity: 0.12,
                                shadowRadius: 7,
                                shadowYOffset: 5
                            )
                            .allowsHitTesting(false)
                            .frame(width: productSize * placement.scale, height: productSize * placement.scale)
                            .rotationEffect(.degrees(placement.rotation))
                            .position(
                                x: proxy.size.width * placement.x,
                                y: proxy.size.width * 0.82 * placement.y
                            )
                            .zIndex(Double(index))
                        }
                    }

                    FolderGlassFront()
                        .frame(width: proxy.size.width * 0.96, height: proxy.size.width * 0.54)
                        .position(x: proxy.size.width / 2, y: proxy.size.width * 0.63)
                        .zIndex(20)
                }
                .frame(height: proxy.size.width * 0.82)

                VStack(spacing: 2) {
                    Text("Pinned")
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .tracking(-0.35)
                        .foregroundStyle(Color.stacksInk)

                    Text("\(stacks.count) Stack\(stacks.count == 1 ? "" : "s")")
                        .font(.stacksText(size: 13, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .frame(height: 206)
    }
}

private struct FeaturedHomeStackCard: View {
    let stack: Stack

    private let placements: [FolderItemPlacement] = [
        .init(x: 0.18, y: 0.55, scale: 0.80, rotation: -11),
        .init(x: 0.42, y: 0.43, scale: 1.08, rotation: 5),
        .init(x: 0.67, y: 0.54, scale: 0.92, rotation: 10),
        .init(x: 0.79, y: 0.35, scale: 0.70, rotation: -7),
        .init(x: 0.29, y: 0.31, scale: 0.68, rotation: 8),
        .init(x: 0.57, y: 0.25, scale: 0.66, rotation: -4)
    ]

    var body: some View {
        GeometryReader { proxy in
            let items = Array(stack.items.prefix(placements.count))
            let productSize = min(proxy.size.width * 0.42, 146)

            ZStack {
                if items.isEmpty {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.stacksInk.opacity(0.10), lineWidth: 1)
                        .frame(width: proxy.size.width * 0.76, height: proxy.size.height * 0.64)

                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.stacksInk.opacity(0.20))
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let placement = placements[index]
                        StickerImageView(
                            item: item,
                            size: productSize * placement.scale,
                            requiresCutout: false,
                            shadowOpacity: 0.15,
                            shadowRadius: 12,
                            shadowYOffset: 9
                        )
                        .frame(width: productSize * placement.scale, height: productSize * placement.scale)
                        .rotationEffect(.degrees(placement.rotation))
                        .position(
                            x: proxy.size.width * placement.x,
                            y: proxy.size.height * placement.y
                        )
                        .zIndex(Double(index))
                    }
                }

                VStack(spacing: 4) {
                    Text(stack.title)
                        .font(.system(size: 25, weight: .light, design: .default))
                        .tracking(-0.55)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                }
                .position(x: proxy.size.width / 2, y: 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open recently viewed \(stack.displayTitle)")
        }
        .frame(height: 334)
    }
}

private struct CompactHomeStackCard: View {
    let stack: Stack

    private let placements: [FolderItemPlacement] = [
        .init(x: 0.30, y: 0.48, scale: 1.0, rotation: -8),
        .init(x: 0.57, y: 0.39, scale: 1.10, rotation: 6),
        .init(x: 0.74, y: 0.57, scale: 0.78, rotation: 10),
        .init(x: 0.44, y: 0.64, scale: 0.76, rotation: -5)
    ]

    var body: some View {
        GeometryReader { proxy in
            let items = Array(stack.items.prefix(placements.count))
            let productSize = min(proxy.size.width * 0.66, 104)

            VStack(spacing: 10) {
                ZStack {
                    FolderGlassBack()
                        .frame(width: proxy.size.width * 0.96, height: proxy.size.width * 0.72)
                        .position(x: proxy.size.width / 2, y: proxy.size.width * 0.45)

                    if items.isEmpty {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color.stacksInk.opacity(0.20))
                            .position(x: proxy.size.width / 2, y: proxy.size.width * 0.38)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let placement = placements[index]
                            StickerImageView(
                                item: item,
                                size: productSize * placement.scale,
                                requiresCutout: false,
                                shadowOpacity: 0.12,
                                shadowRadius: 7,
                                shadowYOffset: 5
                            )
                            .frame(width: productSize * placement.scale, height: productSize * placement.scale)
                            .rotationEffect(.degrees(placement.rotation))
                            .position(
                                x: proxy.size.width * placement.x,
                                y: proxy.size.width * 0.82 * placement.y
                            )
                            .zIndex(Double(index))
                        }
                    }

                    FolderGlassFront()
                        .frame(width: proxy.size.width * 0.96, height: proxy.size.width * 0.54)
                        .position(x: proxy.size.width / 2, y: proxy.size.width * 0.63)
                        .zIndex(20)
                }
                .frame(height: proxy.size.width * 0.82)

                VStack(spacing: 2) {
                    Text(stack.title)
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .tracking(-0.35)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(stack.items.isEmpty ? "Empty" : "\(stack.items.count) finds")
                        .font(.stacksText(size: 13, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open \(stack.displayTitle)")
        }
        .frame(height: 206)
    }
}

private struct FolderItemPlacement {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double
}

private struct FolderGlassBack: View {
    var body: some View {
        ZStack {
            folderLayer(opacity: 0.08)
                .scaleEffect(0.93)
                .offset(y: 18)

            folderLayer(opacity: 0.12)
                .scaleEffect(0.965)
                .offset(y: 9)

            folderLayer(opacity: 0.18)
        }
    }

    private func folderLayer(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .background(.ultraThinMaterial.opacity(opacity), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.38), lineWidth: 1)
            }
    }
}

private struct FolderGlassFront: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .background(.ultraThinMaterial.opacity(0.42), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.56), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 10)
    }
}

private struct FolderEmptyContents: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.stacksInk.opacity(0.08))
                    .frame(width: index == 1 ? 74 : 54, height: index == 1 ? 92 : 68)
                    .rotationEffect(.degrees(index == 0 ? -9 : (index == 2 ? 8 : 0)))
            }
        }
        .opacity(0.65)
    }
}

private struct FolderCarouselLoadingState: View {
    var body: some View {
        HStack(spacing: 22) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 22) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.stacksInk.opacity(0.06))
                        .frame(width: 290, height: 240)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.stacksInk.opacity(0.08))
                        .frame(width: 124, height: 20)
                }
            }
        }
        .redacted(reason: .placeholder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StackRailHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 23, weight: .light, design: .default))
                .tracking(-0.45)
                .foregroundStyle(Color.stacksInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct StackProductRail: View {
    let stack: Stack
    let onOpen: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(stack.items) { item in
                    Button(action: onOpen) {
                        StickerImageView(item: item, size: 98)
                            .frame(width: 78, height: 122)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open (stack.displayTitle), (item.title)")
                }

                if stack.items.isEmpty {
                    Button(action: onOpen) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 30, height: 30)
                                .background(Color.stacksInk.opacity(0.08), in: Circle())
                            Text("Add your first find")
                                .font(.system(size: 16, weight: .regular, design: .default))
                                .tracking(-0.2)
                        }
                        .foregroundStyle(Color.stacksInk.opacity(0.72))
                        .frame(width: 206, height: 112)
                        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.stacksInk.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add your first item to \(stack.displayTitle)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

private struct StackRailLoadingRows: View {
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.black.opacity(0.09))
                        .frame(width: 128, height: 24)

                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            Circle()
                                .fill(Color.black.opacity(0.06))
                                .frame(width: 96, height: 96)
                        }
                    }
                }
                .padding(.vertical, 18)
                .background(index.isMultiple(of: 2) ? Color.stacksQuietSurface : Color.white)
            }
        }
        .redacted(reason: .placeholder)
    }
}

private struct StackLibraryEmptyState: View {
    let section: HomeLibrarySection

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: section == .stacks ? "square.grid.2x2" : "bookmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.stacksInk.opacity(0.45))
            Text(section == .stacks ? "No Stacks yet" : "No bookmarks yet")
                .font(.stacksText(size: 20))
                .tracking(-0.25)
                .foregroundStyle(Color.stacksInk)
            Text(section == .stacks ? "Create your first Stack with the plus button." : "Saved Stacks will appear here.")
                .font(.stacksText(size: 15))
                .foregroundStyle(Color.stacksMutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}
