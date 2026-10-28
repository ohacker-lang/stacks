import CoreImage
import SwiftUI
import UIKit

/// Uses the supplied hand-drawn star exactly, converting its white paper
/// background into transparency and fitting the silhouette to Apple's tab
/// icon canvas. The result remains a template so selected-state tint works.
enum NavStacksArtwork {
    static let image: UIImage = {
        guard let source = UIImage(named: "NavStacksStar")?.cgImage else {
            return UIImage(systemName: "star.fill") ?? UIImage()
        }

        let side = min(source.width, source.height)
        let crop = CGRect(
            x: (source.width - side) / 2,
            y: (source.height - side) / 2,
            width: side,
            height: side
        )
        guard let square = source.cropping(to: crop) else {
            return UIImage(systemName: "star.fill") ?? UIImage()
        }

        let input = CIImage(cgImage: square)
        let transparent = input
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIMaskToAlpha")
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let masked = context.createCGImage(transparent, from: transparent.extent) else {
            return UIImage(systemName: "star.fill") ?? UIImage()
        }

        let silhouette = UIImage(cgImage: masked)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28))
        return renderer.image { _ in
            silhouette.draw(in: CGRect(x: 0, y: 0, width: 28, height: 28))
        }
        .withRenderingMode(.alwaysTemplate)
    }()
}

/// The Add tab uses the angled plus artwork from the supplied reference.
/// Drawing it at tab-icon size keeps its edges sharp without the image's
/// large light-gray canvas becoming part of the tab bar.
private enum NavAddArtwork {
    static let image: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28))
        return renderer.image { _ in
            let outline = UIBezierPath()
            outline.move(to: CGPoint(x: 12.2, y: 1))
            outline.addLine(to: CGPoint(x: 20, y: 1))
            outline.addLine(to: CGPoint(x: 18.5, y: 11.4))
            outline.addLine(to: CGPoint(x: 28, y: 11.4))
            outline.addLine(to: CGPoint(x: 27, y: 18.5))
            outline.addLine(to: CGPoint(x: 17.5, y: 18.5))
            outline.addLine(to: CGPoint(x: 16, y: 27))
            outline.addLine(to: CGPoint(x: 8.2, y: 27))
            outline.addLine(to: CGPoint(x: 9.7, y: 18.5))
            outline.addLine(to: CGPoint(x: 0, y: 18.5))
            outline.addLine(to: CGPoint(x: 1, y: 11.4))
            outline.addLine(to: CGPoint(x: 10.4, y: 11.4))
            outline.close()
            UIColor.black.setFill()
            outline.fill()
        }
    }()
}

enum AppRoute: Hashable {
    case stack(Stack)
    case product(item: StackItem, sourceStack: Stack)
    case profile(UserProfile)
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case add

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Stacks"
        case .add: "Add"
        }
    }

}

private enum FirstStackTourStep {
    case addItem
    case discover
}

