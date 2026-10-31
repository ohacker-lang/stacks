import LinkPresentation
import MessageUI
import Photos
import SwiftUI
import UIKit

private enum StackSheet: Identifiable {
    case search
    case pasteLink
    case photoLibrary
    case editTitle

    var id: String {
        switch self {
        case .search: "search"
        case .pasteLink: "pasteLink"
        case .photoLibrary: "photoLibrary"
        case .editTitle: "editTitle"
        }
    }
}

/// The structured grid remains available for compact surfaces, while Stack
/// detail uses the editorial collage as its primary presentation.
private enum StackCanvasPresentation {
    case editorialCollage
    case structuredGrid

    static let current: StackCanvasPresentation = .editorialCollage
}

struct StackDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(StacksPro.self) private var pro
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StackDetailViewModel
    @State private var sheet: StackSheet?
    @State private var didCopyStack = false
    @State private var searchResultForReview: ProductSearchResult?
    @State private var barcodePreview: ProductLinkPreview?
    @State private var isShowingBarcodeScanner = false
    @State private var isShowingStackShare = false
    @State private var isConfirmingDelete = false
    @State private var didDuplicateStack = false
    @State private var isShowingStackSettings = false

    let stackTransition: Namespace.ID
    let productTransition: Namespace.ID
    let onOpenProduct: (StackItem, Stack) -> Void
    let onOpenProfile: (UserProfile) -> Void
    private let stackID: Stack.ID

    private var isOwner: Bool {
        session.currentUser?.id == viewModel.stack.ownerID
    }

    private var canEdit: Bool {
        viewModel.stack.canEdit(userID: session.currentUser?.id)
    }

    init(
        stack: Stack,
        stackTransition: Namespace.ID,
        productTransition: Namespace.ID,
        onOpenProduct: @escaping (StackItem, Stack) -> Void,
        onOpenProfile: @escaping (UserProfile) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: StackDetailViewModel(stack: stack))
        self.stackTransition = stackTransition
        self.productTransition = productTransition
        self.onOpenProduct = onOpenProduct
        self.onOpenProfile = onOpenProfile
        stackID = stack.id
    }

    private var displayedStack: Stack {
        viewModel.stack.showingCurrentProfile(session.currentUser)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    StackViewerProductCanvas(
                        stack: displayedStack,
                        fadesClaimedItems: viewModel.stack.ownerID != session.currentUser?.id,
                        productTransition: productTransition,
                        onTap: { item in
                            onOpenProduct(item, viewModel.stack)
                        },
                        onUpdatePlacement: { item, placement in
                            Task {
                                await viewModel.updatePlacement(
                                    for: item.id,
                                    placement: placement,
                                    services: services
                                )
                            }
                        }
                    )
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)
            }

            if isShowingStackSettings {
                StackSettingsOverlay(
                    stack: displayedStack,
                    onDismiss: { isShowingStackSettings = false },
                    onSave: { title, visibility, wishlistMode in
                        Task {
                            await viewModel.updateSettings(
                                title: title,
                                visibility: visibility,
                                wishlistMode: wishlistMode,
                                services: services
                            )
                        }
                    },
                    onRotateWishlistLink: { revoke in
                        Task { await viewModel.rotateWishlistLink(revoke: revoke, services: services) }
                    },
                    onSetCollaborationEnabled: { enabled in
                        guard let userID = session.currentUser?.id else { return }
                        Task {
                            await viewModel.setCollaborationEnabled(enabled, services: services, userID: userID)
                        }
                    },
                    onRemoveCollaborator: { collaboratorID in
                        guard let viewerID = session.currentUser?.id else { return }
                        Task {
                            await viewModel.removeCollaborator(
                                userID: collaboratorID,
                                services: services,
                                viewerID: viewerID
                            )
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(2)
            }

            if isShowingBarcodeScanner {
                BarcodeProductScannerView(
                    onProduct: { preview in
                        barcodePreview = preview
                        dismissBarcodeScanner(thenPresent: .pasteLink)
                    },
                    onPasteLink: {
                        barcodePreview = nil
                        dismissBarcodeScanner(thenPresent: .pasteLink)
                    },
                    onChooseFromLibrary: {
                        dismissBarcodeScanner(thenPresent: .photoLibrary)
                    },
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isShowingBarcodeScanner = false
                        }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(3)
            }

        }
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            StackViewerNavigationOverlay(
                stack: displayedStack,
                isOwner: isOwner,
                canEdit: canEdit,
                onBack: { dismiss() },
                onAdd: selectAddSource,
                onCopy: {
                    guard let user = session.currentUser else { return }
                    Task {
                        if await viewModel.copyStack(to: user, services: services) != nil {
                            didCopyStack = true
                        }
                    }
                },
                onOpenSettings: {
                    // Let the native Menu finish dismissing before installing
                    // the interactive glass overlay. Presenting both in the
                    // same event occasionally swallowed the first settings tap.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isShowingStackSettings = true
                    }
                },
                onEditTitle: {
                    guard canEdit else { return }
                    services.haptics.impact(.medium)
                    sheet = .editTitle
                },
                onDuplicate: {
                    guard let user = session.currentUser else { return }
                    Task {
                        if await viewModel.copyStack(to: user, services: services) != nil {
                            didDuplicateStack = true
                        }
                    }
                },
                onDelete: {
                    isConfirmingDelete = true
                },
                onShare: {
                    services.haptics.impact(.medium)
                    isShowingStackShare = true
                },
                onOpenProfile: {
                    onOpenProfile(displayedStack.author)
                },
                onLeave: {
                    Task {
                        if await viewModel.leaveCollaboration(services: services) {
                            dismiss()
                        }
                    }
                }
            )
            .background(Color.white)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(true)
        .navigationTransition(.zoom(sourceID: stackID, in: stackTransition))
        .task {
            guard !CuratedStackCatalog.isCuratedStack(viewModel.stack.id) else { return }
            await services.realtime.watchStack(id: viewModel.stack.id)
            await viewModel.completeVisibleProcessingItems(services: services)
        }
        .task(id: viewModel.stack.id) {
            guard !CuratedStackCatalog.isCuratedStack(viewModel.stack.id) else { return }
            guard let userID = session.currentUser?.id else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await viewModel.refresh(services: services, userID: userID)
            }
        }
        .onDisappear {
            guard !CuratedStackCatalog.isCuratedStack(viewModel.stack.id) else { return }
            Task { await services.realtime.stopWatchingStack(id: viewModel.stack.id) }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .search:
                SearchAddItemSheet { result in
                    searchResultForReview = result
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .pasteLink:
                Group {
                    if let user = session.currentUser {
                        ProductLinkImportSheet(initialPreview: barcodePreview, user: user, preferredStack: viewModel.stack) { savedStack in
                            if savedStack.id == viewModel.stack.id {
                                viewModel.stack = savedStack
                            }
                        }
                    } else {
                        ContentUnavailableView("Sign in required", systemImage: "person.crop.circle")
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .photoLibrary:
                Group {
                    if let user = session.currentUser {
                        PhotoProductImportSheet(
                            navigationTitle: "Camera Roll",
                            startingSource: .photoLibrary,
                            user: user,
                            preferredStack: viewModel.stack
                        ) { savedStack in
                            if savedStack.id == viewModel.stack.id {
                                viewModel.stack = savedStack
                            }
                        }
                    } else {
                        ContentUnavailableView("Sign in required", systemImage: "person.crop.circle")
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .editTitle:
                StackTitleEditorSheet(stack: viewModel.stack) { title in
                    Task {
                        await viewModel.updateSettings(
                            title: title,
                            visibility: viewModel.stack.visibility,
                            wishlistMode: viewModel.stack.wishlistMode,
                            services: services
                        )
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingStackShare) {
            StackSharePreviewSheet(stack: displayedStack, isOwner: isOwner) {
                if let url = viewModel.stack.shareURL { return url }
                guard isOwner else { return nil }
                await viewModel.updateSettings(
                    title: viewModel.stack.title,
                    visibility: .publicLink,
                    wishlistMode: viewModel.stack.wishlistMode,
                    services: services
                )
                return viewModel.stack.shareURL
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $searchResultForReview) { result in
            if let user = session.currentUser {
                ProductLinkImportSheet(
                    initialPreview: ProductLinkPreview(
                        sourceURL: result.sourceURL,
                        title: result.title,
                        brand: result.brand,
                        shortDescription: result.shortDescription,
                        price: result.price,
                        currencyCode: result.currencyCode,
                        imageURL: result.imageURL
                    ),
                    user: user,
                    preferredStack: viewModel.stack
                ) { savedStack in
                    if savedStack.id == viewModel.stack.id {
                        viewModel.stack = savedStack
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else {
                ContentUnavailableView("Sign in required", systemImage: "person.crop.circle")
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Saved to Your Stacks", isPresented: $didCopyStack) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("A copy of \(viewModel.stack.displayTitle) is now yours to edit.")
        }
        .alert("Stack Duplicated", isPresented: $didDuplicateStack) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("A private duplicate of \(viewModel.stack.displayTitle) was added to your Stacks.")
        }
        .confirmationDialog(
            "Delete \(viewModel.stack.displayTitle)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Stack", role: .destructive) {
                Task {
                    if await viewModel.deleteStack(services: services) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Stack and every product in it. This cannot be undone.")
        }
    }

    private func selectAddSource(_ source: AddItemSource) {
        if viewModel.stack.items.count >= StacksPro.freeItemLimit && !pro.isPro {
            pro.present(.itemLimit) { selectAddSource(source) }
            return
        }
        services.haptics.impact(.medium)

        switch source {
        case .search:
            sheet = .search
        case .pastedLink:
            barcodePreview = nil
            sheet = .pasteLink
        case .camera:
            barcodePreview = nil
            withAnimation(.easeIn(duration: 0.18)) {
                isShowingBarcodeScanner = true
            }
        case .photoLibrary, .manualPhoto:
            sheet = .photoLibrary
        }
    }

    private func dismissBarcodeScanner(thenPresent destination: StackSheet) {
        withAnimation(.easeOut(duration: 0.18)) {
            isShowingBarcodeScanner = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            sheet = destination
        }
    }

}

private struct StackViewerNavigationOverlay: View {
    let stack: Stack
    let isOwner: Bool
    let canEdit: Bool
    let onBack: () -> Void
    let onAdd: (AddItemSource) -> Void
    let onCopy: () -> Void
    let onOpenSettings: () -> Void
    let onEditTitle: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onOpenProfile: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.stacksInk)
                        .frame(width: 30, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .offset(y: -2)

                Spacer(minLength: 6)

                headerActions
            }

            StackHeaderTitle(text: stack.title)
                .onLongPressGesture(minimumDuration: 0.45, perform: onEditTitle)
                .accessibilityAction(named: "Edit Stack title", onEditTitle)

            HStack {
                Button(action: onOpenProfile) {
                    HStack(spacing: 6) {
                        CollaboratorAvatarCluster(stack: stack, avatarSize: 22, maximumVisible: 4)
                        Text(stack.author.displayName)
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(Color.stacksInk.opacity(0.78))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(stack.author.displayName)'s profile")

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("Last update")
                    Text(stack.updatedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                }
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(Color.stacksMutedInk)
                .multilineTextAlignment(.trailing)
            }

            Divider()
                .overlay(Color.stacksInk.opacity(0.09))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var headerActions: some View {
        if canEdit {
            Menu {
                Button("Search", systemImage: "magnifyingglass") {
                    onAdd(.search)
                }
                Button("Paste Link", systemImage: "link") {
                    onAdd(.pastedLink)
                }
                Button("Scan Barcode", systemImage: "barcode.viewfinder") {
                    onAdd(.camera)
                }
                Button("Camera Roll", systemImage: "photo.on.rectangle") {
                    onAdd(.photoLibrary)
                }
            } label: {
                HeaderActionIcon(systemName: "plus")
            }
            .accessibilityLabel("Add product")
        }

        if isOwner {
            Menu {
                Button(action: onOpenSettings) {
                    Label("Stack Settings", systemImage: "slider.horizontal.3")
                }
                Button(action: onDuplicate) {
                    Label("Duplicate Stack", systemImage: "square.on.square")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Stack", systemImage: "trash")
                }
            } label: {
                HeaderActionIcon(systemName: "ellipsis")
            }
            .accessibilityLabel("Stack options")
        } else if canEdit {
            Menu {
                Button(action: onEditTitle) {
                    Label("Edit Stack Title", systemImage: "pencil")
                }
                Button(action: onCopy) {
                    Label("Copy to Your Stacks", systemImage: "square.on.square")
                }
                Divider()
                Button(role: .destructive, action: onLeave) {
                    Label("Leave Stack", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                HeaderActionIcon(systemName: "ellipsis")
            }
            .accessibilityLabel("Stack options")
        } else if !CuratedStackCatalog.isCuratedStack(stack.id) {
            Menu {
                Button(action: onCopy) {
                    Label("Copy to Your Stacks", systemImage: "square.on.square")
                }
            } label: {
                HeaderActionIcon(systemName: "square.on.square")
            }
            .accessibilityLabel("Stack options")
        }

        Button(action: onShare) {
            HeaderActionIcon(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share Stack")
    }
}

private struct CollaboratorAvatarCluster: View {
    let stack: Stack
    var avatarSize: CGFloat = 30
    var maximumVisible: Int = 4

    private var profiles: [UserProfile] {
        [stack.author] + stack.collaborators.map(\.user)
    }

    var body: some View {
        HStack(spacing: -avatarSize * 0.30) {
            ForEach(Array(profiles.prefix(maximumVisible).enumerated()), id: \.element.id) { index, profile in
                AvatarView(profile: profile, size: avatarSize)
                    .overlay { Circle().stroke(Color.white, lineWidth: max(1.5, avatarSize * 0.08)) }
                    .zIndex(Double(maximumVisible - index))
            }

            if profiles.count > maximumVisible {
                Text("+\(profiles.count - maximumVisible)")
                    .font(.system(size: avatarSize * 0.34, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Color.stacksInk.opacity(0.82), in: Circle())
                    .overlay { Circle().stroke(Color.white, lineWidth: max(1.5, avatarSize * 0.08)) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profiles.count) Stack \(profiles.count == 1 ? "member" : "members")")
    }
}

private struct StackHeaderTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 49, weight: .bold, design: .default))
            .tracking(-2.1)
            .foregroundStyle(Color.stacksInk)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct HeaderActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.stacksInk.opacity(0.72))
            .frame(width: 42, height: 42)
            .background(Color.stacksInk.opacity(0.055), in: Circle())
            .contentShape(Circle())
    }
}

private enum StackShareStyle: Int, CaseIterable, Identifiable {
    case cutouts, story

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .cutouts: "Cutouts"
        case .story: "Title + cutouts"
        }
    }
    var subtitle: String {
        switch self {
        case .cutouts: "Just the products, arranged together"
        case .story: "A large title with products below"
        }
    }
    var exportSize: CGSize { CGSize(width: 1080, height: 1920) }
}

private enum StackLinkShareAction: String {
    case message, copy, more
}

private struct StackSharePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stack: Stack
    let isOwner: Bool
    let makeShareURL: @MainActor () async -> URL?

    @State private var selectedStyle: StackShareStyle = .cutouts
    @State private var cutouts: [UUID: UIImage] = [:]
    @State private var avatarImage: UIImage?
    @State private var isLoading = true
    @State private var isMakingLink = false
    @State private var activityItems: StackShareActivityItems?
    @State private var messagePayload: StackShareMessagePayload?
    @State private var createdShareURL: URL?
    @State private var pendingLinkAction: StackLinkShareAction?
    @State private var isConfirmingLinkAccess = false
    @State private var feedback: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Share your Stack")
                    .font(.system(size: 25, weight: .bold))
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.stacksInk.opacity(0.06), in: Circle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    previewCarousel

                    if isLoading {
                        ProgressView("Preparing cutouts…")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                    } else if cutouts.isEmpty {
                        Text("Cutouts will appear here once your product images are ready.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.stacksMutedInk)
                            .frame(maxWidth: .infinity)
                    }

                    Button(action: shareImage) {
                        Label("Share image", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Color.stacksInk, in: Capsule())
                    }
                    .disabled(isLoading || cutouts.isEmpty)

                    Rectangle()
                        .fill(Color.stacksInk.opacity(0.1))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Share the link")
                            .font(.system(size: 18, weight: .semibold))
                        HStack(spacing: 10) {
                            linkButton("Copy link", symbol: "link", action: .copy)
                            linkButton("Share link", symbol: "square.and.arrow.up", action: .more)
                        }
                        Text(stack.wishlistMode
                             ? "Friends can view and claim gifts on the web without downloading Stacks."
                             : "Friends can open this Stack on the web without downloading Stacks.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .task(id: stack.id) {
            isLoading = true
            async let loadedCutouts = StackShareArtwork.load(for: stack)
            async let loadedAvatar = StackShareArtwork.loadAvatar(for: stack.author)
            cutouts = await loadedCutouts
            avatarImage = await loadedAvatar
            isLoading = false
        }
        .sheet(item: $activityItems) { selection in
            StackShareActivitySheet(items: selection.items)
                .onAppear { Analytics.capture("stack_shared", ["visibility": stack.visibility.analyticsValue, "channel": "share_sheet"]) }
        }
        .sheet(item: $messagePayload) { payload in
            StackShareMessageSheet(payload: payload)
                .onAppear { Analytics.capture("stack_shared", ["visibility": stack.visibility.analyticsValue, "channel": "messages"]) }
        }
        .confirmationDialog(
            "Create a private share link?",
            isPresented: $isConfirmingLinkAccess,
            titleVisibility: .visible
        ) {
            Button("Create link and continue") {
                guard let action = pendingLinkAction else { return }
                Task { await performLinkAction(action) }
            }
            Button("Cancel", role: .cancel) { pendingLinkAction = nil }
        } message: {
            Text(stack.wishlistMode
                 ? "Anyone who receives this link can view this Wishlist and claim items until you revoke the link. Future additions are visible too."
                 : "Anyone who receives this link can view this private Stack and future additions until you revoke the link.")
        }
        .alert("Share Stack", isPresented: Binding(
            get: { feedback != nil },
            set: { if !$0 { feedback = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedback ?? "")
        }
    }

    private var previewCarousel: some View {
        GeometryReader { proxy in
            let cardWidth = min(238, proxy.size.width * 0.70)

            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(StackShareStyle.allCases) { style in
                            StackShareCard(stack: stack, style: style, cutouts: cutouts, avatarImage: avatarImage)
                                .frame(width: 1080, height: 1920)
                                .scaleEffect(cardWidth / 1080, anchor: .topLeading)
                                .frame(width: cardWidth, height: cardWidth * 16 / 9, alignment: .topLeading)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(
                                            selectedStyle == style ? Color.stacksInk.opacity(0.34) : Color.stacksInk.opacity(0.08),
                                            lineWidth: selectedStyle == style ? 2 : 1
                                        )
                                }
                                .shadow(color: .black.opacity(0.11), radius: 18, y: 8)
                                .id(style)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.28)) {
                                        selectedStyle = style
                                        reader.scrollTo(style, anchor: .center)
                                    }
                                }
                                .accessibilityLabel("Preview of \(style.title)")
                                .accessibilityAddTraits(selectedStyle == style ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .onChange(of: selectedStyle) { _, style in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        reader.scrollTo(style, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 400)
    }

    private func linkButton(_ title: String, symbol: String, action: StackLinkShareAction) -> some View {
        Button {
            requestLinkAction(action)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .foregroundStyle(Color.stacksInk)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isMakingLink)
    }

    private func requestLinkAction(_ action: StackLinkShareAction) {
        if createdShareURL == nil && stack.shareURL == nil {
            guard isOwner else {
                feedback = "Only this Stack's owner can create a share link."
                return
            }
            pendingLinkAction = action
            isConfirmingLinkAccess = true
        } else {
            Task { await performLinkAction(action) }
        }
    }

    @MainActor
    private func performLinkAction(_ action: StackLinkShareAction) async {
        isMakingLink = true
        defer {
            isMakingLink = false
            pendingLinkAction = nil
        }
        let resolvedURL: URL?
        if let createdShareURL {
            resolvedURL = createdShareURL
        } else {
            resolvedURL = await makeShareURL()
        }
        guard let url = resolvedURL else {
            feedback = "The link could not be prepared. Please try again."
            return
        }
        createdShareURL = url
        let preview = cutouts.isEmpty ? nil : renderedImage()
        switch action {
        case .message:
            messagePayload = StackShareMessagePayload(url: url, title: stack.title, image: preview)
        case .copy:
            UIPasteboard.general.url = url
            feedback = "Link copied."
        case .more:
            activityItems = StackShareActivityItems(items: [
                StackShareLinkActivityItem(url: url, title: stack.title, image: preview)
            ])
        }
    }

    @MainActor
    private func renderedImage(scale: CGFloat = 1) -> UIImage? {
        let size = selectedStyle.exportSize
        let renderer = ImageRenderer(content:
            StackShareCard(stack: stack, style: selectedStyle, cutouts: cutouts, avatarImage: avatarImage)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        return renderer.uiImage
    }

    private func shareImage() {
        guard let image = renderedImage() else {
            feedback = "The image could not be prepared. Please try again."
            return
        }
        // The system share sheet presents installed story destinations when
        // they support image sharing; no third-party app is required.
        activityItems = StackShareActivityItems(items: [image])
    }

    private func saveImage() {
        guard let image = renderedImage() else {
            feedback = "The image could not be prepared. Please try again."
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in feedback = "Allow Stacks to add photos in Settings to save this image." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    feedback = success ? "Saved to Photos." : "Could not save the image. Please try again."
                }
            }
        }
    }

    private func saveHighResolutionImage() {
        guard let image = renderedImage(scale: 2) else {
            feedback = "The high-resolution image could not be prepared. Please try again."
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in feedback = "Allow Stacks to add photos in Settings to save this image." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    feedback = success ? "High-resolution image saved to Photos." : "Could not save the image. Please try again."
                }
            }
        }
    }
}

private struct StackShareCard: View {
    let stack: Stack
    let style: StackShareStyle
    let cutouts: [UUID: UIImage]
    let avatarImage: UIImage?

    private var canvas: CGSize { style.exportSize }
    private var visibleItems: [StackItem] {
        Array(stack.items.filter { cutouts[$0.id] != nil }.prefix(6))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            if style == .story {
                VStack(alignment: .leading, spacing: 10) {
                    Text(stack.displayTitle)
                        .font(.system(size: 88, weight: .bold))
                        .tracking(-3.5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 13) {
                        if let avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            AvatarView(profile: stack.author, size: 48)
                        }
                        Text(stack.author.displayName)
                            .font(.system(size: 28, weight: .medium))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Rectangle()
                        .fill(Color.stacksInk.opacity(0.18))
                        .frame(height: 2)
                }
                .frame(width: canvas.width - 144, height: 330)
                .position(x: canvas.width / 2, y: 282)
            }

            let rows = max(1, (visibleItems.count + 1) / 2)
            let productTop: CGFloat = style == .story ? 548 : 220
            let productHeight: CGFloat = style == .story ? 1080 : 1470
            let rowHeight = productHeight / CGFloat(rows)
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                if let image = cutouts[item.id] {
                    let lastUnpaired = visibleItems.count.isMultiple(of: 2) == false && index == visibleItems.count - 1
                    let x = lastUnpaired ? canvas.width / 2 : canvas.width * (index.isMultiple(of: 2) ? 0.27 : 0.73)
                    let y = productTop + rowHeight * (CGFloat(index / 2) + 0.5)
                    let size = visibleItems.count == 1 ? 620 : min(430, rowHeight * 0.85)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.09), radius: 16, y: 9)
                        .position(x: x, y: y)
                }
            }

            if style == .story {
                Text("Made with Stacks")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.stacksMutedInk)
                    .position(x: canvas.width / 2, y: 1825)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .foregroundStyle(Color.stacksInk)
        .clipped()
    }
}

private enum StackShareArtwork {
    static func load(for stack: Stack) async -> [UUID: UIImage] {
        var images: [UUID: UIImage] = [:]
        for item in stack.items {
            if Task.isCancelled { break }
            if let url = item.removedBackgroundImageURL {
                if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                    images[item.id] = image
                } else if let (data, _) = try? await URLSession.shared.data(from: url),
                          let image = UIImage(data: data) {
                    images[item.id] = image
                }
            } else if let asset = DemoProductImageCatalog.assetName(for: item.title),
                      let image = UIImage(named: asset),
                      let alpha = image.cgImage?.alphaInfo,
                      alpha != CGImageAlphaInfo.none,
                      alpha != CGImageAlphaInfo.noneSkipFirst,
                      alpha != CGImageAlphaInfo.noneSkipLast {
                images[item.id] = image
            }
            if images.count == 6 { break }
        }
        return images
    }

    static func loadAvatar(for profile: UserProfile) async -> UIImage? {
        if let data = AvatarStore.data(for: profile.id), let image = UIImage(data: data) {
            return image
        }
        guard let url = profile.avatarURL,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

private struct StackShareActivityItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct StackShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct StackShareMessagePayload: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let image: UIImage?
}

private struct StackShareMessageSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let payload: StackShareMessagePayload

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard MFMessageComposeViewController.canSendText() else {
            let controller = UIActivityViewController(
                activityItems: [StackShareLinkActivityItem(url: payload.url, title: payload.title, image: payload.image)],
                applicationActivities: nil
            )
            controller.completionWithItemsHandler = { _, _, _, _ in
                Task { @MainActor in context.coordinator.onDismiss() }
            }
            return controller
        }

        let composer = MFMessageComposeViewController()
        composer.body = "Take a look at \(payload.title) on Stacks:\n\(payload.url.absoluteString)"
        if MFMessageComposeViewController.canSendAttachments(),
           let data = payload.image?.pngData() {
            composer.addAttachmentData(data, typeIdentifier: "public.png", filename: "Stacks Story.png")
        }
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, @MainActor MFMessageComposeViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onDismiss()
        }
    }
}

private final class StackShareLinkActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let image: UIImage?

    init(url: URL, title: String, image: UIImage?) {
        self.url = url
        self.title = title
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "\(title) · Stacks"
        metadata.originalURL = url
        metadata.url = url
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}

private struct StackSettingsOverlay: View {
    @Environment(\.appServices) private var services
    @Environment(StacksPro.self) private var pro

    let stack: Stack
    let onDismiss: () -> Void
    let onSave: (String, StackVisibility, Bool) -> Void
    let onRotateWishlistLink: (Bool) -> Void
    let onSetCollaborationEnabled: (Bool) -> Void
    let onRemoveCollaborator: (UUID) -> Void

    @State private var visibility: StackVisibility
    @State private var wishlistMode: Bool
    @State private var collaborationEnabled: Bool
    @State private var isChoosingCollabContacts = false
    @State private var queuedInviteMessages: [StackContactInviteMessage] = []
    @State private var activeInviteMessage: StackContactInviteMessage?
    @State private var inviteError: String?
    @State private var editor: StackSettingsEditor?
    @State private var isConfirmingLinkActivation = false
    @State private var isConfirmingLinkReset = false
    @State private var isConfirmingLinkRevoke = false

    init(
        stack: Stack,
        onDismiss: @escaping () -> Void,
        onSave: @escaping (String, StackVisibility, Bool) -> Void,
        onRotateWishlistLink: @escaping (Bool) -> Void,
        onSetCollaborationEnabled: @escaping (Bool) -> Void,
        onRemoveCollaborator: @escaping (UUID) -> Void
    ) {
        self.stack = stack
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onRotateWishlistLink = onRotateWishlistLink
        self.onSetCollaborationEnabled = onSetCollaborationEnabled
        self.onRemoveCollaborator = onRemoveCollaborator
        _visibility = State(initialValue: stack.visibility)
        _wishlistMode = State(initialValue: stack.wishlistMode)
        _collaborationEnabled = State(initialValue: stack.collaborationEnabled)
    }

    var body: some View {
        ZStack {
            // A soft paper wash keeps the Stack faintly visible behind settings
            // without its products showing through the glass cards and help
            // text. Tapping it dismisses the popover.
            Color.white.opacity(0.86)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            StackSettingsGlassContainer(spacing: 12) {
                VStack(spacing: 10) {
                StackSettingsActionCard(
                    title: "Edit title",
                    subtitle: stack.displayTitle
                ) {
                    editor = .title
                }

                StackSettingsActionCard(
                    title: "Visibility",
                    subtitle: visibilityDescription
                ) {
                    editor = .visibility
                }

                StackSettingsActionCard(
                    title: "Wishlist",
                    subtitle: wishlistMode ? "Friends can claim items." : "Keep this Stack for inspiration.",
                    trailing: {
                        Toggle("Wishlist", isOn: $wishlistMode)
                            .labelsHidden()
                            .tint(.stacksInk)
                            .onChange(of: wishlistMode) { _, newValue in
                                onSave(stack.title, visibility, newValue)
                            }
                    },
                    // The card's button receives taps on the switch too, so it
                    // has to flip the value itself.
                    action: { wishlistMode.toggle() }
                )

                if wishlistMode {
                    if let shareURL = stack.shareURL {
                        ShareLink(item: shareURL) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Share wishlist link")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Color.stacksInk)
                                    Text("Anyone with the link can view and claim gifts.")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color.stacksInk.opacity(0.62))
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.stacksInk)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 62)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .stackSettingsGlass(cornerRadius: 20)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { Analytics.capture("stack_shared", ["visibility": stack.visibility.analyticsValue, "channel": "wishlist_link"]) })
                        if stack.visibility == .publicLink {
                            StackSettingsActionCard(
                                title: "Reset wishlist link",
                                subtitle: "Old links stop working immediately."
                            ) { isConfirmingLinkReset = true }
                            StackSettingsActionCard(
                                title: "Revoke wishlist link",
                                subtitle: "Make it private and disable this link."
                            ) { isConfirmingLinkRevoke = true }
                        }
                    } else {
                        StackSettingsActionCard(
                            title: "Enable wishlist link",
                            subtitle: "Create a private link people can use to claim gifts."
                        ) {
                            isConfirmingLinkActivation = true
                        }
                    }
                    Text("People with your unique link can view and claim on stacks.spot using an email code—no app account or public profile needed. Claimed items fade for recipients, not for you. Anyone holding the link, including you in an anonymous browser, can see the recipient view.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.stacksInk.opacity(0.65))
                        .padding(.horizontal, 8)
                }

                StackSettingsActionCard(
                    title: "Collab",
                    subtitle: collaborationEnabled
                        ? "Everyone in this Collab can edit."
                        : "Only you can edit this Stack.",
                    trailing: {
                        Toggle("Collab", isOn: $collaborationEnabled)
                            .labelsHidden()
                            .tint(.stacksInk)
                            .onChange(of: collaborationEnabled) { _, enabled in
                                onSetCollaborationEnabled(enabled)
                            }
                    },
                    action: { collaborationEnabled.toggle() }
                )

                if collaborationEnabled {
                    StackSettingsActionCard(
                        title: "Add people",
                        subtitle: "Choose contacts to invite to this Collab."
                    ) {
                        isChoosingCollabContacts = true
                    }

                    if !stack.collaborators.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(stack.collaborators) { collaborator in
                                HStack(spacing: 11) {
                                    AvatarView(profile: collaborator.user, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(collaborator.user.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.stacksInk)
                                        Text("@\(collaborator.user.username) · Collab")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(Color.stacksMutedInk)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        onRemoveCollaborator(collaborator.user.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(width: 32, height: 32)
                                            .background(Color.stacksInk.opacity(0.055), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(collaborator.user.displayName) from Collab")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)

                                if collaborator.id != stack.collaborators.last?.id {
                                    Divider().padding(.leading, 61)
                                }
                            }
                        }
                        .stackSettingsGlass(cornerRadius: 24)
                    }
                }

                    Button("Done", action: onDismiss)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.stacksInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .stackSettingsGlass(cornerRadius: 27, interactive: true)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: 520)
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .title:
                StackTitleEditorSheet(stack: stack) { title in
                    onSave(title, visibility, wishlistMode)
                }
            case .visibility:
                StackVisibilityEditorSheet(selection: $visibility) { selection in
                    onSave(stack.title, selection, wishlistMode)
                }
            }
        }
        .sheet(isPresented: $isChoosingCollabContacts) {
            StackInviteContactPicker { recipients in
                guard !recipients.isEmpty else { return }
                Task { await createContactInvites(for: recipients) }
            }
        }
        .sheet(item: $activeInviteMessage, onDismiss: presentNextInvite) { message in
            StackInviteMessageSheet(message: message) {
                activeInviteMessage = nil
            }
        }
        .alert("Couldn't create invite", isPresented: Binding(
            get: { inviteError != nil },
            set: { if !$0 { inviteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteError ?? "Try again.")
        }
        .confirmationDialog("Share this wishlist?", isPresented: $isConfirmingLinkActivation) {
            Button("Create private link") {
                visibility = .publicLink
                onSave(stack.title, .publicLink, true)
            }
        } message: {
            Text("Anyone with this unique link can view and claim on the website. It won't appear in Discover.")
        }
        .confirmationDialog("Reset this link?", isPresented: $isConfirmingLinkReset) {
            Button("Reset link") { onRotateWishlistLink(false) }
        } message: {
            Text("Previously shared links will stop working.")
        }
        .confirmationDialog("Revoke this link?", isPresented: $isConfirmingLinkRevoke) {
            Button("Revoke link", role: .destructive) {
                visibility = .private
                onRotateWishlistLink(true)
            }
        } message: {
            Text("This wishlist becomes private. Previously shared links will stop working.")
        }
    }

    private var visibilityDescription: String {
        switch visibility {
        case .private: "Only you can see it."
        case .inviteOnly: "Only invited people can open it."
        case .publicLink: "Anyone with the link can view it."
        case .publicDiscover: "Anyone can see it on your profile."
        }
    }

    private func createContactInvites(for recipients: [String]) async {
        guard pro.isPro
                || stack.collaborators.count + recipients.count <= StacksPro.freeCollaboratorLimit else {
            pro.present(.collaboratorLimit) { isChoosingCollabContacts = true }
            return
        }
        guard pro.requireCollaboratorSlot(in: stack, resume: {
            isChoosingCollabContacts = true
        }) else { return }

        var messages: [StackContactInviteMessage] = []
        do {
            for recipient in recipients {
                let invite = try await services.collaboration.createInvite(to: stack, permission: .edit)
                guard let link = invite.deepLink else { throw AppError.invalidURL }
                messages.append(
                    StackContactInviteMessage(
                        recipient: recipient,
                        body: "Join my Collab “\(stack.displayTitle)” in Stacks: \(link.absoluteString)"
                    )
                )
            }
            queuedInviteMessages.append(contentsOf: messages)
            presentNextInvite()
            services.haptics.notification(.success)
        } catch {
            if StacksPro.isCollaboratorLimitError(error) {
                pro.present(.collaboratorLimit) { isChoosingCollabContacts = true }
                return
            }
            inviteError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    private func presentNextInvite() {
        guard activeInviteMessage == nil, !queuedInviteMessages.isEmpty else { return }
        activeInviteMessage = queuedInviteMessages.removeFirst()
    }
}

private enum StackSettingsEditor: Identifiable {
    case title
    case visibility

    var id: Self { self }
}

private struct StackSettingsActionCard<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing
    let action: () -> Void

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.stacksInk)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.stacksInk.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(minHeight: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .stackSettingsGlass(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}

private extension StackSettingsActionCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            trailing: { EmptyView() },
            action: action
        )
    }
}

private extension View {
    @ViewBuilder
    func stackSettingsGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.75), lineWidth: 1)
                }
        }
    }
}

