import SwiftUI

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

    var systemImage: String {
        switch self {
        case .home: "square.stack.3d.up"
        case .add: "camera"
        }
    }
}

private enum FirstStackTourStep {
    case addItem
    case discover
}

struct AppShellView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var lastContentTab: AppTab = .home
    @State private var homeSection: HomeLibrarySection = .stacks
    @State private var homePath: [AppRoute] = []
    @State private var pendingSharedLink: PendingSharedLink?
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
                    .withAppDestinations(
                        path: $homePath,
                        stackTransition: stackTransition,
                        productTransition: productTransition
                    )
                }
                .tabItem {
                    Label(AppTab.home.title, image: "NavStacks")
                }
                .tag(AppTab.home)

                Color.clear
                    .tabItem {
                        Label(AppTab.add.title, systemImage: AppTab.add.systemImage)
                    }
                    .tag(AppTab.add)
            }

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
        .task {
            pendingSharedLink = PendingSharedLinkStore.load()
        }
        .onOpenURL { url in
            guard url.scheme == "stacks" else { return }
            selectedTab = .home
            pendingSharedLink = PendingSharedLinkStore.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, pendingSharedLink == nil else { return }
            pendingSharedLink = PendingSharedLinkStore.load()
        }
        .fullScreenCover(item: $pendingSharedLink, onDismiss: presentNextPendingSharedLinkIfNeeded) { link in
            if let user = session.currentUser {
                PendingSharedLinkSheet(
                    link: link,
                    user: user,
                    onSaved: { stack in
                        pendingSharedLink = nil
                        selectedTab = .home
                        homePath.append(.stack(stack))
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
        .animation(.easeInOut(duration: 0.2), value: isPresentingAddProductFlow)
    }

    private func presentNextPendingSharedLinkIfNeeded() {
        guard !defersPendingSharedLink else {
            defersPendingSharedLink = false
            return
        }
        pendingSharedLink = PendingSharedLinkStore.load()
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
                }
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
            case .profile(let profile):
                ProfileView(profile: profile) { stack in
                    path.wrappedValue.append(.stack(stack))
                }
            }
        }
    }
}
