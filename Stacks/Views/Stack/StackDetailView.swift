import LinkPresentation
import SwiftUI
import UIKit

private enum StackSheet: Identifiable {
    case search
    case pasteLink
    case camera
    case photoLibrary

    var id: String {
        switch self {
        case .search: "search"
        case .pasteLink: "pasteLink"
        case .camera: "camera"
        case .photoLibrary: "photoLibrary"
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
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StackDetailViewModel
    @State private var sheet: StackSheet?
    @State private var didCopyStack = false
    @State private var itemToShare: StackItem?
    @State private var itemToMove: StackItem?
    @State private var searchResultForReview: ProductSearchResult?

    let stackTransition: Namespace.ID
    let productTransition: Namespace.ID
    let onOpenProduct: (StackItem, Stack) -> Void
    private let stackID: Stack.ID

    init(
        stack: Stack,
        stackTransition: Namespace.ID,
        productTransition: Namespace.ID,
        onOpenProduct: @escaping (StackItem, Stack) -> Void
    ) {
        _viewModel = State(initialValue: StackDetailViewModel(stack: stack))
        self.stackTransition = stackTransition
        self.productTransition = productTransition
        self.onOpenProduct = onOpenProduct
        stackID = stack.id
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    StackViewerTitleBlock(stack: viewModel.stack)
                        .padding(.horizontal, 16)
                        .padding(.top, 30)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StackViewerProductCanvas(
                        stack: viewModel.stack,
                        isOwner: session.currentUser?.id == viewModel.stack.ownerID,
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
                        },
                        onShare: { itemToShare = $0 },
                        onMove: { itemToMove = $0 },
                        onBookmark: { item in
                            Task {
                                await viewModel.toggleProductBookmark(for: item.id, services: services)
                            }
                        }
                    )
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)
            }