private struct StackSettingsGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

private struct StackTitleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stack: Stack
    let onSave: (String) -> Void
    @State private var title: String

    init(stack: Stack, onSave: @escaping (String) -> Void) {
        self.stack = stack
        self.onSave = onSave
        _title = State(initialValue: stack.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Stack title", text: $title)
            }
            .navigationTitle("Edit title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.visible)
    }
}

private struct StackVisibilityEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: StackVisibility
    let onSave: (StackVisibility) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(StackVisibility.allCases, id: \.self) { option in
                    Button {
                        selection = option
                        onSave(option)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: visibilityIcon(option))
                                .foregroundStyle(Color.stacksInk)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                Text(description(for: option))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.stacksInk)
                            }
                        }
                    }
                    .foregroundStyle(Color.stacksInk)
                }
            }
            .navigationTitle("Visibility")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func visibilityIcon(_ option: StackVisibility) -> String {
        switch option {
        case .private: "lock.fill"
        case .inviteOnly: "person.2.fill"
        case .publicLink: "link"
        case .publicDiscover: "globe"
        }
    }

    private func description(for option: StackVisibility) -> String {
        switch option {
        case .private: "Only you can view this Stack."
        case .inviteOnly: "Only people you invite can open it."
        case .publicLink: "Anyone with the link can view it."
        case .publicDiscover: "Anyone can see it on your stacks.spot profile."
        }
    }
}

