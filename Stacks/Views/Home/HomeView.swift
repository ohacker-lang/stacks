import Contacts
import ContactsUI
import MessageUI
import SwiftUI

private enum HomeExperiments {
    /// Flip to `false` to restore the original folder homepage without removing this prototype.
    static let walletStackBrowser = false
}

private enum HomeSheet: Identifiable {
    case createStack

    var id: String { rawValue }

    private var rawValue: String {
        switch self {
        case .createStack: "createStack"
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
    @State private var isShowingDiscoverSearch = false
    @State private var showsFirstStackCoachmark = false
    @State private var isCreatingFirstStack = false
    @State private var isOwnedExpanded = true
    @State private var isPinnedExpanded = true
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
        Group {
            if selectedSection == .discover {
                DiscoverView(
                    isShowingSearch: $isShowingDiscoverSearch,
                    onOpenStack: openStack,
                    onOpenProfile: onOpenProfile
                )
            } else if HomeExperiments.walletStackBrowser {
                walletCarousel
            } else {
                folderCarousel
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .stacksCollaborationDidChange)) { _ in
            Task { await loadHome() }
        }
        .sheet(item: $sheet) { destination in
            if let user = session.currentUser {
                switch destination {
                case .createStack:
                    CreateStackSheet(viewModel: viewModel, user: user) { stack in
                        openCreatedStack(stack)
                    }
                }
            }
        }
    }

    private var walletCarousel: some View {
        Group {
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
                StackLibraryEmptyState(section: selectedSection)
            } else {
                WalletRolodexDeck(
                    stacks: walletStacks,
                    stackTransition: stackTransition,
                    onOpen: openStack
                )
                .padding(.bottom, 72)
            }
        }
    }

    private struct WalletRolodexDeck: View {
        let stacks: [Stack]
        let stackTransition: Namespace.ID
        let onOpen: (Stack) -> Void