struct AppShellView: View {
    @Environment(AppSession.self) private var session
    @Environment(StacksPro.self) private var pro
    @Environment(PriceAlertCenter.self) private var priceAlerts
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appServices) private var services
    @State private var selectedTab: AppTab = .home
    @State private var lastContentTab: AppTab = .home
    @State private var homeSection: HomeLibrarySection = .stacks
    @State private var homePath: [AppRoute] = []
    @State private var pendingSharedLink: PendingSharedLink?
    @State private var importConfirmation: String?
    @State private var shareDestinationRefreshID = UUID()
    @State private var defersPendingSharedLink = false
    @State private var isPresentingAddProductFlow = false
    @State private var firstStackTourStep: FirstStackTourStep?
    @AppStorage("stacks.hasCompletedFirstStackTour") private var hasCompletedFirstStackTour = false
    @Namespace private var stackTransition
    @Namespace private var productTransition

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        selectedSection: $homeSection,
                        onOpenStack: { homePath.append(.stack($0)) },
                        onOpenProfile: { homePath.append(.profile($0)) },
                        onOpenDiscover: { homeSection = .discover },
                        onAddProduct: { isPresentingAddProductFlow = true },
                        onFirstStackCreated: openFirstStackTour,
                        stackTransition: stackTransition
                    )
                    .task(id: homeSection) {
                        Analytics.screen(homeSection == .discover ? "Discover" : "Home")
                    }
                    .withAppDestinations(
                        path: $homePath,
                        stackTransition: stackTransition,
                        productTransition: productTransition
                    )
                }
                .tabItem {
                    Label {
                        Text(AppTab.home.title)
                    } icon: {
                        Image(uiImage: NavStacksArtwork.image)
                            .renderingMode(.template)
                    }
                }
                .tag(AppTab.home)

                Color.clear
                    .tabItem {
                        Label {
                            Text(AppTab.add.title)
                        } icon: {
                            Image(uiImage: NavAddArtwork.image)
                                .renderingMode(.original)
                        }
                    }
                    .tag(AppTab.add)
            }
            // Do not inherit a dark tab-bar appearance from presented stack
            // and product screens. The app shell is deliberately light glass.
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)

            if isPresentingAddProductFlow, let user = session.currentUser {
                AddProductFlowView(
                    user: user,
                    onComplete: { stack in
                        selectedTab = .home
                        homePath.append(.stack(stack))
                        isPresentingAddProductFlow = false
                    },
                    onCancel: {
                        isPresentingAddProductFlow = false
                    }
                )
                .onAppear { Analytics.screen("Add") }
                .transition(.opacity)
                .zIndex(1)
            }

            if let firstStackTourStep {
                FirstStackTourPanel(
                    step: firstStackTourStep,
                    onContinue: advanceFirstStackTour
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 94)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
            if let importConfirmation {
                Text(importConfirmation)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 62)
                    .zIndex(4)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .tint(Color.stacksInk)
        .onChange(of: selectedTab) { _, tab in
            guard tab == .add else {
                lastContentTab = tab
                return
            }

            selectedTab = lastContentTab
            isPresentingAddProductFlow = true
        }
        .onChange(of: homePath) { _, _ in
            Task { await refreshShareDestinations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stacksShareDestinationsDidChange)) { _ in
            Task { await refreshShareDestinations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stacksDidOpenPriceAlert)) { note in
            guard let stackID = note.userInfo?["stackID"] as? UUID,
                  let itemID = note.userInfo?["itemID"] as? UUID else { return }
            Task { await openPriceAlert(stackID: stackID, itemID: itemID) }
        }
        .onChange(of: session.currentUser?.id) { _, userID in
            if userID == nil {
                SharedStackDestinationStore.clear()
            } else {
                if SharedStackDestinationStore.ownerID != userID {
                    SharedStackDestinationStore.clear()
                }
                Task { await refreshShareDestinations() }
            }
        }
        .task {
            pendingSharedLink = PendingSharedLinkStore.load()
            await refreshShareDestinations()
            if let link = session.pendingSharedStackLink {
                await openUniversalStack(link)
            }
        }
        .onChange(of: session.pendingSharedStackLink) { _, link in
            guard let link else { return }
            Task { await openUniversalStack(link) }
        }
        .task(id: session.pendingProfileLink) {
            if let link = session.pendingProfileLink { await openProfileLink(link) }
        }
        .sheet(item: Binding(get: { pro.gate }, set: { if $0 == nil { pro.close() } })) { _ in
            StacksProPaywall()
        }
        .onOpenURL { url in
            guard url.scheme == "stacks" else { return }
            if url.host?.lowercased() == "wishlist",
               let tokenValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value,
               let token = UUID(uuidString: tokenValue) {
                Task { await openSharedWishlist(token: token) }
                return
            }
            selectedTab = .home
            pendingSharedLink = PendingSharedLinkStore.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pro.refreshEntitlement(); await priceAlerts.refresh() } }
            guard phase == .active, pendingSharedLink == nil else { return }
            pendingSharedLink = PendingSharedLinkStore.load()
            Task { await refreshShareDestinations() }
        }
        .fullScreenCover(item: $pendingSharedLink, onDismiss: presentNextPendingSharedLinkIfNeeded) { link in
            if let user = session.currentUser {
                if link.destinationStackID != nil || link.newStackTitle != nil {
                    SharedLinkImportProgressView(
                        link: link,
                        user: user,
                        onSaved: { stack, item in
                            pendingSharedLink = nil
                            selectedTab = .home
                            homePath.append(.stack(stack))
                            homePath.append(.product(item: item, sourceStack: stack))
                            showImportConfirmation("Added to \(stack.displayTitle).")
                        },
                        onFallback: {
                            // A deleted/out-of-date destination should never
                            // discard someone’s shared link.
                            PendingSharedLinkStore.clearDestination(for: link)
                            pendingSharedLink = PendingSharedLinkStore.load()
                        }
                    )
                } else {
                    PendingSharedLinkSheet(
                        link: link,
                        user: user,
                        onSaved: { stack, item in
                            pendingSharedLink = nil
                            selectedTab = .home
                            homePath.append(.stack(stack))
                            homePath.append(.product(item: item, sourceStack: stack))
                            showImportConfirmation("Added to \(stack.displayTitle).")
                        },
                        onDeferred: {
                            defersPendingSharedLink = true
                            pendingSharedLink = nil
                        },
                        onDiscarded: {
                            pendingSharedLink = nil
                        }
                    )
                }
            }
        }
        .sheet(item: Binding(
            get: { session.pendingCollaborationInvite },
            set: { if $0 == nil { session.dismissPendingCollaborationInvite() } }
        )) { invite in
            CollaborationInviteAcceptanceSheet(
                invite: invite,
                isAccepting: session.isAcceptingCollaborationInvite,
                onAccept: {
                    Task { await acceptCollaborationInvite() }
                },
                onDecline: session.dismissPendingCollaborationInvite
            )
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.2), value: isPresentingAddProductFlow)
    }

    @MainActor
    private func openPriceAlert(stackID: UUID, itemID: UUID) async {
        guard let userID = session.currentUser?.id,
              let stack = try? await services.stacks.fetchStack(id: stackID, for: userID),
              let item = stack.items.first(where: { $0.id == itemID }) else { return }
        selectedTab = .home
        homePath = [.stack(stack), .product(item: item, sourceStack: stack)]
        if let event = priceAlerts.events.first(where: { event in
            priceAlerts.alerts.first(where: { $0.id == event.alertID })?.stackItemID == itemID && event.readAt == nil
        }) {
            await priceAlerts.markRead(event)
        }
    }

    private func presentNextPendingSharedLinkIfNeeded() {
        guard !defersPendingSharedLink else {
            defersPendingSharedLink = false
            return
        }
        pendingSharedLink = PendingSharedLinkStore.load()
    }

    @MainActor
    private func acceptCollaborationInvite() async {
        guard let stackID = await session.acceptPendingCollaborationInvite(),
              let user = session.currentUser else { return }
        do {
            let stack = try await services.stacks.fetchStack(id: stackID, for: user.id)
            selectedTab = .home
            homeSection = .stacks
            homePath.append(.stack(stack))
        } catch {
            session.lastError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    @MainActor
    private func refreshShareDestinations() async {
        let requestID = UUID()
        shareDestinationRefreshID = requestID
        guard let user = session.currentUser else {
            SharedStackDestinationStore.clear()
            return
        }
        guard let destinations = try? await services.stacks.fetchOwnedStackDestinations(for: user),
              shareDestinationRefreshID == requestID,
              session.currentUser?.id == user.id else { return }
        SharedStackDestinationStore.save(destinations, for: user.id)
    }

    private func showImportConfirmation(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) { importConfirmation = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if importConfirmation == message {
                withAnimation(.easeIn(duration: 0.2)) { importConfirmation = nil }
            }
        }
    }

    @MainActor
    private func openSharedWishlist(token: UUID) async {
        do {
            let stack = try await services.stacks.fetchSharedStack(token: token)
            selectedTab = .home
            homeSection = .stacks
            homePath.append(.stack(stack))
            session.lastError = nil
        } catch {
            session.lastError = "This private wishlist link is invalid or no longer available."
            services.haptics.notification(.error)
        }
    }

    @MainActor
    private func openUniversalStack(_ link: SharedStackUniversalLink) async {
        guard session.pendingSharedStackLink == link,
              let user = session.currentUser else { return }
        session.clearPendingSharedStackLink()
        do {
            let stack: Stack
            if let token = link.token {
                stack = try await services.stacks.fetchSharedStack(token: token)
                guard stack.id == link.stackID else { throw AppError.notFound }
            } else {
                stack = try await services.stacks.fetchStack(id: link.stackID, for: user.id)
            }
            selectedTab = .home
            homeSection = .stacks
            homePath.append(.stack(stack))
            session.lastError = nil
        } catch {
            session.lastError = "This Stack link is invalid or no longer available."
            services.haptics.notification(.error)
        }
    }

    @MainActor
    private func openProfileLink(_ link: PublicProfileUniversalLink) async {
        guard session.pendingProfileLink == link,
              let user = session.currentUser else { return }
        session.clearPendingProfileLink()
        do {
            guard let profile = try await services.profiles.publicProfile(username: link.username) else {
                throw AppError.notFound
            }
            selectedTab = .home
            homeSection = .stacks
            homePath.append(.profile(profile))
            if let slug = link.stackSlug {
                let stacks = try await services.stacks.fetchPublicStacks(ownerID: profile.id, for: user.id)
                guard let stack = stacks.first(where: { $0.webSlug == slug }) else { throw AppError.notFound }
                homePath.append(.stack(stack))
            }
            session.lastError = nil
        } catch {
            session.lastError = "This profile or Stack is private or no longer available."
            services.haptics.notification(.error)
        }
    }

    private func openFirstStackTour(_ stack: Stack) {
        homePath.append(.stack(stack))
        guard !hasCompletedFirstStackTour else { return }
        withAnimation(.snappy) {
            firstStackTourStep = .addItem
        }
    }

    private func advanceFirstStackTour() {
        switch firstStackTourStep {
        case .addItem:
            selectedTab = .home
            homeSection = .discover
            withAnimation(.snappy) {
                firstStackTourStep = .discover
            }
        case .discover:
            hasCompletedFirstStackTour = true
            withAnimation(.snappy) {
                firstStackTourStep = nil
            }
        case nil:
            break
        }
    }
}