private struct StackViewerProductCanvas: View {
    let stack: Stack
    let fadesClaimedItems: Bool
    let productTransition: Namespace.ID
    let onTap: (StackItem) -> Void
    let onUpdatePlacement: (StackItem, StickerPlacement) -> Void

    @ViewBuilder
    var body: some View {
        switch StackCanvasPresentation.current {
        case .editorialCollage:
            StackViewerEditorialCollage(
                stack: stack,
                fadesClaimedItems: fadesClaimedItems,
                productTransition: productTransition,
                onTap: onTap,
                onUpdatePlacement: onUpdatePlacement
            )
        case .structuredGrid:
            StackViewerProductGrid(items: stack.items, fadesClaimedItems: fadesClaimedItems, onTap: onTap)
        }
    }
}

private struct StackViewerEditorialCollage: View {
    let stack: Stack
    let fadesClaimedItems: Bool
    let productTransition: Namespace.ID
    let onTap: (StackItem) -> Void
    let onUpdatePlacement: (StackItem, StickerPlacement) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = EditorialCollageLayout(items: stack.items, canvasSize: proxy.size)

            ZStack {
                if stack.items.isEmpty {
                    Image("EmptyStackArtwork")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(proxy.size.width * 0.48, 190))
                        .accessibilityLabel("This Stack is empty")
                }