        @State private var activeIndex = 0
        @GestureState private var dragTranslation: CGFloat = 0

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(stacks.enumerated()), id: \.element.id) { index, stack in
                        let relativeIndex = index - activeIndex

                        if abs(relativeIndex) <= 4 {
                            Button {
                                onOpen(stack)
                            } label: {
                                WalletStackCard(stack: stack, index: index)
                                    .matchedTransitionSource(id: stack.id, in: stackTransition)
                            }
                            .buttonStyle(.plain)
                            .frame(width: min(proxy.size.width - 58, 344))
                            .scaleEffect(cardScale(relativeIndex))
                            .offset(y: cardOffset(relativeIndex))
                            .opacity(abs(relativeIndex) == 4 ? 0.62 : 1)
                            .zIndex(relativeIndex == 0 ? 100 : Double(20 - abs(relativeIndex)))
                            .allowsHitTesting(relativeIndex == 0)
                            .accessibilityHidden(relativeIndex != 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(deckGesture)
            }
            .onChange(of: stacks.map(\.id)) { _, _ in
                activeIndex = min(activeIndex, max(stacks.count - 1, 0))
            }
        }

        private func cardScale(_ relativeIndex: Int) -> CGFloat {
            relativeIndex == 0 ? 1 : max(0.78, 0.90 - CGFloat(abs(relativeIndex)) * 0.025)
        }

        private func cardOffset(_ relativeIndex: Int) -> CGFloat {
            if relativeIndex == 0 {
                return dragTranslation * 0.32
            }

            let distance = CGFloat(min(abs(relativeIndex), 4))
            let filedOffset = 100 + distance * 25
            return (relativeIndex < 0 ? filedOffset : -filedOffset) + dragTranslation * 0.06
        }

        private var deckGesture: some Gesture {
            DragGesture(minimumDistance: 12)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let projected = value.predictedEndTranslation.height
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        if projected < -48, activeIndex < stacks.count - 1 {
                            activeIndex += 1
                        } else if projected > 48, activeIndex > 0 {
                            activeIndex -= 1
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

                LazyVStack(alignment: .leading, spacing: 30) {
                    if let featuredStack = stacks.first {
                        VStack(alignment: .leading, spacing: 8) {
                            HomeLibrarySectionHeading(title: "Recent")

                            Button {
                                openStack(featuredStack)
                            } label: {
                                FeaturedHomeStackCard(stack: featuredStack)
                                    .matchedTransitionSource(id: featuredStack.id, in: stackTransition)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                pinAction(for: featuredStack)
                            }
                            .frame(maxWidth: 430)
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HomeLibrarySectionHeading(
                            title: "Owned",
                            isExpanded: isOwnedExpanded
                        ) {
                            withAnimation(.snappy(duration: 0.32)) {
                                isOwnedExpanded.toggle()
                            }
                        }

                        if isOwnedExpanded {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)
                                ],
                                spacing: 22
                            ) {
                                ForEach(viewModel.myStacks) { stack in
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
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 12) {
                        HomeLibrarySectionHeading(
                            title: "Pinned",
                            isExpanded: isPinnedExpanded
                        ) {
                            withAnimation(.snappy(duration: 0.32)) {
                                isPinnedExpanded.toggle()
                            }
                        }

                        if isPinnedExpanded {
                            if visiblePinnedStacks.isEmpty {
                                Text("Pin a Stack to keep it close.")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(Color.stacksMutedInk)
                                    .padding(.vertical, 8)
                            } else {
                                PinnedStacksRail(stacks: visiblePinnedStacks, onOpen: openStack)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 118)
            }
        }
    }

    private var homeSectionSwitcher: some View {
        ZStack {
            HStack(spacing: 18) {
                Text("Stacks")
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
                    if selectedSection == .discover {
                        services.haptics.impact(.light)
                        withAnimation(.snappy) {
                            isShowingDiscoverSearch.toggle()
                        }
                    } else {
                        services.haptics.impact(.medium)
                        dismissFirstStackCoachmark()
                        sheet = .createStack
                    }
                } label: {
                    Image(systemName: selectedSection == .discover ? "magnifyingglass" : "plus")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.stacksInk)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedSection == .discover ? "Search Discover" : "Create a new Stack")
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .stacksGlass(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 0.75)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
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

    private var walletStacks: [Stack] {
        let primary = prioritizedStacks
        let primaryIDs = Set(primary.map(\.id))
        let supplemental = (selectedSection == .stacks ? viewModel.discoverStacks : viewModel.myStacks)
            .filter { !primaryIDs.contains($0.id) }
        return primary + supplemental
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

private enum CreateStackStep: Int, CaseIterable {
    case name
    case kind
    case access
    case collab
    case make
}

private struct CreateStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(StacksPro.self) private var pro
    @Bindable var viewModel: HomeViewModel
    @FocusState private var isTitleFocused: Bool
    @State private var step: CreateStackStep = .name
    @State private var isChoosingInviteContacts = false
    @State private var inviteRecipients: [String] = []
    @State private var pendingCreatedStack: Stack?
    @State private var queuedInviteMessages: [StackContactInviteMessage] = []
    @State private var activeInviteMessage: StackContactInviteMessage?
    @State private var inviteError: String?

    let user: UserProfile
    let onCreated: (Stack) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            TabView(selection: $step) {
                namePage.tag(CreateStackStep.name)
                kindPage.tag(CreateStackStep.kind)
                accessPage.tag(CreateStackStep.access)
                collabPage.tag(CreateStackStep.collab)
                makePage.tag(CreateStackStep.make)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: step)

            sheetControls
        }
        .padding(10)
        .stacksClearGlass(cornerRadius: 34)
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.46), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .presentationBackground(.clear)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTitleFocused = true
            }
        }
        .onChange(of: step) { oldStep, newStep in
            if oldStep == .name,
               newStep.rawValue > oldStep.rawValue,
               trimmedTitle.isEmpty {
                step = .name
                isTitleFocused = true
                return
            }
            isTitleFocused = newStep == .name
        }
        .sheet(isPresented: $isChoosingInviteContacts) {
            StackInviteContactPicker { recipients in
                inviteRecipients = recipients
            }
        }
        .sheet(item: $activeInviteMessage, onDismiss: presentNextInviteOrFinish) { message in
            StackInviteMessageSheet(message: message) {
                activeInviteMessage = nil
            }
        }
        .alert("Stack created, but the invite couldn't open", isPresented: Binding(
            get: { inviteError != nil },
            set: { if !$0 { inviteError = nil } }
        )) {
            Button("Continue", action: finishCreatedStack)
        } message: {
            Text(inviteError ?? "You can add people to the Collab from Stack settings.")
        }
    }

    private var trimmedTitle: String {
        viewModel.createTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sheetHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("New Stack")
                    .font(.system(size: 16, weight: .semibold))

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .stacksClearGlass(cornerRadius: 20, interactive: true)
                    .buttonStyle(.plain)

                    Spacer()
                }
            }