private struct CollaborationInviteAcceptanceSheet: View {
    let invite: CollaborationInvitePreview
    let isAccepting: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: -10) {
                AvatarView(profile: invite.owner, size: 64)
                    .zIndex(1)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 64, height: 64)
                    .background(Color.stacksInk, in: Circle())
                    .overlay { Circle().stroke(Color.white, lineWidth: 3) }
            }

            VStack(spacing: 8) {
                Text("Join \(invite.stackTitle)")
                    .font(.system(size: 29, weight: .bold, design: .default))
                    .tracking(-0.9)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("\(invite.owner.displayName) invited you to a Collab. You’ll both be able to add, edit, move, and remove finds.")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(Color.stacksMutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAccept) {
                Group {
                    if isAccepting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Join Collab")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.stacksInk, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAccepting)

            Button("Not now", action: onDecline)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.stacksMutedInk)
                .disabled(isAccepting)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .foregroundStyle(Color.stacksInk)
    }
}

private struct FirstStackTourPanel: View {
    let step: FirstStackTourStep
    let onContinue: () -> Void

    private var title: String {
        switch step {
        case .addItem: "Your Stack"
        case .discover: "Discover"
        }
    }

    private var detail: String {
        switch step {
        case .addItem:
            "Use the + in the top-right to save a photo, a product link, or something from your camera. Tap any sticker to see its details and buy link."
        case .discover:
            "Find people and their Stacks here. Follow creators, bookmark ideas, and keep the ones you want close."
        }
    }