                ForEach(Array(stack.items.enumerated()), id: \.element.id) { index, item in
                    let placement = layout.placement(for: index)

                    StickerImageView(
                        item: item,
                        size: placement.size,
                        requiresCutout: true,
                        shadowOpacity: 0.07,
                        shadowRadius: 6,
                        shadowYOffset: 4
                    )
                        .saturation(fadesClaimedItems && item.claimStatus != nil ? 0 : 1)
                        .opacity(fadesClaimedItems && item.claimStatus != nil ? 0.30 : 1)
                        .rotationEffect(.degrees(placement.rotation))
                        .scaleEffect(placement.scale)
                        .matchedTransitionSource(id: item.id, in: productTransition)
                        .contentShape(Rectangle())
                        .position(placement.position)
                        .zIndex(item.removalStatus.isWorking ? 30 : Double(index + 1))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -56)),
                            removal: .opacity
                        ))
                        .onTapGesture { onTap(item) }
                        .accessibilityIdentifier("stack-product-\(item.id.uuidString)")
                        .accessibilityLabel(fadesClaimedItems && item.claimStatus != nil ? "\(item.title), already claimed" : item.title)
                        .accessibilityHint("Opens product details.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(Rectangle())
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: stack.items.map(\.id))
        }
        .frame(height: canvasHeight)
        .accessibilityElement(children: .contain)
    }

    private var canvasHeight: CGFloat {
        EditorialCollageLayout.canvasHeight(for: stack.items.count)
    }
}