            HStack(spacing: 7) {
                ForEach(CreateStackStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue
                              ? Color.stacksInk
                              : Color.stacksInk.opacity(0.13))
                        .frame(width: item == step ? 25 : 7, height: 7)
                        .animation(.snappy, value: step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(CreateStackStep.allCases.count)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var namePage: some View {
        CreateStackPage(
            title: "Name your Stack",
            subtitle: "Give it a name you’ll recognize. You can change it later."
        ) {
            ZStack {
                if viewModel.createTitle.isEmpty {
                    ShimmeringNewStackPrompt(text: "Tap here to name your stack")
                        .allowsHitTesting(false)
                }

                TextField("", text: $viewModel.createTitle)
                    .font(.stacksMasthead(size: 44))
                    .tracking(-1.8)
                    .foregroundStyle(Color.stacksInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .submitLabel(.next)
                    .onSubmit { moveForward() }
                    .accessibilityLabel("Stack name")
            }
            .frame(maxWidth: 520)
            .frame(minHeight: 118)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { isTitleFocused = true }
        }
    }

    private var kindPage: some View {
        CreateStackPage(
            title: "What are you making?",
            subtitle: "Keep ideas for inspiration, or make a wishlist people can shop together."
        ) {
            VStack(spacing: 12) {
                CreateStackChoiceCard(
                    title: "Inspo Stack",
                    detail: "Collect ideas, products, and things you love.",
                    symbol: nil,
                    centersContent: true,
                    isSelected: !viewModel.createWishlistMode
                ) {
                    withAnimation(.snappy) {
                        viewModel.createWishlistMode = false
                        viewModel.createVisibility = .defaultForNewStacks
                    }
                }

                CreateStackChoiceCard(
                    title: "Wishlist",
                    detail: "Share gifts people can claim so no one chooses the same item twice.",
                    symbol: nil,
                    centersContent: true,
                    isSelected: viewModel.createWishlistMode
                ) {
                    withAnimation(.snappy) {
                        viewModel.createWishlistMode = true
                    }
                }
            }
            .frame(maxWidth: 520)
        }
    }

    private var accessPage: some View {
        CreateStackPage(
            title: "Who can open it?",
            subtitle: "Choose how people can see this Stack. You can change this later in Settings."
        ) {
            VStack(spacing: 12) {
                CreateStackChoiceCard(
                    title: "Everyone",
                    detail: "It shows on your profile at stacks.spot/\(user.username.lowercased()).",
                    symbol: nil,
                    centersContent: true,
                    isSelected: viewModel.createVisibility == .publicDiscover
                ) {
                    viewModel.createVisibility = .publicDiscover
                }

                CreateStackChoiceCard(
                    title: "Anyone with the link",
                    detail: viewModel.createWishlistMode
                        ? "It stays out of Discover. People with the private link can view and claim gifts."
                        : "It stays out of Discover. Only people with the private link can view it.",
                    symbol: nil,
                    centersContent: true,
                    isSelected: viewModel.createVisibility == .publicLink
                ) {
                    viewModel.createVisibility = .publicLink
                }

                CreateStackChoiceCard(
                    title: "Only me and my Collab",
                    detail: "Keep it private and invite specific people who can edit with you.",
                    symbol: nil,
                    centersContent: true,
                    isSelected: viewModel.createVisibility == .private
                ) {
                    viewModel.createVisibility = .private
                }
            }
            .frame(maxWidth: 520)
        }
    }

    private var collabPage: some View {
        CreateStackPage(
            title: "Collab",
            subtitle: "Invite people who can add, edit, and arrange finds with you."
        ) {
            Button {
                isTitleFocused = false
                isChoosingInviteContacts = true
            } label: {
                VStack(spacing: 6) {
                    Text(inviteRecipients.isEmpty ? "Add people" : "Edit people")
                        .font(.system(size: 18, weight: .semibold))

                    Text(inviteRecipients.isEmpty
                         ? "Choose contacts for this Collab."
                         : "\(inviteRecipients.count) friend\(inviteRecipients.count == 1 ? "" : "s") selected")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.stacksMutedInk)
                }
                .foregroundStyle(Color.stacksInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .frame(minHeight: 92)
                .padding(.horizontal, 18)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .stacksGlass(cornerRadius: 24, interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if inviteRecipients.isEmpty {
                Text("You can skip this and add people later.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.stacksMutedInk)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var makePage: some View {
        CreateStackPage(
            title: "Make it.",
            subtitle: "Everything looks good. Your Stack is ready to start filling up."
        ) {
            VStack(spacing: 9) {
                Text(trimmedTitle)
                    .font(.system(size: 42, weight: .semibold))
                    .tracking(-1.1)
                    .foregroundStyle(Color.stacksInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(viewModel.createWishlistMode ? "Wishlist" : "Inspo Stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)

                Text(viewModel.createVisibility == .publicDiscover
                     ? "On your public profile"
                     : viewModel.createVisibility == .publicLink
                     ? "Anyone with the link"
                     : "Only you and your Collab")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.stacksMutedInk)

                if !inviteRecipients.isEmpty {
                    Text("\(inviteRecipients.count) Collab invite\(inviteRecipients.count == 1 ? "" : "s")")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.stacksMutedInk)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var sheetControls: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                sheetControlContent
            }
        } else {
            sheetControlContent
        }
        #else
        sheetControlContent
        #endif
    }

    private var sheetControlContent: some View {
        HStack(spacing: 12) {
            if step != .name {
                CreateStackGlassActionButton(title: "Back") {
                    moveBackward()
                }
            }

            CreateStackGlassActionButton(
                title: step == .make ? "Make Stack" : "Next",
                prominent: true,
                isEnabled: !trimmedTitle.isEmpty
            ) {
                if step == .make {
                    Task { await createStack() }
                } else {
                    moveForward()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func moveForward() {
        guard !trimmedTitle.isEmpty else {
            step = .name
            isTitleFocused = true
            return
        }
        guard let nextStep = CreateStackStep(rawValue: step.rawValue + 1) else { return }
        isTitleFocused = false
        services.haptics.impact(.light)
        withAnimation(.snappy) {
            step = nextStep
        }
    }

    private func moveBackward() {
        guard let previousStep = CreateStackStep(rawValue: step.rawValue - 1) else { return }
        services.haptics.impact(.light)
        withAnimation(.snappy) {
            step = previousStep
        }
    }

    private func createStack() async {
        guard pro.isPro || inviteRecipients.count <= StacksPro.freeCollaboratorLimit else {
            pro.present(.collaboratorLimit)
            return
        }
        guard let stack = await viewModel.createStack(services: services, user: user) else { return }
        guard !inviteRecipients.isEmpty else {
            dismiss()
            onCreated(stack)
            return
        }

        var collabStack = stack
        collabStack.collaborationEnabled = true
        pendingCreatedStack = collabStack
        var messages: [StackContactInviteMessage] = []
        do {
            // Invite creation is intentionally blocked server-side until the
            // owner turns Collab on. Do that first, then create a unique,
            // one-use link for every selected contact.
            try await services.collaboration.setCollaborationEnabled(stackID: stack.id, enabled: true)
            for recipient in inviteRecipients {
                let invite = try await services.collaboration.createInvite(to: collabStack, permission: .edit)
                guard let link = invite.deepLink else { throw AppError.invalidURL }
                messages.append(
                    StackContactInviteMessage(
                        recipient: recipient,
                        body: "Join my Collab “\(collabStack.displayTitle)” in Stacks: \(link.absoluteString)"
                    )
                )
            }
            queuedInviteMessages = messages
            presentNextInviteOrFinish()
            services.haptics.notification(.success)
        } catch {
            inviteError = error.localizedDescription
            services.haptics.notification(.error)
        }
    }

    private func finishCreatedStack() {
        guard let stack = pendingCreatedStack else { return }
        pendingCreatedStack = nil
        activeInviteMessage = nil
        queuedInviteMessages = []
        dismiss()
        onCreated(stack)
    }

    private func presentNextInviteOrFinish() {
        guard activeInviteMessage == nil else { return }
        guard !queuedInviteMessages.isEmpty else {
            finishCreatedStack()
            return
        }
        activeInviteMessage = queuedInviteMessages.removeFirst()
    }
}

private struct CreateStackGlassActionButton: View {
    let title: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                button
                    .buttonStyle(.glassProminent)
                    .tint(Color.stacksInk)
            } else {
                button
                    .buttonStyle(.glass)
            }
        } else {
            fallbackButton
        }
        #else
        fallbackButton
        #endif
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(Capsule())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var fallbackButton: some View {
        button
            .buttonStyle(.plain)
            .foregroundStyle(prominent ? Color.white : Color.stacksInk)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(prominent ? Color.stacksInk.opacity(0.82) : Color.white.opacity(0.08))
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(prominent ? 0.28 : 0.64), lineWidth: 1)
            }
    }
}

private struct CreateStackPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 20)

                    VStack(spacing: 10) {
                        Text(title)
                            .font(.stacksMasthead(size: 42))
                            .tracking(-1.5)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.stacksMutedInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 520)

                    content()

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct ShimmeringNewStackPrompt: View {
    let text: String
    @State private var shimmerMovesRight = false

    var body: some View {
        Text(text)
            .font(.stacksMasthead(size: 44))
            .tracking(-1.8)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.stacksInk.opacity(shimmerMovesRight ? 0.18 : 0.38),
                        Color.stacksInk.opacity(shimmerMovesRight ? 0.52 : 0.20),
                        Color.stacksInk.opacity(shimmerMovesRight ? 0.18 : 0.38)
                    ],
                    startPoint: shimmerMovesRight ? .leading : .trailing,
                    endPoint: shimmerMovesRight ? .trailing : .leading
                )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                    shimmerMovesRight = true
                }
            }
    }
}

private struct CreateStackChoiceCard: View {
    let title: String
    let detail: String
    let symbol: String?
    var centersContent = false
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.stacksInk)
                        .frame(width: 42, height: 42)
                        .background(isSelected ? Color.stacksInk : Color.stacksInk.opacity(0.07), in: Circle())
                }

                VStack(alignment: centersContent ? .center : .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.stacksMutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(centersContent ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: centersContent ? .center : .leading)

                if !centersContent {
                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.stacksInk : Color.stacksInk.opacity(0.22))
                }
            }
            .foregroundStyle(Color.stacksInk)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.stacksInk.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .stacksGlass(cornerRadius: 22, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isSelected ? Color.stacksInk.opacity(0.28) : Color.white.opacity(0.68),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

struct StackInviteContactPicker: UIViewControllerRepresentable {
    let onSelect: ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: ([String]) -> Void

        init(onSelect: @escaping ([String]) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let recipients = contacts
                .compactMap { $0.phoneNumbers.first?.value.stringValue }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            onSelect(Array(Set(recipients)).sorted())
        }
    }
}

struct StackContactInviteMessage: Identifiable {
    let id = UUID()
    let recipient: String
    let body: String
}

struct StackInviteMessageSheet: UIViewControllerRepresentable {
    let message: StackContactInviteMessage
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard MFMessageComposeViewController.canSendText() else {
            let controller = UIActivityViewController(activityItems: [message.body], applicationActivities: nil)
            controller.completionWithItemsHandler = { _, _, _, _ in
                Task { @MainActor in
                    context.coordinator.onComplete()
                }
            }
            return controller
        }

        let composer = MFMessageComposeViewController()
        composer.recipients = [message.recipient]
        composer.body = message.body
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, @MainActor MFMessageComposeViewControllerDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onComplete()
        }
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

private struct HomeLibrarySectionHeading: View {
    let title: String
    var isExpanded: Bool?
    var action: (() -> Void)?

    init(title: String, isExpanded: Bool? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.isExpanded = isExpanded
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    label
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded == true ? "Collapse" : "Expand") \(title)")
            } else {
                label
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var label: some View {
        HStack(spacing: 7) {
            Text(title)

            if let isExpanded {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 15, weight: .regular, design: .default))
        .tracking(0.05)
        .foregroundStyle(Color.stacksMutedInk)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        EmptyStackArtwork(width: 68)
                            .position(x: proxy.size.width / 2, y: 50)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let placement = items.count == 1 ? .centered : placements[index]
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
                        let placement = items.count == 1 ? .centered : placements[index]
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

                    Text(stack.items.isEmpty ? "Ready for your first find" : "\(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
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
        .init(x: 0.15, y: 0.62, scale: 0.82, rotation: -12),
        .init(x: 0.38, y: 0.52, scale: 1.08, rotation: 5),
        .init(x: 0.65, y: 0.62, scale: 0.94, rotation: 10),
        .init(x: 0.83, y: 0.48, scale: 0.72, rotation: -7),
        .init(x: 0.27, y: 0.30, scale: 0.70, rotation: 8),
        .init(x: 0.56, y: 0.29, scale: 0.68, rotation: -4),
        .init(x: 0.74, y: 0.25, scale: 0.58, rotation: 8),
        .init(x: 0.46, y: 0.76, scale: 0.62, rotation: -7)
    ]

    var body: some View {
        GeometryReader { proxy in
            let items = Array(stack.items.prefix(placements.count))
            let productSize = min(proxy.size.width * 0.40, 142)
            let previewHeight: CGFloat = 235

            VStack(spacing: 8) {
                ZStack {
                    if items.isEmpty {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.stacksInk.opacity(0.10), lineWidth: 1)
                            .frame(width: proxy.size.width * 0.76, height: 220)

                        EmptyStackArtwork(width: min(proxy.size.width * 0.48, 178))
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let placement = items.count == 1 ? .centered : placements[index]
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
                                y: previewHeight * placement.y
                            )
                            .zIndex(Double(index))
                        }
                    }
                }
                .frame(height: previewHeight)

                VStack(spacing: 4) {
                    Text(stack.title)
                        .font(.system(size: 23, weight: .regular, design: .default))
                        .tracking(-0.55)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text("\(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
                        .font(.stacksText(size: 14, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open recently viewed \(stack.displayTitle)")
        }
        .frame(height: 297)
    }
}

private struct CompactHomeStackCard: View {
    let stack: Stack

    private let placements: [FolderItemPlacement] = [
        .init(x: 0.24, y: 0.52, scale: 0.82, rotation: -9),
        .init(x: 0.52, y: 0.42, scale: 1.00, rotation: 6),
        .init(x: 0.76, y: 0.53, scale: 0.74, rotation: 10),
        .init(x: 0.39, y: 0.66, scale: 0.68, rotation: -5),
        .init(x: 0.67, y: 0.66, scale: 0.62, rotation: 5)
    ]

    var body: some View {
        GeometryReader { proxy in
            let items = Array(stack.items.prefix(placements.count))
            let productSize = min(proxy.size.width * 0.62, 98)
            let previewWidth = proxy.size.width * 0.98
            let previewHeight = proxy.size.width * 0.72

            VStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.60),
                                    Color.white.opacity(0.28),
                                    Color.stacksInk.opacity(0.075)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .stacksGlass(cornerRadius: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.82), Color.stacksInk.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.09), radius: 18, x: 0, y: 10)

                    if items.isEmpty {
                        EmptyStackArtwork(width: min(previewWidth * 0.50, 92))
                            .position(x: previewWidth / 2, y: previewHeight / 2)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let placement = items.count == 1 ? .centered : placements[index]
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
                                x: previewWidth * placement.x,
                                y: previewHeight * placement.y
                            )
                            .zIndex(Double(index))
                        }
                    }
                }
                .frame(width: previewWidth, height: previewHeight)
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(stack.title)
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .tracking(-0.35)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
                        .font(.stacksText(size: 13, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open \(stack.displayTitle)")
        }
        .frame(height: 214)
    }
}

private struct EmptyStackArtwork: View {
    let width: CGFloat