    private var actionTitle: String {
        switch step {
        case .addItem: "Show me Discover"
        case .discover: "Finish tour"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .default))
                Spacer()
                Image(systemName: step == .addItem ? "plus" : "person.2")
                    .font(.system(size: 16, weight: .semibold))
            }

            Text(detail)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(Color.stacksMutedInk)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onContinue) {
                Text(actionTitle)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.stacksInk, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(18)
        .stacksGlass(cornerRadius: 24, interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func withAppDestinations(
        path: Binding<[AppRoute]>,
        stackTransition: Namespace.ID,
        productTransition: Namespace.ID
    ) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .stack(let stack):
                StackDetailView(
                    stack: stack,
                    stackTransition: stackTransition,
                    productTransition: productTransition
                ) { item, sourceStack in
                    path.wrappedValue.append(.product(item: item, sourceStack: sourceStack))
                } onOpenProfile: { profile in
                    path.wrappedValue.append(.profile(profile))
                }
                .onAppear { Analytics.screen("Stack") }
            case .product(let item, let sourceStack):
                ProductDetailView(
                    item: item,
                    sourceStack: sourceStack,
                    productTransition: productTransition,
                    onBack: {
                        guard !path.wrappedValue.isEmpty else { return }
                        path.wrappedValue.removeLast()
                    }
                )
                .onAppear { Analytics.screen("Product") }
            case .profile(let profile):
                ProfileView(profile: profile) { stack in
                    path.wrappedValue.append(.stack(stack))
                } onNavigateBack: {
                    guard !path.wrappedValue.isEmpty else { return }
                    path.wrappedValue.removeLast()
                }
                .onAppear { Analytics.screen("Profile") }
            }
        }
    }
}