private struct CanvasProductActionPalette: View {
    let item: StackItem
    let isOwner: Bool
    let onShare: () -> Void
    let onMove: () -> Void
    let onBookmark: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            paletteButton("Share product", systemImage: "square.and.arrow.up", action: onShare)
            paletteButton(
                isOwner ? "Move to Stack" : "Save to Stack",
                systemImage: isOwner ? "arrowshape.turn.up.right" : "square.on.square",
                action: onMove
            )
            paletteButton(
                item.isBookmarked == true ? "Remove product bookmark" : "Bookmark product",
                systemImage: item.isBookmarked == true ? "bookmark.fill" : "bookmark",
                action: onBookmark
            )
            paletteButton("Close", systemImage: "xmark", action: onDismiss)
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 7)
        .accessibilityElement(children: .contain)
    }

    private func paletteButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.stacksInk)
                .frame(width: 42, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct EditorialCollageLayout {
    struct Placement {
        let position: CGPoint
        let size: CGFloat
        let scale: CGFloat
        let rotation: Double

        var footprint: CGFloat {
            size * scale
        }
    }

    private struct Template {
        let x: CGFloat
        let y: CGFloat
        let sizeRatio: CGFloat
        let scale: CGFloat
        let rotation: Double
    }

    static let itemsPerPage = 4
    private static let compactPageHeight: CGFloat = 420
    private static let roomyPageHeight: CGFloat = 520

    private static let compactTemplates: [Template] = [
        Template(x: 0.27, y: 0.17, sizeRatio: 0.43, scale: 1.00, rotation: -2),
        Template(x: 0.73, y: 0.18, sizeRatio: 0.35, scale: 0.96, rotation: 7),
        Template(x: 0.25, y: 0.50, sizeRatio: 0.40, scale: 0.98, rotation: -5),
        Template(x: 0.75, y: 0.50, sizeRatio: 0.39, scale: 0.98, rotation: 3),
        Template(x: 0.29, y: 0.83, sizeRatio: 0.38, scale: 1.00, rotation: -7),
        Template(x: 0.72, y: 0.82, sizeRatio: 0.36, scale: 0.96, rotation: 5)
    ]

    // Each page uses two columns and up to two rows. One item sits in the
    // center; the third sits below the first pair until a fourth fills its row.
    let items: [StackItem]
    let canvasSize: CGSize

    static func canvasHeight(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return compactPageHeight }
        if itemCount <= itemsPerPage { return roomyPageHeight }

        let completePages = itemCount / itemsPerPage
        let trailingItems = itemCount % itemsPerPage
        return CGFloat(completePages) * compactPageHeight
            + (trailingItems == 0 ? 0 : roomyPageHeight)
    }

    func placement(for index: Int) -> Placement {
        let isSingleItem = items.count == 1
        let page = index / Self.itemsPerPage
        let indexInPage = index % Self.itemsPerPage
        let itemsOnPage = min(Self.itemsPerPage, items.count - page * Self.itemsPerPage)
        let usesRoomyLayout = items.count <= Self.itemsPerPage || itemsOnPage < Self.itemsPerPage
        let pageHeight = usesRoomyLayout ? Self.roomyPageHeight : Self.compactPageHeight
        let pageStart = Self.pageStart(for: page, totalItems: items.count)
        let item = items[index]
        let rows = max(1, (itemsOnPage + 1) / 2)
        let row = indexInPage / 2
        let isCenteredItem = itemsOnPage == 1 || (itemsOnPage == 3 && indexInPage == 2)
        let columnX: CGFloat = isCenteredItem ? 0.5 : (indexInPage.isMultiple(of: 2) ? 0.25 : 0.75)
        let rowY = (CGFloat(row) + 0.5) / CGFloat(rows)
        let size = isSingleItem
            ? min(canvasSize.width * 0.64, pageHeight * 0.48, 250)
            : min(canvasSize.width * 0.42, pageHeight / CGFloat(rows) * 0.70, 205)
        let stickerScale = item.hasCustomPlacement == true
            ? CGFloat(item.placement.scale)
            : 1
        let halfFootprint = size * stickerScale * 0.51 + 4
        let rawX = isSingleItem ? canvasSize.width * 0.5 : item.hasCustomPlacement == true
            ? canvasSize.width * CGFloat(item.placement.xRatio)
            : canvasSize.width * columnX
        let rawY = isSingleItem ? pageStart + pageHeight * 0.5 : item.hasCustomPlacement == true
            ? pageStart + pageHeight * CGFloat(item.placement.yRatio)
            : pageStart + pageHeight * rowY
        let rotation = isSingleItem ? 0 : item.hasCustomPlacement == true
            ? item.placement.rotationDegrees
            : 0

        return Placement(
            position: CGPoint(
                x: min(max(rawX, halfFootprint), canvasSize.width - halfFootprint),
                y: min(
                    max(rawY, pageStart + halfFootprint),
                    pageStart + pageHeight - halfFootprint
                )
            ),
            size: size,
            scale: stickerScale,
            rotation: rotation
        )
    }

    private static func pageStart(for page: Int, totalItems: Int) -> CGFloat {
        guard page > 0 else { return 0 }
        let completedDensePages = min(page, totalItems / itemsPerPage)
        return CGFloat(completedDensePages) * compactPageHeight
    }

    private static func roomyTemplates(for itemCount: Int) -> [Template] {
        switch itemCount {
        case 1:
            [Template(x: 0.50, y: 0.50, sizeRatio: 0.66, scale: 1.00, rotation: -2)]
        case 2:
            [
                Template(x: 0.31, y: 0.33, sizeRatio: 0.56, scale: 1.00, rotation: -4),
                Template(x: 0.69, y: 0.68, sizeRatio: 0.56, scale: 1.00, rotation: 4)
            ]
        case 3:
            [
                Template(x: 0.28, y: 0.27, sizeRatio: 0.52, scale: 1.00, rotation: -4),
                Template(x: 0.72, y: 0.47, sizeRatio: 0.50, scale: 1.00, rotation: 5),
                Template(x: 0.34, y: 0.75, sizeRatio: 0.52, scale: 1.00, rotation: 2)
            ]
        case 4:
            [
                Template(x: 0.27, y: 0.27, sizeRatio: 0.49, scale: 1.00, rotation: -4),
                Template(x: 0.73, y: 0.28, sizeRatio: 0.47, scale: 1.00, rotation: 4),
                Template(x: 0.29, y: 0.72, sizeRatio: 0.47, scale: 1.00, rotation: 3),
                Template(x: 0.72, y: 0.72, sizeRatio: 0.49, scale: 1.00, rotation: -4)
            ]
        case 5:
            [
                Template(x: 0.25, y: 0.22, sizeRatio: 0.47, scale: 1.00, rotation: -3),
                Template(x: 0.74, y: 0.24, sizeRatio: 0.44, scale: 1.00, rotation: 5),
                Template(x: 0.50, y: 0.51, sizeRatio: 0.48, scale: 1.00, rotation: -2),
                Template(x: 0.25, y: 0.80, sizeRatio: 0.44, scale: 1.00, rotation: -5),
                Template(x: 0.73, y: 0.79, sizeRatio: 0.47, scale: 1.00, rotation: 4)
            ]
        default:
            [
                Template(x: 0.25, y: 0.20, sizeRatio: 0.48, scale: 1.00, rotation: -3),
                Template(x: 0.74, y: 0.23, sizeRatio: 0.43, scale: 1.00, rotation: 5),
                Template(x: 0.31, y: 0.51, sizeRatio: 0.45, scale: 1.00, rotation: 3),
                Template(x: 0.76, y: 0.54, sizeRatio: 0.46, scale: 1.00, rotation: -4),
                Template(x: 0.25, y: 0.82, sizeRatio: 0.43, scale: 1.00, rotation: -5),
                Template(x: 0.73, y: 0.81, sizeRatio: 0.47, scale: 1.00, rotation: 4)
            ]
        }
    }

    private func stableVariation(for id: UUID) -> (x: CGFloat, y: CGFloat, scale: CGFloat, rotation: Double) {
        let seed = id.uuidString.unicodeScalars.reduce(UInt64(17)) { partial, scalar in
            partial &* 31 &+ UInt64(scalar.value)
        }
        let x = CGFloat(Int(seed % 11) - 5) * 0.002
        let y = CGFloat(Int((seed / 17) % 11) - 5) * 0.002
        let scale = CGFloat(Int((seed / 31) % 7) - 3) * 0.006
        let rotation = Double(Int((seed / 53) % 9) - 4) * 0.35
        return (x, y, scale, rotation)
    }
}