    var body: some View {
        Image("EmptyStackArtwork")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

private struct FolderItemPlacement {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double

    static let centered = FolderItemPlacement(x: 0.5, y: 0.5, scale: 1, rotation: 0)
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

private struct WalletStackCard: View {
    let stack: Stack
    let index: Int

    private let stickerPositions: [CGPoint] = [
        CGPoint(x: 0.18, y: 0.26),
        CGPoint(x: 0.50, y: 0.22),
        CGPoint(x: 0.82, y: 0.26),
        CGPoint(x: 0.21, y: 0.61),
        CGPoint(x: 0.50, y: 0.58),
        CGPoint(x: 0.79, y: 0.61),
        CGPoint(x: 0.50, y: 0.83)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .stacksGlass(cornerRadius: 34, interactive: true)

                ForEach(Array(stack.items.prefix(stickerPositions.count).enumerated()), id: \.element.id) { itemIndex, item in
                    let isSingleItem = stack.items.count == 1
                    let point = isSingleItem ? CGPoint(x: 0.5, y: 0.5) : stickerPositions[itemIndex]
                    let stickerSize: CGFloat = isSingleItem ? 112 : (itemIndex < 3 ? 72 : 84)
                    let safeInset = stickerSize * 0.62 + 10
                    StickerImageView(
                        item: item,
                        size: stickerSize,
                        requiresCutout: true,
                        shadowOpacity: 0.13,
                        shadowRadius: 7,
                        shadowYOffset: 5
                    )
                    .rotationEffect(.degrees(isSingleItem ? 0 : item.placement.rotationDegrees * 0.45))
                    .position(
                        x: min(max(proxy.size.width * point.x, safeInset), proxy.size.width - safeInset),
                        y: min(max(proxy.size.height * point.y, safeInset), proxy.size.height - safeInset)
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(stack.displayTitle)
                        .font(.system(size: 39, weight: .regular, design: .default))
                        .tracking(-1.35)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("\(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .tracking(-0.2)
                    .foregroundStyle(Color.stacksInk.opacity(0.68))
                }
                .padding(.horizontal, 25)
                .padding(.top, 54)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 9)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .frame(height: 272)
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open \(stack.displayTitle), \(stack.items.count) \(stack.items.count == 1 ? "find" : "finds")")
    }
}