            StackViewerNavigationOverlay(
                isOwner: session.currentUser?.id == viewModel.stack.ownerID,
                shareURL: stackShareURL,
                stackTitle: viewModel.stack.displayTitle,
                onBack: { dismiss() },
                onSelectAddSource: { source in
                    services.haptics.impact(.medium)
                    switch source {
                    case .search: sheet = .search
                    case .pastedLink: sheet = .pasteLink
                    case .camera: sheet = .camera
                    case .photoLibrary: sheet = .photoLibrary
                    case .manualPhoto: sheet = .photoLibrary
                    }
                },
                onCopy: {
                    guard let user = session.currentUser else { return }
                    Task {
                        if await viewModel.copyStack(to: user, services: services) != nil {
                            didCopyStack = true
                        }
                    }
                }
            )
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(true)
        .navigationTransition(.zoom(sourceID: stackID, in: stackTransition))
        .task {
            await services.realtime.watchStack(id: viewModel.stack.id)
            await viewModel.completeVisibleProcessingItems(services: services)
        }
        .onDisappear {
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
                        ProductLinkImportSheet(user: user, preferredStack: viewModel.stack) { savedStack in
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
            case .camera:
                Group {
                    if let user = session.currentUser {
                        PhotoProductImportSheet(
                            navigationTitle: "Take Picture",
                            startingSource: .camera,
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
            }
        }
        .sheet(item: $itemToShare) { item in
            ProductShareSheet(item: item)
        }
        .sheet(item: $itemToMove) { item in
            if let user = session.currentUser {
                MoveProductToStackSheet(
                    item: item,
                    sourceStack: viewModel.stack,
                    user: user,
                    removesOriginal: user.id == viewModel.stack.ownerID
                ) { destination in
                    Task {
                        await viewModel.transfer(
                            itemID: item.id,
                            to: destination,
                            removingOriginal: user.id == viewModel.stack.ownerID,
                            services: services
                        )
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                ContentUnavailableView("Sign in required", systemImage: "person.crop.circle")
            }
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
    }

    private var stackShareURL: URL {
        URL(string: "https://stacks.example/stacks/\(viewModel.stack.id.uuidString)")!
    }
}

private struct StackViewerNavigationOverlay: View {
    let isOwner: Bool
    let shareURL: URL
    let stackTitle: String
    let onBack: () -> Void
    let onSelectAddSource: (AddItemSource) -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            if isOwner {
                Menu {
                    Button {
                        onSelectAddSource(.search)
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    Button {
                        onSelectAddSource(.pastedLink)
                    } label: {
                        Label("Paste Link", systemImage: "link")
                    }

                    Button {
                        onSelectAddSource(.camera)
                    } label: {
                        Label("Take Picture", systemImage: "camera")
                    }

                    Button {
                        onSelectAddSource(.photoLibrary)
                    } label: {
                        Label("Camera Roll", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.stacksInk)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add product")
            } else {
                Menu {
                    ShareLink(
                        item: shareURL,
                        subject: Text(stackTitle),
                        message: Text("A Stack worth saving.")
                    ) {
                        Label("Share Stack", systemImage: "square.and.arrow.up")
                    }

                    Button(action: onCopy) {
                        Label("Copy to Your Stacks", systemImage: "square.on.square")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.stacksInk)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Stack options")
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 4)
    }
}

private struct StackViewerTitleBlock: View {
    let stack: Stack

    var body: some View {
        StackTitle(text: stack.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(1)
    }
}

private struct StackViewerProductCanvas: View {
    let stack: Stack
    let isOwner: Bool
    let productTransition: Namespace.ID
    let onTap: (StackItem) -> Void
    let onUpdatePlacement: (StackItem, StickerPlacement) -> Void
    let onShare: (StackItem) -> Void
    let onMove: (StackItem) -> Void
    let onBookmark: (StackItem) -> Void

    @ViewBuilder
    var body: some View {
        switch StackCanvasPresentation.current {
        case .editorialCollage:
            StackViewerEditorialCollage(
                stack: stack,
                isOwner: isOwner,
                productTransition: productTransition,
                onTap: onTap,
                onUpdatePlacement: onUpdatePlacement,
                onShare: onShare,
                onMove: onMove,
                onBookmark: onBookmark
            )
        case .structuredGrid:
            StackViewerProductGrid(items: stack.items, onTap: onTap)
        }
    }
}

private struct StackViewerEditorialCollage: View {
    let stack: Stack
    let isOwner: Bool
    let productTransition: Namespace.ID
    let onTap: (StackItem) -> Void
    let onUpdatePlacement: (StackItem, StickerPlacement) -> Void
    let onShare: (StackItem) -> Void
    let onMove: (StackItem) -> Void
    let onBookmark: (StackItem) -> Void

    @State private var positions: [UUID: CGPoint] = [:]

    var body: some View {
        GeometryReader { proxy in
            let layout = EditorialCollageLayout(items: stack.items, canvasSize: proxy.size)

            ZStack {
                ForEach(Array(stack.items.enumerated()), id: \.element.id) { index, item in
                    let placement = layout.placement(for: index)
                    let position = positions[item.id] ?? placement.position

                    StickerImageView(
                        item: item,
                        size: placement.size,
                        requiresCutout: true,
                        shadowOpacity: 0.07,
                        shadowRadius: 6,
                        shadowYOffset: 4
                    )
                        .rotationEffect(.degrees(placement.rotation))
                        .scaleEffect(placement.scale)
                        .matchedTransitionSource(id: item.id, in: productTransition)
                        .contentShape(Rectangle())
                        .position(position)
                        .zIndex(item.removalStatus.isWorking ? 30 : Double(index + 1))
                        .onTapGesture { onTap(item) }
                        .contextMenu {
                            Button {
                                onShare(item)
                            } label: {
                                Label("Share product", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                onMove(item)
                            } label: {
                                Label(
                                    isOwner ? "Move to Stack" : "Save to Stack",
                                    systemImage: isOwner ? "arrowshape.turn.up.right" : "square.on.square"
                                )
                            }

                            Button {
                                onBookmark(item)
                            } label: {
                                Label(
                                    item.isBookmarked == true ? "Remove bookmark" : "Bookmark product",
                                    systemImage: item.isBookmarked == true ? "bookmark.fill" : "bookmark"
                                )
                            }
                        }
                        .accessibilityIdentifier("stack-product-\(item.id.uuidString)")
                        .accessibilityHint("Opens product. Touch and hold for options.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { seedPositions(using: layout) }
            .onChange(of: stack.items.map(\.id)) { _, _ in
                seedPositions(using: layout)
            }
        }
        .frame(height: canvasHeight)
        .accessibilityElement(children: .contain)
    }

    private func seedPositions(using layout: EditorialCollageLayout) {
        var nextPositions = positions
        for index in stack.items.indices where nextPositions[stack.items[index].id] == nil {
            nextPositions[stack.items[index].id] = layout.placement(for: index).position
        }
        positions = nextPositions
    }

    private var canvasHeight: CGFloat {
        let pages = max(1, Int(ceil(Double(stack.items.count) / Double(EditorialCollageLayout.itemsPerPage))))
        return CGFloat(pages) * EditorialCollageLayout.pageHeight
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

private struct EditorialCollageLayout {
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

    static let itemsPerPage = 6
    static let pageHeight: CGFloat = 820

    private static let templates: [Template] = [
        Template(x: 0.31, y: 0.24, sizeRatio: 0.74, scale: 1.00, rotation: -2),
        Template(x: 0.80, y: 0.13, sizeRatio: 0.31, scale: 0.96, rotation: 8),
        Template(x: 0.79, y: 0.40, sizeRatio: 0.27, scale: 0.94, rotation: -5),
        Template(x: 0.22, y: 0.68, sizeRatio: 0.47, scale: 0.98, rotation: -3),
        Template(x: 0.67, y: 0.70, sizeRatio: 0.62, scale: 1.00, rotation: 3),
        Template(x: 0.66, y: 0.93, sizeRatio: 0.37, scale: 0.94, rotation: -7)
    ]

    let items: [StackItem]
    let canvasSize: CGSize

    func placement(for index: Int) -> Placement {
        let template = Self.templates[index % Self.itemsPerPage]
        let page = index / Self.itemsPerPage
        let item = items[index]
        let variation = stableVariation(for: item.id)
        let size = min(max(canvasSize.width * template.sizeRatio, 92), 290)
        let stickerScale = item.hasCustomPlacement == true
            ? CGFloat(item.placement.scale)
            : template.scale + variation.scale
        let halfFootprint = size * stickerScale / 2 + 10
        let rawX = item.hasCustomPlacement == true
            ? canvasSize.width * CGFloat(item.placement.xRatio)
            : canvasSize.width * (template.x + variation.x)
        let rawY = item.hasCustomPlacement == true
            ? CGFloat(page) * Self.pageHeight + Self.pageHeight * CGFloat(item.placement.yRatio)
            : CGFloat(page) * Self.pageHeight + Self.pageHeight * (template.y + variation.y)
        let rotation = item.hasCustomPlacement == true
            ? item.placement.rotationDegrees
            : template.rotation + variation.rotation

        return Placement(
            position: CGPoint(
                x: min(max(rawX, halfFootprint), canvasSize.width - halfFootprint),
                y: min(
                    max(rawY, CGFloat(page) * Self.pageHeight + halfFootprint),
                    CGFloat(page + 1) * Self.pageHeight - halfFootprint
                )
            ),
            size: size,
            scale: stickerScale,
            rotation: rotation
        )
    }

    private func stableVariation(for id: UUID) -> (x: CGFloat, y: CGFloat, scale: CGFloat, rotation: Double) {
        let seed = id.uuidString.unicodeScalars.reduce(UInt64(17)) { partial, scalar in
            partial &* 31 &+ UInt64(scalar.value)
        }
        let x = CGFloat(Int(seed % 11) - 5) * 0.004
        let y = CGFloat(Int((seed / 17) % 11) - 5) * 0.004
        let scale = CGFloat(Int((seed / 31) % 7) - 3) * 0.012
        let rotation = Double(Int((seed / 53) % 9) - 4) * 0.55
        return (x, y, scale, rotation)
    }
}

private struct StackViewerProductGrid: View {
    let items: [StackItem]
    let onTap: (StackItem) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 68), spacing: 12, alignment: .center),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 24) {
            ForEach(items) { item in
                StackViewerProductCell(item: item, onTap: onTap)
                    .zIndex(item.removalStatus.isWorking ? 20 : 1)
            }
        }
    }
}

private struct StackViewerProductCell: View {
    let item: StackItem
    let onTap: (StackItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let stickerSize = min(max(proxy.size.width * 1.28, 78), 132)

            Button(action: { onTap(item) }) {
                StickerImageView(item: item, size: stickerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Label("Invite Collaborator", systemImage: "person.badge.plus")
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
                                    Text("\(destination.items.count) items")
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