private struct StackViewerProductGrid: View {
    let items: [StackItem]
    let fadesClaimedItems: Bool
    let onTap: (StackItem) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 68), spacing: 12, alignment: .center),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 24) {
            ForEach(items) { item in
                StackViewerProductCell(item: item, fadesClaimedItems: fadesClaimedItems, onTap: onTap)
                    .zIndex(item.removalStatus.isWorking ? 20 : 1)
            }
        }
    }
}

private struct StackViewerProductCell: View {
    let item: StackItem
    let fadesClaimedItems: Bool
    let onTap: (StackItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let stickerSize = min(max(proxy.size.width * 1.28, 78), 132)

            Button(action: { onTap(item) }) {
                StickerImageView(item: item, size: stickerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .saturation(fadesClaimedItems && item.claimStatus != nil ? 0 : 1)
                    .opacity(fadesClaimedItems && item.claimStatus != nil ? 0.36 : 1)
                    .overlay(alignment: .bottom) {
                        if fadesClaimedItems, item.claimStatus != nil {
                            Label("Claimed", systemImage: "checkmark.circle.fill")
                                .font(.stacksText(size: 12, weight: .semibold))
                                .foregroundStyle(Color.stacksInk.opacity(0.62))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.88), in: Capsule())
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stack-product-\(item.id.uuidString)")
        }
        .frame(height: 142)
    }
}

private struct StackMoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stack: Stack

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Label("Share Stack", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label(stack.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: stack.isBookmarked ? "bookmark.slash" : "bookmark")
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label("Add to Collab", systemImage: "person.badge.plus")
                    }
                }
            }
            .navigationTitle("Stack Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MoveProductToStackSheet: View {
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss

    let item: StackItem
    let sourceStack: Stack
    let user: UserProfile
    let removesOriginal: Bool
    let onSelect: (Stack) -> Void

    @State private var stacks: [Stack] = []
    @State private var errorMessage: String?

    private var destinations: [Stack] {
        stacks.filter { $0.id != sourceStack.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView(
                        "Couldn’t load your Stacks",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if stacks.isEmpty {
                    ProgressView()
                } else if destinations.isEmpty {
                    ContentUnavailableView(
                        "Create another Stack first",
                        systemImage: "square.stack.3d.up",
                        description: Text("You can place \(item.title) there once it exists.")
                    )
                } else {
                    List(destinations) { destination in
                        Button {
                            onSelect(destination)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.stacksInk)
                                    .frame(width: 32, height: 32)
                                    .background(Color.stacksInk.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(destination.displayTitle)
                                        .font(.stacksText(size: 17, weight: .semibold))
                                        .foregroundStyle(Color.stacksInk)
                                    Text("\(destination.items.count) \(destination.items.count == 1 ? "find" : "finds")")
                                        .font(.stacksText(size: 13, weight: .regular))
                                        .foregroundStyle(Color.stacksInk.opacity(0.58))
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.stacksInk.opacity(0.42))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(removesOriginal ? "Move Product" : "Save Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                do {
                    stacks = try await services.stacks.fetchMyStacks(for: user.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ProductShareSheet: UIViewControllerRepresentable {
    let item: StackItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [ProductShareActivityItem(item: item)],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class ProductShareActivityItem: NSObject, UIActivityItemSource {
    private let item: StackItem

    init(item: StackItem) {
        self.item = item
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        item.purchaseURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        item.purchaseURL
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = item.brand.isEmpty ? item.title : "\(item.title) · \(item.brand)"
        metadata.originalURL = item.purchaseURL
        metadata.url = item.purchaseURL

        if let imageURL = item.removedBackgroundImageURL,
           imageURL.isFileURL,
           let image = UIImage(contentsOfFile: imageURL.path) {
            metadata.imageProvider = NSItemProvider(object: image)
        }

        return metadata
    }
}
