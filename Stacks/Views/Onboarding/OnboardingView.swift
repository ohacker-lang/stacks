import SwiftUI
import UIKit
import CoreMotion
import Contacts
import PhotosUI

private enum OnboardingKeyboard {
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private enum OnboardingStage: Equatable {
    case hero
    case profile
    case stackIt
    case saveAnywhere
    case shareIt
    case friends
    case cameraReveal
    case firstStack
}

private struct OnboardingContactPreview: Identifiable, Equatable {
    let id: String
    let name: String
    let imageData: Data?
}

private enum FirstStackStep: Equatable {
    case purpose
    case name
    case addProduct
}

private enum FirstStackPurpose: Equatable {
    case inspiration
    case wishlist

    var isWishlist: Bool { self == .wishlist }
}

private enum OnboardingSheet: Identifiable {
    case email

    var id: String {
        switch self {
        case .email: "email"
        }
    }
}

private enum FirstItemImportSheet: Identifiable {
    case link
    case photo

    var id: String {
        switch self {
        case .link: "link"
        case .photo: "photo"
        }
    }
}

struct OnboardingView: View {
    @Environment(AppSession.self) private var session
    @Environment(StacksPro.self) private var pro
    @Environment(\.appServices) private var services
    @State private var stage: OnboardingStage = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-preview-onboarding-stickers") {
            .stackIt
        } else if ProcessInfo.processInfo.arguments.contains("-preview-save-anywhere") {
            .saveAnywhere
        } else if ProcessInfo.processInfo.arguments.contains("-preview-first-stack-name")
                    || ProcessInfo.processInfo.arguments.contains("-preview-first-stack-purpose") {
            .firstStack
        } else {
            .hero
        }
        #else
        .hero
        #endif
    }()
    @State private var sheet: OnboardingSheet? = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-preview-email-signin") ? .email : nil
        #else
        nil
        #endif
    }()
    @State private var firstStackTitle = ""
    @State private var heroWord = "things"
    @State private var firstStackStep: FirstStackStep = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-preview-first-stack-name") ? .name : .purpose
        #else
        .purpose
        #endif
    }()
    @State private var firstStackPurpose: FirstStackPurpose = .inspiration
    @State private var firstItemImageData: Data?
    @State private var firstItemLinkPreview: ProductLinkPreview?
    @State private var onboardingProfile: UserProfile?
    @State private var firstItemImportSheet: FirstItemImportSheet?
    @State private var isShowingFirstItemCamera = false
    @State private var isShowingFirstItemPhotoLibrary = false
    @State private var isLoadingFirstItemImport = false
    @State private var firstItemImportError: String?
    @State private var isAuthenticating = false
    @State private var isShowingProPaywall = false
    @State private var contactsAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @State private var contactPreviews: [OnboardingContactPreview] = []
    @State private var isRequestingContacts = false
    @State private var burstMultiplier = 1
    @State private var burstID = 0
    @Namespace private var firstStackCanvasNamespace

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Group {
                switch stage {
                case .hero:
                    hero
                case .profile:
                    OnboardingProfileSetupScreen(
                        profile: onboardingProfile,
                        email: onboardingEmail,
                        onSave: saveOnboardingProfile,
                        onBack: returnToSignIn
                    )
                    .transition(.opacity)
                case .stackIt:
                    PhysicsExplainerScreen(
                        title: "Stack your finds",
                        assets: .stacking,
                        burstMultiplier: burstMultiplier,
                        burstID: burstID,
                        primaryTitle: "Next",
                        onPrimary: advanceToSaveAnywhere,
                        onSkip: completeOnboarding
                    )
                case .saveAnywhere:
                    SaveFromAnywhereVisual(onComplete: advanceToShareIt)
                        .transition(.opacity)
                case .shareIt:
                    PhysicsExplainerScreen(
                        title: "Share your taste",
                        assets: .sharing,
                        burstMultiplier: burstMultiplier,
                        burstID: burstID,
                        primaryTitle: "Next",
                        showsSharedStackPreview: true,
                        onPrimary: advanceToFirstStack,
                        onSkip: completeOnboarding
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .friends:
                    FriendsContactsScreen(
                        contacts: contactPreviews,
                        authorizationStatus: contactsAuthorizationStatus,
                        isRequesting: isRequestingContacts,
                        onAllow: requestContactsAccess,
                        onContinue: completeOnboarding
                    )
                case .cameraReveal:
                    Color.white.ignoresSafeArea()
                case .firstStack:
                    firstStackPrompt
                }
            }
            .frame(maxWidth: 430, maxHeight: 932)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isShowingFirstItemCamera {
                BarcodeProductScannerView(
                    showsMoreWaysHint: true,
                    onProduct: { preview in
                        isShowingFirstItemCamera = false
                        openFirstItemImport(.link, linkPreview: preview)
                    },
                    onPasteLink: {
                        isShowingFirstItemCamera = false
                        openFirstItemImport(.link)
                    },
                    onChooseFromLibrary: {
                        isShowingFirstItemCamera = false
                        isShowingFirstItemPhotoLibrary = true
                    },
                    onCancel: {
                        skipFirstItemImport()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(2)
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .email:
                EmailSignInSheet(onSubmit: { email in
                    let didSend = await session.signInWithEmail(
                        email,
                        acceptingLegalTerms: true
                    )
                    guard didSend else {
                        let message = session.lastError
                        session.lastError = nil
                        return .failed(message)
                    }
                    return session.pendingEmailSignIn ? .codeSent : .signedIn
                }, onVerifyCode: { code, email in
                    await session.verifyEmailCode(code, email: email)
                }, onCancel: returnToHeroAfterCancelledSignIn)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .task(id: onboardingStepName) {
            Analytics.capture("onboarding_step_viewed", ["step": onboardingStepName])
        }
        .fullScreenCover(isPresented: $isShowingProPaywall, onDismiss: finishOnboarding) {
            StacksProPaywall()
        }
        // Sign-in failures land in session.lastError; show them here so a
        // failed Apple, Google or email link never looks like nothing happened.
        .alert(
            "Couldn’t sign in",
            isPresented: Binding(
                get: { sheet == nil && session.lastError != nil },
                set: { if !$0 { session.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.lastError ?? "")
        }
        .overlay {
            if isShowingFirstItemPhotoLibrary {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.10).ignoresSafeArea()

                    ProductPhotoLibraryPicker(
                        onCapture: { data in
                            isShowingFirstItemPhotoLibrary = false
                            openFirstItemImport(.photo, imageData: data)
                        },
                        onCancel: {
                            isShowingFirstItemPhotoLibrary = false
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 620)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 28, y: -8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(4)
            } else if let importSheet = firstItemImportSheet, let onboardingProfile {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.10)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    Group {
                        switch importSheet {
                        case .link:
                            ProductLinkImportSheet(
                                initialPreview: firstItemLinkPreview,
                                user: onboardingProfile,
                                locksDestination: true,
                                initialNewStackTitle: resolvedFirstStackTitle,
                                initialNewStackWishlistMode: firstStackPurpose.isWishlist,
                                onCancel: returnToFirstItemScanner,
                                onSaved: finishFirstItemImport
                            )
                        case .photo:
                            PhotoProductImportSheet(
                                initialImageData: firstItemImageData,
                                navigationTitle: "Review Product",
                                user: onboardingProfile,
                                locksDestination: true,
                                initialNewStackTitle: resolvedFirstStackTitle,
                                initialNewStackWishlistMode: firstStackPurpose.isWishlist,
                                onCancel: returnToFirstItemScanner,
                                onSaved: finishFirstItemImport
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 620)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 28, y: -8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(3)
            } else if isLoadingFirstItemImport {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Preparing your first Stack…")
                            .font(.stacksText(size: 15, weight: .semibold))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(3)
            }
        }
        .alert("Couldn’t start import", isPresented: Binding(
            get: { firstItemImportError != nil },
            set: { if !$0 { firstItemImportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(firstItemImportError ?? "Please try again.")
        }
        .task(id: stage) {
            guard stage == .friends else { return }
            refreshContactAuthorization()
        }
        // An email link, or relaunching mid-onboarding, arrives already signed
        // in; skip the sign-in buttons and go straight to profile setup.
        .onChange(of: session.state, initial: true) { _, state in
            guard case .onboarding = state else { return }
            sheet = nil
            advanceToProfileSetup()
        }
    }

    private var hero: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let heroScale = min(1, max(0.88, proxy.size.height / 852))
            let titleSize = min((isCompact ? 48 : 54) * heroScale, proxy.size.width * 0.142)
            let titleHeight = (isCompact ? 98 : 108) * heroScale
            // Reserve the sign-in area first so the cutout field never sits
            // underneath the buttons on shorter phones.
            let ctaReservedHeight: CGFloat = isCompact ? 242 : 228
            let availableProductHeight = proxy.size.height
                - proxy.safeAreaInsets.top
                - titleHeight
                - ctaReservedHeight
                - 12
            let productHeight = min(max(availableProductHeight, 250), isCompact ? 330 : 410)
            let ctaBottomInset = max(isCompact ? 22 : 26, proxy.safeAreaInsets.bottom + 12)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    (Text("Stack ").font(.stacksOnboardingSerif(size: titleSize))
                        + Text("your").font(.stacksOnboardingSerif(size: titleSize)).italic()
                        + Text("\n\(heroWord)").font(.stacksOnboardingSerif(size: titleSize)))
                        .foregroundStyle(Color.stacksInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .lineSpacing(-8 * heroScale)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: proxy.size.width - 56)
                        .frame(height: titleHeight, alignment: .bottom)
                        .padding(.horizontal, 24)
                        .padding(.top, proxy.safeAreaInsets.top)

                    EditorialOnboardingProductField(assets: OnboardingProductSet.keeping.heroAssets)
                        .frame(height: productHeight)
                        .padding(.top, 8)
                        .allowsHitTesting(false)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(spacing: 14) {
                    PrimaryButton(
                        title: "Continue with Apple",
                        systemImage: "apple.logo",
                        isLoading: isAuthenticating
                    ) {
                        guard !isAuthenticating else { return }
                        services.haptics.impact(.medium)
                        isAuthenticating = true
                        Task {
                            let didSignIn = await session.signInWithApple(
                                acceptingLegalTerms: true
                            )
                            isAuthenticating = false
                            if didSignIn {
                                advanceToProfileSetup()
                            }
                        }
                    }
                    .disabled(isAuthenticating)

                    Button {
                        guard !isAuthenticating else { return }
                        services.haptics.impact(.medium)
                        isAuthenticating = true
                        Task {
                            let didSignIn = await session.signInWithGoogle(
                                acceptingLegalTerms: true
                            )
                            isAuthenticating = false
                            if didSignIn {
                                advanceToProfileSetup()
                            }
                        }
                    } label: {
                        if isAuthenticating {
                            ProgressView()
                                .tint(Color.stacksInk)
                                .frame(height: 58)
                        } else {
                            // Google's iOS-provided, pre-approved light pill.
                            // Keeping the supplied asset intact preserves the
                            // required multicolor G, font, border, and spacing.
                            Image("GoogleSignInButton")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 58)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .disabled(isAuthenticating)

                    Button("Continue with email") {
                        guard !isAuthenticating else { return }
                        services.haptics.impact(.light)
                        sheet = .email
                    }
                    .buttonStyle(.plain)
                    .font(.stacksText(size: 14, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk)
                    .disabled(isAuthenticating)

                    LegalAgreementNotice()
                }
                .padding(.horizontal, isCompact ? 24 : 28)
                .padding(.bottom, ctaBottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
            .task(id: stage) {
                guard stage == .hero else { return }
                await rotateHeroWords()
            }
        }
    }

    private func rotateHeroWords() async {
        let words = ["things", "books", "shoes", "clothes", "furniture", "tech", "homeware", "gifts", "vinyl"]
        var wordIndex = 0

        while !Task.isCancelled {
            let word = words[wordIndex]
            for count in 1...word.count {
                guard !Task.isCancelled else { return }
                heroWord = String(word.prefix(count))
                try? await Task.sleep(nanoseconds: 78_000_000)
            }

            try? await Task.sleep(nanoseconds: 900_000_000)

            if word.count > 1 {
                for count in stride(from: word.count - 1, through: 0, by: -1) {
                    guard !Task.isCancelled else { return }
                    heroWord = String(word.prefix(count))
                    try? await Task.sleep(nanoseconds: 52_000_000)
                }
            }
            wordIndex = (wordIndex + 1) % words.count
        }
    }

    private var firstStackPrompt: some View {
        GeometryReader { proxy in
            switch firstStackStep {
            case .name:
                FirstStackNameQuestion(
                    title: $firstStackTitle,
                    author: onboardingProfile,
                    namespace: firstStackCanvasNamespace,
                    onContinue: { advanceFirstStackStep(to: .addProduct) }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color.white.ignoresSafeArea())
            case .addProduct:
                FirstStackAddProductCoach(
                    title: resolvedFirstStackTitle,
                    author: onboardingProfile,
                    namespace: firstStackCanvasNamespace,
                    onAdd: beginCameraReveal
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color.white.ignoresSafeArea())
            case .purpose:
                ZStack {
                    FirstStackPurposeQuestion { purpose in
                        firstStackPurpose = purpose
                        advanceFirstStackStep(to: .name)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)

                    OnboardingSkipButton(action: completeOnboarding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 8))
                }
                .background(Color.white.ignoresSafeArea())
            }
        }
    }

    private var onboardingStepName: String {
        stage == .firstStack ? "firstStack.\(firstStackStep)" : "\(stage)"
    }

    private var resolvedFirstStackTitle: String {
        let title = firstStackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "First Stack" : title
    }

    private func openFirstItemImport(
        _ importSheet: FirstItemImportSheet,
        imageData: Data? = nil,
        linkPreview: ProductLinkPreview? = nil
    ) {
        if let imageData {
            firstItemImageData = imageData
        }
        firstItemLinkPreview = linkPreview

        isLoadingFirstItemImport = true
        firstItemImportError = nil

        Task {
            defer { isLoadingFirstItemImport = false }
            guard case .onboarding(let authSession) = session.state else {
                firstItemImportError = "Sign in is still finishing. Please try again in a moment."
                return
            }

            do {
                onboardingProfile = try await services.profiles.currentProfile(for: authSession)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    firstItemImportSheet = importSheet
                }
            } catch {
                services.haptics.notification(.error)
                firstItemImportError = "We couldn’t load your profile. Check your connection and try again."
            }
        }
    }

    private func finishFirstItemImport(_ stack: Stack) {
        firstItemImportSheet = nil
        firstItemLinkPreview = nil
        firstItemImageData = nil
        isShowingFirstItemPhotoLibrary = false
        withAnimation(.easeInOut(duration: 0.3)) {
            stage = .friends
        }
    }

    private func returnToFirstItemScanner() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            firstItemImportSheet = nil
            firstItemLinkPreview = nil
            firstItemImageData = nil
            isShowingFirstItemPhotoLibrary = false
            isShowingFirstItemCamera = true
        }
    }

    private func advanceFirstStackStep(to step: FirstStackStep) {
        OnboardingKeyboard.dismiss()
        withAnimation(.easeInOut(duration: 0.24)) {
            firstStackStep = step
        }
    }

    private func completeOnboarding() {
        OnboardingKeyboard.dismiss()
        guard !pro.isPro else {
            finishOnboarding()
            return
        }
        pro.present(.onboarding)
        isShowingProPaywall = true
    }

    private func finishOnboarding() {
        Task { await session.completeOnboarding() }
    }

    private var onboardingEmail: String? {
        guard case .onboarding(let authSession) = session.state else { return nil }
        return authSession.email
    }

    private func advanceToProfileSetup() {
        guard stage == .hero else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            stage = .profile
        }
        loadOnboardingProfileIfNeeded()
    }

    /// Returns a message to show under the form, or nil once saved.
    private func saveOnboardingProfile(displayName: String, username: String, avatarData: Data?) async -> String? {
        guard case .onboarding(let authSession) = session.state else {
            return "Sign in is still finishing. Please try again in a moment."
        }
        var saved: UserProfile
        do {
            var profile: UserProfile
            if let onboardingProfile {
                profile = onboardingProfile
            } else {
                profile = try await services.profiles.currentProfile(for: authSession)
            }
            profile.displayName = displayName
            profile.username = username
            // Name and handle first, so a photo problem never loses them.
            saved = try await services.profiles.updateProfile(profile, avatarData: nil)
            onboardingProfile = saved
        } catch {
            services.haptics.notification(.error)
            let message = error.localizedDescription.lowercased()
            // Postgres reports a taken or waitlist-reserved handle as a unique violation.
            if message.contains("taken") || message.contains("duplicate") || message.contains("unique") || message.contains("reserved") {
                return "@\(username) is taken. Try another username."
            }
            if error is URLError {
                return "You seem to be offline. Check your connection and try again."
            }
            return "We couldn’t save your profile. Please try again."
        }

        if let avatarData {
            do {
                saved = try await services.profiles.updateProfile(saved, avatarData: avatarData)
                AvatarStore.save(avatarData, for: saved.id)
                onboardingProfile = saved
            } catch {
                services.haptics.notification(.error)
                return "Your name and @handle are saved, but the photo didn’t upload. Try another photo, or remove it to continue."
            }
        }

        Analytics.capture("profile_set_up", ["has_photo": avatarData != nil])
        services.haptics.impact(.medium)
        advanceToStackIt()
        return nil
    }

    /// Lets someone who signed in with the wrong account start again.
    private func returnToSignIn() {
        OnboardingKeyboard.dismiss()
        Task {
            await session.signOut()
            onboardingProfile = nil
            withAnimation(.easeInOut(duration: 0.3)) {
                stage = .hero
            }
        }
    }

    private func advanceToStackIt() {
        guard stage == .profile else { return }
        // Keep the stage swap immediate. The physics field is the transition:
        // the same hero products launch into the newly visible Stack canvas.
        burstMultiplier = 1
        burstID += 1
        stage = .stackIt
    }

    private func advanceToSaveAnywhere() {
        guard stage == .stackIt else { return }
        burstMultiplier = min(burstMultiplier * 2, 4)
        burstID += 1
        stage = .saveAnywhere
    }

    private func advanceToShareIt() {
        guard stage == .saveAnywhere else { return }
        stage = .shareIt
    }

    private func advanceToFirstStack() {
        guard stage == .shareIt else { return }
        stage = .firstStack
        loadOnboardingProfileIfNeeded()
    }

    private func beginCameraReveal() {
        guard stage == .firstStack, firstStackStep == .addProduct else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            stage = .cameraReveal
            isShowingFirstItemCamera = true
        }
    }

    private func skipFirstItemImport() {
        guard stage == .cameraReveal else { return }
        services.haptics.impact(.light)
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowingFirstItemCamera = false
            stage = .friends
        }
    }

    private func loadOnboardingProfileIfNeeded() {
        guard onboardingProfile == nil,
              case .onboarding(let authSession) = session.state else { return }

        Task {
            onboardingProfile = try? await services.profiles.currentProfile(for: authSession)
        }
    }

    @MainActor
    private func refreshContactAuthorization() {
        contactsAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        if contactsAuthorizationStatus == .authorized || contactsAuthorizationStatus == .limited {
            loadContactPreviews()
        }
    }

    @MainActor
    private func requestContactsAccess() {
        switch contactsAuthorizationStatus {
        case .authorized, .limited:
            loadContactPreviews()
        case .denied, .restricted:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .notDetermined:
            isRequestingContacts = true
            Task { @MainActor in
                let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
                isRequestingContacts = false
                contactsAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
                if granted {
                    loadContactPreviews()
                    services.haptics.notification(.success)
                }
            }
        @unknown default:
            break
        }
    }

    @MainActor
    private func loadContactPreviews() {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var previews: [OnboardingContactPreview] = []

        try? CNContactStore().enumerateContacts(with: request) { contact, stop in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !name.isEmpty else { return }
            previews.append(
                OnboardingContactPreview(
                    id: contact.identifier,
                    name: name,
                    imageData: contact.thumbnailImageData
                )
            )
            if previews.count == 7 {
                stop.pointee = true
            }
        }
        contactPreviews = previews
    }

    private func returnToHeroAfterCancelledSignIn() {
        if stage != .hero {
            withAnimation(.easeOut(duration: 0.2)) { stage = .hero }
        }
    }
}

/// First step after sign-in: the name, @handle and optional photo people see.
/// New accounts start with a placeholder handle, so this step can't be skipped.
private struct OnboardingProfileSetupScreen: View {
    let profile: UserProfile?
    let email: String?
    let onSave: (String, String, Data?) async -> String?
    let onBack: () -> Void

    @State private var displayName = ""
    @State private var username = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var hasPrefilled = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case username
    }

    static let usernameLength = 3...30

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The handle as saved: lowercase, without a leading @ or stray spaces.
    private var normalizedUsername: String {
        var value = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        return value
    }

    private var hasInvalidCharacters: Bool {
        !normalizedUsername.allSatisfy { Self.allowedUsernameCharacters.contains($0) }
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty
            && Self.usernameLength.contains(normalizedUsername.count)
            && !hasInvalidCharacters
            && !isSaving
    }

    private var showsProblem: Bool {
        errorMessage != nil || hasInvalidCharacters || normalizedUsername.count > Self.usernameLength.upperBound
    }

    private var usernameHint: String {
        if normalizedUsername.isEmpty {
            "Letters, numbers and underscores"
        } else if hasInvalidCharacters {
            "Only letters, numbers and underscores"
        } else if normalizedUsername.count < Self.usernameLength.lowerBound {
            "At least 3 characters"
        } else if normalizedUsername.count > Self.usernameLength.upperBound {
            "30 characters at most"
        } else {
            "stacks.spot/\(normalizedUsername)"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    FirstStackQuestion(
                        title: "Make it yours",
                        detail: "This is how friends find you\nand see your Stacks."
                    ) {
                        VStack(spacing: 14) {
                            photoPicker

                            if avatarData != nil {
                                Button("Remove photo") {
                                    photoItem = nil
                                    avatarData = nil
                                    errorMessage = nil
                                }
                                .font(.stacksText(size: 13, weight: .regular))
                                .foregroundStyle(Color.stacksMutedInk)
                                .disabled(isSaving)
                            }

                            Color.clear.frame(height: 4)

                            OnboardingTextField(
                                placeholder: "Your name",
                                text: $displayName,
                                contentType: .name,
                                autocapitalization: .words
                            )
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .username }
                            .accessibilityLabel("Display name")

                            usernameField

                            Text(errorMessage ?? usernameHint)
                                .font(.stacksText(size: 14, weight: showsProblem ? .semibold : .regular))
                                .foregroundStyle(showsProblem ? Color.red : Color.stacksMutedInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .accessibilityIdentifier("profile-setup-hint")
                        }
                    } primary: {
                        PrimaryButton(title: "Continue", systemImage: "arrow.right", isLoading: isSaving, action: save)
                            .disabled(!canContinue)
                            .opacity(canContinue || isSaving ? 1 : 0.42)
                            .accessibilityIdentifier("profile-setup-continue")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.safeAreaInsets.top + 36)
                    .padding(.bottom, 24)
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.white.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.stacksInk)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .padding(.leading, 16)
                .padding(.top, proxy.safeAreaInsets.top + 4)
                .accessibilityLabel("Back to sign in")
                .accessibilityHint("Signs out so you can use a different account")
                .accessibilityIdentifier("profile-setup-back")
            }
        }
        .onChange(of: profile, initial: true) { _, profile in
            prefill(from: profile)
        }
        .onChange(of: username) { _, _ in
            errorMessage = nil
        }
        .task(id: photoItem) {
            guard let photoItem,
                  let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            avatarData = data
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let avatarData, let image = UIImage(data: avatarData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 38, weight: .medium))
                                .foregroundStyle(Color.stacksMutedInk)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.stacksInk.opacity(0.06))
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())

                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.stacksInk, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }

                Text(avatarData == nil ? "Add a photo (optional)" : "Change photo")
                    .font(.stacksText(size: 14, weight: .semibold))
                    .foregroundStyle(Color.stacksMutedInk)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(avatarData == nil ? "Add a profile photo" : "Change profile photo")
    }

    private var usernameField: some View {
        HStack(spacing: 2) {
            Text("@")
                .font(.stacksText(size: 17, weight: .semibold))
                .foregroundStyle(Color.stacksMutedInk)
            TextField("username", text: $username)
                .font(.stacksText(size: 17, weight: .regular))
                .foregroundStyle(Color.stacksInk)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: .username)
                .submitLabel(.done)
                .onSubmit { if canContinue { save() } }
                .accessibilityLabel("Username")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(showsProblem ? Color.red.opacity(0.6) : Color.stacksInk.opacity(0.08), lineWidth: 1)
        }
    }

    /// Fills in what sign-in already told us, but never the placeholder handle
    /// or a name that is just the email address's first half.
    private func prefill(from profile: UserProfile?) {
        guard !hasPrefilled, let profile else { return }
        hasPrefilled = true
        let emailPrefix = email?.split(separator: "@").first.map { String($0).lowercased() }
        if displayName.isEmpty, profile.displayName.lowercased() != emailPrefix, profile.displayName != "New member" {
            displayName = profile.displayName
        }
        if username.isEmpty, !profile.username.hasPrefix("stacker_"), profile.username.lowercased() != emailPrefix {
            username = profile.username.lowercased()
        }
        if avatarData == nil {
            avatarData = AvatarStore.data(for: profile.id)
        }
    }

    /// Matches the database rule for handles.
    static let allowedUsernameCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789_")

    private func save() {
        guard canContinue else { return }
        OnboardingKeyboard.dismiss()
        isSaving = true
        errorMessage = nil
        let name = String(trimmedName.prefix(80))
        let handle = normalizedUsername
        let photo = photoItem == nil ? nil : avatarData
        Task {
            errorMessage = await onSave(name, handle, photo)
            isSaving = false
        }
    }
}

private struct LegalAgreementNotice: View {
    var body: some View {
        Text("By continuing, you agree to the [Terms of Service](https://stacks.spot/terms) and acknowledge the [Privacy Policy](https://stacks.spot/privacy).")
            .font(.stacksText(size: 10, weight: .regular))
            .foregroundStyle(Color.stacksMutedInk)
            .tint(Color.stacksInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

private struct FriendsContactsScreen: View {
    let contacts: [OnboardingContactPreview]
    let authorizationStatus: CNAuthorizationStatus
    let isRequesting: Bool
    let onAllow: () -> Void
    let onContinue: () -> Void

    private var hasAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    private var primaryTitle: String {
        if hasAccess { return "Continue" }
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return "Open Settings"
        }
        return "Allow Contacts"
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("Stacking is better\nwith friends")
                        .font(.stacksOnboardingSerif(size: isCompact ? 40 : 46))
                        .foregroundStyle(Color.stacksInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(hasAccess
                         ? "Your contacts are ready. Find friends, share Stacks, and make Collabs together."
                         : "Find friends already on Stacks and make Collabs effortless.")
                        .font(.stacksText(size: 16, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(.top, isCompact ? 2 : 8)

                FriendsContactField(contacts: contacts)
                    .frame(height: isCompact ? 276 : 342)
                    .padding(.top, isCompact ? 8 : 20)

                Spacer(minLength: 16)

                VStack(spacing: 14) {
                    PrimaryButton(
                        title: primaryTitle,
                        systemImage: hasAccess ? "arrow.right" : "person.2.fill",
                        isLoading: isRequesting,
                        action: hasAccess ? onContinue : onAllow
                    )
                    .disabled(isRequesting)

                    if !hasAccess {
                        Button("Not now", action: onContinue)
                            .font(.stacksText(size: 15, weight: .semibold))
                            .foregroundStyle(Color.stacksMutedInk)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(26, proxy.safeAreaInsets.bottom + 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
        }
    }
}

private struct FriendsContactField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let contacts: [OnboardingContactPreview]

    private static let placeholders = [
        OnboardingContactPreview(id: "maya", name: "Maya", imageData: nil),
        OnboardingContactPreview(id: "ethan", name: "Ethan", imageData: nil),
        OnboardingContactPreview(id: "lucas", name: "Lucas", imageData: nil),
        OnboardingContactPreview(id: "viola", name: "Viola", imageData: nil),
        OnboardingContactPreview(id: "sienna", name: "Sienna", imageData: nil),
        OnboardingContactPreview(id: "noah", name: "Noah", imageData: nil)
    ]

    private let placements: [(CGFloat, CGFloat, Double)] = [
        (-0.03, 0.72, -8), (0.16, 0.59, -5), (0.36, 0.46, -2),
        (0.57, 0.35, 3), (0.77, 0.23, 6), (0.98, 0.13, 8)
    ]

    private var visibleContacts: [OnboardingContactPreview] {
        let source = contacts.isEmpty ? Self.placeholders : contacts
        return Array(source.prefix(placements.count))
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    ForEach(Array(visibleContacts.enumerated()), id: \.element.id) { index, contact in
                        let placement = placements[index]
                        let phase = elapsed * 0.62 + Double(index) * 0.72
                        let driftX: CGFloat = reduceMotion ? 0 : CGFloat(cos(phase)) * 10
                        let driftY: CGFloat = reduceMotion ? 0 : CGFloat(sin(phase)) * 5

                        FriendPortrait(contact: contact, showsName: index == 2)
                            .rotationEffect(.degrees(placement.2 + (reduceMotion ? 0 : sin(phase) * 1.4)))
                            .position(
                                x: proxy.size.width * placement.0 + driftX,
                                y: proxy.size.height * placement.1 + driftY
                            )
                            .zIndex(Double(index + 1))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Friends from your contacts")
    }
}

private struct FriendPortrait: View {
    let contact: OnboardingContactPreview
    let showsName: Bool

    private var initials: String {
        contact.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    private var tint: Color {
        let seed = contact.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let colors: [Color] = [.orange, .blue, .pink, .mint, .purple, .indigo]
        return colors[seed % colors.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(tint.gradient)

            if let data = contact.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 92, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .stroke(Color.white, lineWidth: 4)
        }
        .shadow(color: .black.opacity(0.17), radius: 10, y: 6)
        .overlay(alignment: .top) {
            if showsName {
                Text(contact.name)
                    .font(.stacksText(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.stacksInk, in: Capsule())
                    .offset(y: -15)
            }
        }
    }
}

private struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.stacksText(size: 17, weight: .regular))
            .foregroundStyle(Color.stacksInk)
            .textInputAutocapitalization(autocapitalization)
            .keyboardType(keyboardType)
            .textContentType(contentType)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.stacksInk.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct FirstStackQuestion<Content: View, Primary: View>: View {
    let title: String
    let detail: String
    private let content: Content
    private let primary: Primary

    init(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder primary: () -> Primary
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
        self.primary = primary()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.stacksOnboardingSerif(size: 46))
                .foregroundStyle(Color.stacksInk)
                .multilineTextAlignment(.center)
                .lineSpacing(-6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Text(detail)
                .font(.stacksText(size: 17, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            content
                .padding(.top, 34)

            primary
                .padding(.top, 28)
        }
    }
}

private struct FirstStackPurposeQuestion: View {
    let onSelect: (FirstStackPurpose) -> Void

    @State private var burstAssets: [OnboardingBurstAsset] = {
        let earlierCutouts = OnboardingProductSet.keeping.burstAssets
            + OnboardingProductSet.stacking.burstAssets
            + OnboardingProductSet.sharing.burstAssets
        return Array(earlierCutouts.shuffled().prefix(10))
    }()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MagneticStackingField(assets: burstAssets)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Text("Stack a \(Text("wishlist").italic()), or just for \(Text("inspo").italic())")
                        .font(.stacksOnboardingSerif(size: proxy.size.height < 650 ? 36 : 41))
                        .foregroundStyle(Color.stacksInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .lineSpacing(-5)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 390)
                        .padding(.horizontal, 28)

                    Text("Where do you want to start?")
                        .font(.stacksText(size: 17, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)

                    purposeChoices
                        .padding(.horizontal, 24)
                        .padding(.top, 26)

                    Spacer(minLength: 0)
                }
                .padding(.top, max(72, proxy.safeAreaInsets.top + 58))
            }
        }
    }

    @ViewBuilder
    private var purposeChoices: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                choices
            }
        } else {
            choices
        }
    }

    private var choices: some View {
        VStack(spacing: 12) {
            purposeButton(
                title: "Inspo",
                detail: "A private place for things you love.",
                purpose: .inspiration
            )
            purposeButton(
                title: "Wishlist",
                detail: "Share a link so people can claim gifts together.",
                purpose: .wishlist
            )
        }
    }

    private func purposeButton(
        title: String,
        detail: String,
        purpose: FirstStackPurpose
    ) -> some View {
        Button {
            onSelect(purpose)
        } label: {
            ZStack {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.stacksText(size: 19, weight: .semibold))
                    Text(detail)
                        .font(.stacksText(size: 14, weight: .regular))
                        .foregroundStyle(Color.stacksMutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.stacksInk.opacity(0.68))
                }
            }
            .foregroundStyle(Color.stacksInk)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .stacksGlass(cornerRadius: 24, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FirstStackNameQuestion: View {
    @Binding var title: String
    let author: UserProfile?
    let namespace: Namespace.ID
    let onContinue: () -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                EmptyStackNameCanvas(
                    title: $title,
                    author: author,
                    namespace: namespace,
                    titleTopInset: proxy.safeAreaInsets.top + 56
                )

                PrimaryButton(title: "Next", systemImage: "arrow.right") {
                    OnboardingKeyboard.dismiss()
                    onContinue()
                }
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.42 : 1)
                .accessibilityIdentifier("first-stack-next")
                .padding(.horizontal, 24)
                .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 8))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Riding up with the keyboard put Next on top of the title being
        // typed. Keep the page still; the keyboard's Done key reveals Next.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct FirstStackAddProductCoach: View {
    let title: String
    let author: UserProfile?
    let namespace: Namespace.ID
    let onAdd: () -> Void
    @State private var isPulsing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                EmptyStackNameCanvas(
                    title: .constant(title),
                    author: author,
                    namespace: namespace,
                    titleTopInset: proxy.safeAreaInsets.top + 56
                )
                .allowsHitTesting(false)

                OnboardingStackChrome(canAdd: true, onAdd: onAdd)
                    .padding(.horizontal, 17)
                    .padding(.top, proxy.safeAreaInsets.top + 3)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("Tap + to add your first product")
                        .font(.stacksText(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.stacksInk, in: Capsule())

                    Image(systemName: "arrow.up")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(Color.stacksInk)
                        .rotationEffect(.degrees(13))
                        .padding(.trailing, 58)
                }
                .padding(.top, proxy.safeAreaInsets.top + 50)
                .padding(.trailing, 17)
                .scaleEffect(isPulsing ? 1.025 : 0.98, anchor: .topTrailing)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tap the plus button to add your first product")
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

private struct OnboardingStackChrome: View {
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 14) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .foregroundStyle(Color.stacksInk.opacity(canAdd ? 1 : 0.25))
                .accessibilityLabel("Add your first item")

                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Color.stacksInk.opacity(0.25))
            }
            .frame(height: 34)
        }
    }
}

private struct EmptyStackNameCanvas: View {
    @Binding var title: String
    /// The signed-in person, shown as the Stack's byline once their profile loads.
    let author: UserProfile?
    let namespace: Namespace.ID
    let titleTopInset: CGFloat

    private let blobs: [StackPlaceholderBlob] = [
        .featured,
        StackPlaceholderBlob(id: "cap", imageName: "StickerBlueCap", x: 0.76, y: 0.18, width: 118, height: 82, rotation: 6),
        StackPlaceholderBlob(id: "shorts", imageName: "OnboardingShorts", x: 0.70, y: 0.46, width: 130, height: 96, rotation: -4),
        StackPlaceholderBlob(id: "wallet", imageName: "OnboardingWallet", x: 0.22, y: 0.44, width: 98, height: 76, rotation: -8),
        StackPlaceholderBlob(id: "watch", imageName: "OnboardingWatch", x: 0.44, y: 0.68, width: 80, height: 116, rotation: 5),
        StackPlaceholderBlob(id: "tote", imageName: "OnboardingTote", x: 0.76, y: 0.73, width: 118, height: 136, rotation: -5)
    ]

    private var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 390
            let displayTitle = hasTitle ? title : "Tap here to name your stack"
            let titleFontSize = OnboardingEditableTitleMetrics.resolvedFontSize(
                for: displayTitle,
                availableWidth: proxy.size.width - 40
            )
            let titleHeight = max(64, titleFontSize * 1.2)
            let productsTop = titleTopInset + titleHeight + 47
            let productsHeight = max(1, proxy.size.height - productsTop - 102)

            ZStack(alignment: .top) {
                Color.white
                    .onTapGesture { OnboardingKeyboard.dismiss() }

                GeometryReader { area in
                    ZStack {
                        ForEach(blobs) { blob in
                            PlaceholderProductBlob(blob: blob)
                                .matchedGeometryEffect(id: blob.id, in: namespace)
                                .frame(width: blob.width * scale, height: blob.height * scale)
                                .rotationEffect(.degrees(blob.rotation))
                                .position(
                                    x: area.size.width * blob.x,
                                    y: area.size.height * blob.y
                                )
                        }
                    }
                }
                .frame(height: productsHeight)
                .clipped()
                .padding(.top, productsTop)

                // Keep the placeholder mounted after typing begins. Removing it
                // changes the ZStack's child identity and causes UIKit to discard
                // the active text field after the first character.
                ShimmeringStackTitle(text: "Tap here to name your stack", fontSize: titleFontSize)
                    .opacity(hasTitle ? 0 : 1)
                    .frame(width: max(1, proxy.size.width - 40), height: titleHeight, alignment: .leading)
                    .padding(.top, titleTopInset)
                    .allowsHitTesting(false)

                OnboardingStackTitleField(
                    text: $title,
                    fontSize: titleFontSize,
                    isVisible: hasTitle
                )
                    .frame(width: max(1, proxy.size.width - 40), height: titleHeight, alignment: .leading)
                    .padding(.top, titleTopInset)
                    .accessibilityLabel("Tap here to name your stack")

                VStack(spacing: 8) {
                    HStack(spacing: 7) {
                        if let author {
                            AvatarView(profile: author, size: 22)
                        } else {
                            Circle()
                                .fill(Color.stacksInk.opacity(0.12))
                                .frame(width: 22, height: 22)
                        }

                        Text(author?.displayName ?? "You")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(Color.stacksInk.opacity(0.78))

                        Spacer()

                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Last update")
                            Text("Today")
                        }
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color.stacksMutedInk)
                    }

                    Divider()
                        .overlay(Color.stacksInk.opacity(0.09))
                }
                .padding(.horizontal, 20)
                .padding(.top, titleTopInset + titleHeight + 4)
            }
            .clipShape(Rectangle())
        }
    }
}

private enum OnboardingEditableTitleMetrics {
    static let maximumFontSize: CGFloat = 49
    static let minimumFontSize = StackTitleTokens.stackTitleMinimumFontSize
    static let trackingRatio = StackTitleTokens.stackTitleTrackingRatio

    static func resolvedFontSize(for text: String, availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return maximumFontSize }

        for size in stride(from: maximumFontSize, through: minimumFontSize, by: -0.25) {
            let width = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: .bold),
                    .kern: size * trackingRatio
                ]
            ).size().width

            if width <= availableWidth {
                return size
            }
        }

        return minimumFontSize
    }
}

private struct OnboardingStackTitleField: View {
    @Binding var text: String
    let fontSize: CGFloat
    let isVisible: Bool

    var body: some View {
        ExactCaseStackTitleField(
            text: $text,
            fontSize: fontSize,
            textColor: isVisible ? UIColor(Color.stacksInk) : .clear
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Tap here to name your stack")
    }
}

/// UIKit keeps this high-impact title editor stable while its font size changes.
/// It also deliberately leaves the user's casing untouched.
private struct ExactCaseStackTitleField: UIViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let textColor: UIColor

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.adjustsFontSizeToFitWidth = false
        field.textAlignment = .left
        field.autocapitalizationType = .none
        field.autocorrectionType = .yes
        field.spellCheckingType = .yes
        field.keyboardType = .default
        field.returnKeyType = .done
        field.textContentType = nil
        field.clearButtonMode = .never
        field.textAlignment = .left
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.tintColor = UIColor(Color.stacksInk)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)

        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        // Only write the binding back into the field when it changed from
        // outside (for example a reset). Rewriting it on every update threw
        // away characters that autocorrect, predictive text or fast typing
        // had inserted since the last sync, so "Fall fits" saved as "Fall".
        if text != context.coordinator.lastSyncedText {
            context.coordinator.lastSyncedText = text
            if field.text != text { field.text = text }
        }
        // Re-applying text attributes while typing also disturbs editing, so
        // only do it when the size or colour actually changes.
        let style = Style(fontSize: fontSize, textColor: textColor)
        guard context.coordinator.appliedStyle != style else { return }
        context.coordinator.appliedStyle = style
        field.defaultTextAttributes = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .kern: fontSize * OnboardingEditableTitleMetrics.trackingRatio,
            .foregroundColor: textColor
        ]
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    struct Style: Equatable {
        let fontSize: CGFloat
        let textColor: UIColor
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        var lastSyncedText = ""
        var appliedStyle: Style?

        init(text: Binding<String>) { _text = text }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        /// Fires after UIKit has applied every kind of edit, including
        /// autocorrect and predictive text, so the binding always matches.
        @objc func editingChanged(_ textField: UITextField) {
            let value = textField.text ?? ""
            lastSyncedText = value
            text = value
        }
    }
}

private struct StackPlaceholderBlob: Identifiable {
    static let featured = StackPlaceholderBlob(
        id: "featured-blob",
        imageName: "OnboardingTShirt",
        x: 0.27,
        y: 0.20,
        width: 142,
        height: 136,
        rotation: -6
    )

    let id: String
    let imageName: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
}

private struct PlaceholderProductBlob: View {
    let blob: StackPlaceholderBlob

    var body: some View {
        Image(blob.imageName)
            .resizable()
            .scaledToFit()
            .saturation(0)
            .colorMultiply(Color(white: 0.72))
            .contrast(0.52)
            .brightness(0.26)
            .opacity(0.66)
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 7)
            .shadow(color: .white.opacity(0.88), radius: 2, x: 0, y: 0)
    }
}

private struct ShimmeringStackTitle: View {
    let text: String
    let fontSize: CGFloat
    @State private var isShimmering = false

    var body: some View {
        Text(text)
            .font(.stacksMasthead(size: fontSize))
            .tracking(fontSize * OnboardingEditableTitleMetrics.trackingRatio)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.stacksInk.opacity(isShimmering ? 0.18 : 0.34),
                        Color.stacksInk.opacity(isShimmering ? 0.46 : 0.20),
                        Color.stacksInk.opacity(isShimmering ? 0.18 : 0.34)
                    ],
                    startPoint: isShimmering ? .leading : .trailing,
                    endPoint: isShimmering ? .trailing : .leading
                )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                    isShimmering = true
                }
            }
    }
}

private struct FirstStackOrbCanvas: View {
    @Binding var title: String
    let allowsEditing: Bool
    var isZoomed = false

    private let standardOrbs: [StackOrb] = [
        StackOrb(x: 0.16, y: 0.28, size: 88, color: Color(red: 0.20, green: 0.45, blue: 0.79)),
        StackOrb(x: 0.71, y: 0.20, size: 66, color: Color(red: 0.92, green: 0.64, blue: 0.18)),
        StackOrb(x: 0.77, y: 0.51, size: 112, color: Color(red: 0.48, green: 0.33, blue: 0.72)),
        StackOrb(x: 0.26, y: 0.63, size: 136, color: Color(red: 0.12, green: 0.58, blue: 0.51)),
        StackOrb(x: 0.52, y: 0.78, size: 84, color: Color(red: 0.91, green: 0.36, blue: 0.36)),
        StackOrb(x: 0.92, y: 0.84, size: 58, color: Color(red: 0.25, green: 0.25, blue: 0.29))
    ]

    private let zoomedOrbs: [StackOrb] = [
        StackOrb(x: -0.06, y: 0.44, size: 210, color: Color(red: 0.12, green: 0.58, blue: 0.51)),
        StackOrb(x: 0.52, y: 0.20, size: 176, color: Color(red: 0.20, green: 0.45, blue: 0.79)),
        StackOrb(x: 0.96, y: 0.58, size: 198, color: Color(red: 0.48, green: 0.33, blue: 0.72)),
        StackOrb(x: 0.40, y: 1.02, size: 168, color: Color(red: 0.91, green: 0.36, blue: 0.36))
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 360
            let orbs = isZoomed ? zoomedOrbs : standardOrbs

            ZStack {
                ForEach(orbs) { orb in
                    ShiningOrb(color: orb.color)
                        .frame(width: orb.size * scale, height: orb.size * scale)
                        .position(
                            x: proxy.size.width * orb.x,
                            y: proxy.size.height * orb.y
                        )
                }

                if allowsEditing {
                        TextField("Tap here to name your stack", text: $title)
                        .font(.stacksMasthead(size: 44))
                        .tracking(-1.8)
                        .foregroundStyle(Color.stacksInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .position(x: proxy.size.width / 2, y: 42)
                        .accessibilityLabel("Stack name")
                }
            }
            .clipShape(Rectangle())
        }
    }
}

private struct StackOrb: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
}

private struct ShiningOrb: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white, color.opacity(0.88), color.opacity(0.24)],
                    center: UnitPoint(x: 0.30, y: 0.24),
                    startRadius: 1,
                    endRadius: 90
                )
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.78), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: 20, height: 12)
                    .blur(radius: 3)
                    .padding(.top, 17)
                    .padding(.leading, 20)
            }
            .shadow(color: color.opacity(0.24), radius: 18, x: 0, y: 10)
            .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 3)
    }
}

private struct FirstStackSourceRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.stacksText(size: 17, weight: .medium))
            .foregroundStyle(Color.stacksInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.stacksInk.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct OnboardingCameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.92) else {
                onCancel()
                return
            }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct EditorialOnboardingProductField: View {
    let assets: [OnboardingHeroAsset]

    private let placements: [ProductPlacement] = [
        ProductPlacement(asset: .ramblinCap, x: 0.17, y: 0.15, width: 118, rotation: -7),
        ProductPlacement(asset: .orangeLamp, x: 0.50, y: 0.12, width: 116, rotation: 0),
        ProductPlacement(asset: .beanieSlateBird, x: 0.82, y: 0.16, width: 120, rotation: 5),
        ProductPlacement(asset: .beanieBurgundyBird, x: 0.20, y: 0.40, width: 138, rotation: -5),
        ProductPlacement(asset: .redBosHat, x: 0.51, y: 0.38, width: 112, rotation: 1),
        ProductPlacement(asset: .blueWindbreaker, x: 0.80, y: 0.40, width: 146, rotation: 4),
        ProductPlacement(asset: .memorialShirt, x: 0.18, y: 0.67, width: 154, rotation: 4),
        ProductPlacement(asset: .coffeeMachine, x: 0.53, y: 0.62, width: 100, rotation: -4),
        ProductPlacement(asset: .duffelBag, x: 0.78, y: 0.67, width: 138, rotation: -3),
        ProductPlacement(asset: .sambaShoe, x: 0.60, y: 0.77, width: 132, rotation: 4)
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, max(0.82, proxy.size.width / 390))

            ZStack {
                ForEach(placements.filter { assets.contains($0.asset) }) { placement in
                    ProductCutout(asset: placement.asset)
                        .frame(width: placement.width * scale, height: placement.width * scale)
                        .rotationEffect(.degrees(placement.rotation))
                        .position(
                            x: proxy.size.width * placement.x,
                            y: proxy.size.height * placement.y
                        )
                        .zIndex(placement.asset == .coffeeMachine || placement.asset == .orangeChair ? 2 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProductPlacement: Identifiable {
    let asset: OnboardingHeroAsset
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let rotation: Double

    var id: OnboardingHeroAsset { asset }
}

private struct ProductCutout: View {
    let asset: OnboardingHeroAsset

    var body: some View {
        Image(asset.rawValue)
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.13), radius: 5, x: 0, y: 4)
            .shadow(color: .white.opacity(0.9), radius: 2, x: 0, y: 0)
            .accessibilityLabel(asset.accessibilityLabel)
            .accessibilityHidden(true)
    }
}

private enum OnboardingHeroAsset: String, CaseIterable, Hashable {
    case tShirt = "OnboardingTShirt"
    case shorts = "OnboardingShorts"
    case earrings = "OnboardingEarrings"
    case watch = "OnboardingWatch"
    case wine = "OnboardingWine"
    case wallet = "OnboardingWallet"
    case sneaker = "OnboardingSneaker"
    case sambaShoe = "OnboardingSambaShoe"
    case memorialShirt = "OnboardingMemorialShirt"
    case duffelBag = "OnboardingDuffelBag"
    case redBosHat = "OnboardingRedBosHat"
    case filmCrewCap = "OnboardingFilmCrewCap"
    case adidasShorts = "OnboardingAdidasShorts"
    case keys = "OnboardingKeys"
    case tote = "OnboardingTote"
    case coffeeMachine = "HeroCoffeeMachine"
    case foldingCrate = "HeroFoldingCrate"
    case stripedCup = "HeroStripedCup"
    case orangeLamp = "OnboardingLampOrangeMushroom"
    case mokaPot = "HeroMokaPot"
    case discoBall = "HeroDiscoBall"
    case blueLamp = "HeroBlueLamp"
    case orangeChair = "HeroOrangeChair"
    case blueBlanket = "HeroBlueBlanket"
    case navyCap = "OnboardingNavyCap"
    case ramblinCap = "OnboardingRamblinCap"
    case blueWindbreaker = "OnboardingBlueWindbreaker"
    case greenTee = "OnboardingGreenTee"
    case beanieRustVintage = "BeanieRustVintage"
    case beanieGreenStripe = "BeanieGreenStripe"
    case beanieSlateBird = "BeanieSlateBird"
    case beanieBurgundyBird = "BeanieBurgundyBird"

    var accessibilityLabel: String {
        switch self {
        case .tShirt: "T-shirt"
        case .shorts: "Shorts"
        case .earrings: "Earrings"
        case .watch: "Watch"
        case .wine: "Wine bottle"
        case .wallet: "Leather pouch"
        case .sneaker: "Sneaker"
        case .sambaShoe: "Navy Adidas Samba shoes"
        case .memorialShirt: "Graphic T-shirt"
        case .duffelBag: "Duffel bag"
        case .redBosHat: "Red BOS cap"
        case .filmCrewCap: "Film crew cap"
        case .adidasShorts: "Adidas shorts"
        case .keys: "Keys"
        case .tote: "Canvas tote"
        case .coffeeMachine: "Espresso machine"
        case .foldingCrate: "Green folding crate"
        case .stripedCup: "Striped cup and saucer"
        case .orangeLamp: "Orange mushroom lamp"
        case .mokaPot: "Stovetop coffee maker"
        case .discoBall: "Disco ball"
        case .blueLamp: "Blue table lamp"
        case .orangeChair: "Orange lounge chair"
        case .blueBlanket: "Blue blanket"
        case .navyCap: "Navy embroidered cap"
        case .ramblinCap: "Blue Ramblin cap"
        case .blueWindbreaker: "Blue windbreaker"
        case .greenTee: "Green athletic T-shirt"
        case .beanieRustVintage: "Rust vintage beanie"
        case .beanieGreenStripe: "Green striped beanie"
        case .beanieSlateBird: "Blue bird beanie"
        case .beanieBurgundyBird: "Burgundy bird beanie"
        }
    }
}

private enum OnboardingProductSet {
    case keeping
    case stacking
    case sharing

    var heroAssets: [OnboardingHeroAsset] {
        switch self {
        case .keeping:
            [.ramblinCap, .beanieSlateBird, .orangeLamp, .beanieBurgundyBird, .redBosHat, .blueWindbreaker, .memorialShirt, .coffeeMachine, .duffelBag, .sambaShoe]
        case .stacking:
            [.tShirt, .shorts, .earrings, .watch, .wine, .wallet, .sneaker]
        case .sharing:
            [.tShirt, .shorts, .earrings, .watch, .wine, .wallet, .sneaker, .keys, .tote]
        }
    }

    var burstAssets: [OnboardingBurstAsset] {
        switch self {
        case .stacking:
            OnboardingStickerAsset.allCases.map(OnboardingBurstAsset.sticker)
        case .sharing:
            OnboardingLampAsset.allCases.map(OnboardingBurstAsset.lamp)
        case .keeping:
            heroAssets.map(OnboardingBurstAsset.wardrobe)
        }
    }
}

private enum OnboardingStickerAsset: String, CaseIterable, Hashable {
    case everySecond = "StickerEverySecond"
    case callMe = "StickerCallMe"
    case pocketWatch = "StickerPocketWatch"
    case blueCap = "StickerBlueCap"
    case vinyl = "StickerVinyl"
    case nyApple = "StickerNYApple"
    case eightBall = "StickerEightBall"
    case brooklynBall = "StickerBrooklynBall"
    case lipstick = "StickerLipstick"
    case yellowTaxi = "StickerYellowTaxi"
    case upsideDownPerson = "StickerUpsideDownPerson"
    case legoHead = "StickerLegoHead"

    var accessibilityLabel: String {
        switch self {
        case .everySecond: "Every second counts sticker"
        case .callMe: "Call me if you get lost patch"
        case .pocketWatch: "Pocket watch"
        case .blueCap: "Blue cap"
        case .vinyl: "Vinyl record"
        case .nyApple: "New York apple sticker"
        case .eightBall: "Eight ball"
        case .brooklynBall: "Brooklyn basketball"
        case .lipstick: "Red lipstick"
        case .yellowTaxi: "Yellow taxi"
        case .upsideDownPerson: "Upside-down portrait sticker"
        case .legoHead: "Worried LEGO head sticker"
        }
    }
}

private enum OnboardingRunningAsset: String, CaseIterable, Hashable {
    case headphones = "RunningHeadphones"
    case cap = "RunningCap"
    case bottle = "RunningBottle"
    case tee = "RunningTee"
    case balm = "RunningBalm"
    case shorts = "RunningShorts"
    case sneaker = "RunningSneaker"
    case sock = "RunningSock"

    var accessibilityLabel: String {
        switch self {
        case .headphones: "Headphones"
        case .cap: "Running cap"
        case .bottle: "Water bottle"
        case .tee: "Running club T-shirt"
        case .balm: "Balm jar"
        case .shorts: "Running shorts"
        case .sneaker: "Running sneaker"
        case .sock: "Running sock"
        }
    }
}

private enum OnboardingLampAsset: String, CaseIterable, Hashable {
    case yellowStem = "OnboardingLampYellowStem"
    case aquaMushroom = "OnboardingLampAquaMushroom"
    case greenDome = "OnboardingLampGreenDome"
    case blackRibbed = "OnboardingLampBlackRibbed"
    case burgundyShade = "OnboardingLampBurgundyShade"
    case redMushroom = "OnboardingLampRedMushroom"
    case orangeMushroom = "OnboardingLampOrangeMushroom"
    case blueOrb = "OnboardingLampBlueOrb"
    case navyDome = "OnboardingLampNavyDome"
    case pleatedBlue = "OnboardingLampPleatedBlue"
    case greenTall = "OnboardingLampGreenTall"
    case redShade = "OnboardingLampRedShade"

    var accessibilityLabel: String { "Table lamp" }
}

private enum OnboardingBurstAsset: Hashable {
    case wardrobe(OnboardingHeroAsset)
    case sticker(OnboardingStickerAsset)
    case running(OnboardingRunningAsset)
    case lamp(OnboardingLampAsset)

    var imageName: String {
        switch self {
        case .wardrobe(let asset): asset.rawValue
        case .sticker(let asset): asset.rawValue
        case .running(let asset): asset.rawValue
        case .lamp(let asset): asset.rawValue
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .wardrobe(let asset): asset.accessibilityLabel
        case .sticker(let asset): asset.accessibilityLabel
        case .running(let asset): asset.accessibilityLabel
        case .lamp(let asset): asset.accessibilityLabel
        }
    }

    var burstSize: CGFloat {
        switch self {
        case .wardrobe(.tShirt): 122
        case .wardrobe(.shorts): 138
        case .wardrobe(.earrings): 58
        case .wardrobe(.watch): 66
        case .wardrobe(.wine): 156
        case .wardrobe(.wallet): 86
        case .wardrobe(.sneaker): 136
        case .wardrobe(.sambaShoe): 154
        case .wardrobe(.memorialShirt): 162
        case .wardrobe(.duffelBag): 160
        case .wardrobe(.redBosHat): 116
        case .wardrobe(.filmCrewCap): 126
        case .wardrobe(.adidasShorts): 136
        case .wardrobe(.keys): 106
        case .wardrobe(.tote): 142
        case .wardrobe(.coffeeMachine): 130
        case .wardrobe(.foldingCrate): 138
        case .wardrobe(.stripedCup): 112
        case .wardrobe(.orangeLamp): 112
        case .wardrobe(.mokaPot): 102
        case .wardrobe(.discoBall): 90
        case .wardrobe(.blueLamp): 102
        case .wardrobe(.orangeChair): 148
        case .wardrobe(.blueBlanket): 144
        case .wardrobe(.navyCap): 126
        case .wardrobe(.ramblinCap): 126
        case .wardrobe(.blueWindbreaker): 156
        case .wardrobe(.greenTee): 146
        case .wardrobe(.beanieRustVintage): 120
        case .wardrobe(.beanieGreenStripe): 138
        case .wardrobe(.beanieSlateBird): 120
        case .wardrobe(.beanieBurgundyBird): 138
        case .sticker(.everySecond): 146
        case .sticker(.callMe): 136
        case .sticker(.pocketWatch): 92
        case .sticker(.blueCap): 114
        case .sticker(.vinyl): 88
        case .sticker(.nyApple): 132
        case .sticker(.eightBall): 88
        case .sticker(.brooklynBall): 94
        case .sticker(.lipstick): 88
        case .sticker(.yellowTaxi): 158
        case .sticker(.upsideDownPerson): 142
        case .sticker(.legoHead): 106
        case .running(.headphones): 126
        case .running(.cap): 106
        case .running(.bottle): 92
        case .running(.tee): 142
        case .running(.balm): 92
        case .running(.shorts): 122
        case .running(.sneaker): 132
        case .running(.sock): 112
        case .lamp(.yellowStem): 112
        case .lamp(.aquaMushroom): 132
        case .lamp(.greenDome): 120
        case .lamp(.blackRibbed): 130
        case .lamp(.burgundyShade): 112
        case .lamp(.redMushroom): 120
        case .lamp(.orangeMushroom): 142
        case .lamp(.blueOrb): 104
        case .lamp(.navyDome): 128
        case .lamp(.pleatedBlue): 126
        case .lamp(.greenTall): 112
        case .lamp(.redShade): 116
        }
    }

    var burstRotation: Double {
        switch self {
        case .wardrobe(.tShirt): -5
        case .wardrobe(.shorts): 3
        case .wardrobe(.earrings): 8
        case .wardrobe(.watch): 3
        case .wardrobe(.wine): -3
        case .wardrobe(.wallet): -12
        case .wardrobe(.sneaker): -3
        case .wardrobe(.sambaShoe): 2
        case .wardrobe(.memorialShirt): 4
        case .wardrobe(.duffelBag): -4
        case .wardrobe(.redBosHat): 1
        case .wardrobe(.filmCrewCap): 5
        case .wardrobe(.adidasShorts): -5
        case .wardrobe(.keys): 7
        case .wardrobe(.tote): 4
        case .wardrobe(.coffeeMachine): -5
        case .wardrobe(.foldingCrate): 3
        case .wardrobe(.stripedCup): 8
        case .wardrobe(.orangeLamp): -5
        case .wardrobe(.mokaPot): 4
        case .wardrobe(.discoBall): 7
        case .wardrobe(.blueLamp): -8
        case .wardrobe(.orangeChair): -6
        case .wardrobe(.blueBlanket): 4
        case .wardrobe(.navyCap): 5
        case .wardrobe(.ramblinCap): -7
        case .wardrobe(.blueWindbreaker): 4
        case .wardrobe(.greenTee): -5
        case .wardrobe(.beanieRustVintage): 5
        case .wardrobe(.beanieGreenStripe): -5
        case .wardrobe(.beanieSlateBird): 5
        case .wardrobe(.beanieBurgundyBird): -5
        case .sticker(.everySecond): -4
        case .sticker(.callMe): 5
        case .sticker(.pocketWatch): -8
        case .sticker(.blueCap): 12
        case .sticker(.vinyl): -6
        case .sticker(.nyApple): 8
        case .sticker(.eightBall): -9
        case .sticker(.brooklynBall): 5
        case .sticker(.lipstick): -7
        case .sticker(.yellowTaxi): -4
        case .sticker(.upsideDownPerson): 7
        case .sticker(.legoHead): -7
        case .running(.headphones): -8
        case .running(.cap): 7
        case .running(.bottle): -5
        case .running(.tee): 4
        case .running(.balm): -11
        case .running(.shorts): 8
        case .running(.sneaker): -4
        case .running(.sock): 12
        case .lamp(.yellowStem): -8
        case .lamp(.aquaMushroom): 4
        case .lamp(.greenDome): -5
        case .lamp(.blackRibbed): 8
        case .lamp(.burgundyShade): -10
        case .lamp(.redMushroom): 6
        case .lamp(.orangeMushroom): -4
        case .lamp(.blueOrb): 11
        case .lamp(.navyDome): -7
        case .lamp(.pleatedBlue): 5
        case .lamp(.greenTall): -3
        case .lamp(.redShade): 9
        }
    }
}

/// The products are deliberately allowed to occupy the entire phone surface.
/// That keeps the onboarding interaction physical rather than trapping the
/// motion inside a decorative, card-sized preview.
private struct PhysicsExplainerScreen: View {
    let title: String
    let assets: OnboardingProductSet
    let burstMultiplier: Int
    let burstID: Int
    let primaryTitle: String
    var showsSharedStackPreview = false
    var isPrimaryDisabled = false
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MagneticStackingField(
                    assets: assets.burstAssets,
                    burstMultiplier: burstMultiplier,
                    burstID: burstID
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if showsSharedStackPreview {
                    SharedStackPreview()
                        .frame(width: min(proxy.size.width - 48, 296))
                        .position(
                            x: proxy.size.width / 2,
                            y: min(max(proxy.size.height * 0.48, 340), 410)
                        )
                        .zIndex(0.5)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 0) {
                    Text(title)
                        .font(.stacksOnboardingSerif(size: proxy.size.height < 760 ? 46 : 52))
                        .foregroundStyle(Color.stacksInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .lineSpacing(-6)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                        .padding(.horizontal, 24)
                        .padding(.top, max(16, proxy.safeAreaInsets.top + 8))
                        .zIndex(1)

                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        PrimaryButton(title: primaryTitle, systemImage: "arrow.right", action: onPrimary)
                            .disabled(isPrimaryDisabled)

                        OnboardingSkipButton(action: onSkip)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 12))
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

/// Products fall behind these pages, so plain grey text was unreadable over
/// them. A frosted pill keeps Skip legible on any artwork.
private struct OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip")
                .font(.stacksText(size: 16, weight: .semibold))
                .foregroundStyle(Color.stacksInk.opacity(0.72))
                .padding(.horizontal, 22)
                .frame(minHeight: 40)
                .stacksGlass(cornerRadius: 20, interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SharedStackPreview: View {
    private let previewAssets = [
        "OnboardingLampOrangeMushroom",
        "OnboardingLampAquaMushroom",
        "OnboardingLampPleatedBlue"
    ]

    var body: some View {
        ZStack {
            AbstractShareBubbleShape()
                .fill(.ultraThinMaterial)
                .overlay {
                    // Lamps scroll behind this card, so it needs a solid
                    // enough base for dark text to stay readable.
                    AbstractShareBubbleShape()
                        .fill(Color.white.opacity(0.72))
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image("OnboardingProfile")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 31, height: 31)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.82), lineWidth: 1)
                        }

                    Text("Lamps for apt")
                        .font(.stacksMasthead(size: 21))
                        .tracking(-0.45)
                        .foregroundStyle(Color.stacksInk)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    ForEach(previewAssets, id: \.self) { asset in
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 62, height: 57)
                            .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                    // Owen's own Stack, so the link uses his handle.
                    Text("stacks.spot/owen/lamps-for-apt")
                        .font(.stacksText(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.stacksMutedInk)
            }
            .padding(.horizontal, 19)
            .padding(.top, 17)
            .padding(.bottom, 22)
        }
        .frame(height: 188)
    }
}

private struct SaveFromAnywhereVisual: View {
    @State private var page = 0
    let onComplete: () -> Void

    private let titles = [
        "Save from the share sheet",
        "Save from any link",
        "Save from a barcode"
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Text(titles[page])
                    .font(.stacksOnboardingSerif(size: proxy.size.height < 760 ? 46 : 52))
                    .foregroundStyle(Color.stacksInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: min(360, proxy.size.width - 48))
                    .padding(.top, max(20, proxy.safeAreaInsets.top + 12))

                Spacer(minLength: 8)

                ZStack {
                    switch page {
                    case 0:
                        SafariSaveDemo()
                    case 1:
                        LinkSaveDemo()
                    default:
                        BarcodeSaveDemo(isActive: page == 2)
                    }
                }
                .id(page)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .frame(width: proxy.size.width - 20,
                       height: min(proxy.size.height * 0.57, 540))

                Spacer(minLength: 8)

                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(page == index ? Color.stacksInk : Color.stacksMutedInk.opacity(0.24))
                                .frame(width: page == index ? 20 : 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)

                    PrimaryButton(title: "Next", systemImage: "arrow.right", action: advance)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(26, proxy.safeAreaInsets.bottom + 14))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 55)
                    .onEnded { gesture in
                        if gesture.translation.width < -70 {
                            advance()
                        } else if gesture.translation.width > 70, page > 0 {
                            withAnimation(.easeInOut(duration: 0.42)) { page -= 1 }
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Way \(page + 1) of 3 to save")
            .accessibilityAction(named: "Next way to save") { advance() }
        }
    }

    private func advance() {
        if page < 2 {
            withAnimation(.easeInOut(duration: 0.42)) { page += 1 }
        } else {
            withAnimation(.easeInOut(duration: 0.42)) { onComplete() }
        }
    }
}

private struct SafariSaveDemo: View {
    var body: some View {
        GeometryReader { proxy in
            let viewportHeight = min(proxy.size.height - 6, 590)
            let viewportWidth = min(proxy.size.width - 8, viewportHeight * 644 / 1400)

            ZStack {
                Color.white

                Image("OnboardingSafariShareSheet")
                    .resizable()
                    .scaledToFit()
                .frame(width: viewportWidth, height: viewportHeight)
                .clipped()
            }
            .frame(width: viewportWidth, height: viewportHeight)
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Safari share sheet showing the Stacks destination")
    }
}

private struct LinkSaveDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusesLink = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.35)).frame(width: 9, height: 9)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.27)).frame(width: 9, height: 9)
                    Circle().fill(Color(red: 0.31, green: 0.78, blue: 0.38)).frame(width: 9, height: 9)
                    Spacer()
                    Text("Safari")
                        .font(.stacksText(size: 11, weight: .medium))
                        .foregroundStyle(Color.stacksMutedInk)
                    Spacer()
                    Color.clear.frame(width: 38, height: 1)
                }
                .frame(height: 11)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .medium))
                    Text("newamsterdamsurf.com/products/windbreaker-blue")
                        .font(.stacksText(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(focusesLink ? Color.blue : Color.stacksMutedInk)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .padding(.horizontal, 9)
                .background(
                    focusesLink ? Color.blue.opacity(0.13) : Color.black.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(focusesLink ? Color.blue.opacity(0.32) : .clear, lineWidth: 1)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)

                Image("OnboardingBlueWindbreaker")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .padding(.horizontal, 20)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
            }
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Copy the hoodie product link from Safari, then paste it into Stacks")
        .onAppear {
            focusesLink = reduceMotion
            guard !reduceMotion else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                    focusesLink = true
                }
            }
        }
    }
}

private struct BarcodeSaveDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    @State private var scanning = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    barcodeGlassIcon("xmark")
                    Spacer()
                    Text("Scan barcode").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    barcodeGlassIcon("bolt.slash")
                }
                .padding(16)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.white.opacity(0.10))
                        .frame(width: 220, height: 112)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.stacksInk.opacity(0.44), lineWidth: 1.5)
                        }
                    HStack(spacing: 3) {
                        ForEach(0..<28) { index in
                            Rectangle()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: index.isMultiple(of: 4) ? 4 : 2,
                                       height: index.isMultiple(of: 3) ? 62 : 48)
                        }
                    }
                    Rectangle()
                        .fill(Color(red: 0.16, green: 0.68, blue: 0.57))
                        .frame(width: 205, height: 2)
                        .shadow(color: Color(red: 0.16, green: 0.68, blue: 0.57).opacity(0.6), radius: 4)
                        .offset(y: scanning ? 44 : -44)
                }
                Spacer()
                Text("Point at a product barcode")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.bottom, 25)
            }
            .foregroundStyle(Color.white)
        }
        .frame(maxWidth: 340)
        .frame(height: 292)
        .modifier(BarcodeBlackGlass())
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 21, x: 0, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Scan a product barcode to find and save its listing")
        .onChange(of: isActive, initial: true) { _, active in
            scanning = false
            guard active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                scanning = true
            }
        }
    }

    private func barcodeGlassIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(.white.opacity(0.12), in: Circle())
            .overlay {
                Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.8)
            }
    }
}

private struct BarcodeBlackGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .glassEffect(.regular.tint(Color.black.opacity(0.80)), in: .rect(cornerRadius: 23))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
    }
}

private enum SaveSurfaceKind {
    case browser
    case social
}

private struct SaveSurfaceWindow: View {
    let kind: SaveSurfaceKind

    var body: some View {
        VStack(spacing: 0) {
            if kind == .browser {
                browserChrome
            } else {
                socialChrome
            }

            BouncingStickerCollage()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(kind == .browser ? Color(red: 0.972, green: 0.969, blue: 0.963) : .white)
                .clipped()

            if kind == .social {
                socialFooter
            }
        }
        .frame(maxWidth: 340)
        .frame(height: 292)
        .background(.white, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.13), radius: 21, x: 0, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(kind == .browser
            ? "Browser window with colorful cutout stickers bouncing inside"
            : "Social media post with colorful cutout stickers bouncing inside")
    }

    private var browserChrome: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 9, height: 9)
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.24)).frame(width: 9, height: 9)
            Circle().fill(Color(red: 0.28, green: 0.76, blue: 0.36)).frame(width: 9, height: 9)

            Text("stacks.app / finds")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.stacksMutedInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.045), in: Capsule())

            Image(systemName: "square.on.square")
                .font(.system(size: 11))
                .foregroundStyle(Color.stacksMutedInk)
        }
        .frame(height: 11)
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(Color(red: 0.955, green: 0.953, blue: 0.948))
        .overlay(alignment: .bottom) { Color.black.opacity(0.07).frame(height: 1) }
    }

    private var socialChrome: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.stacksInk)
                .frame(width: 26, height: 26)
                .overlay {
                    Text("s")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                }
            Text("saved.by.stacks")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.stacksInk)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.stacksInk)
        }
        .padding(.horizontal, 14)
        .frame(height: 43)
    }

    private var socialFooter: some View {
        HStack(spacing: 13) {
            Image(systemName: "heart")
            Image(systemName: "bubble.right")
            Image(systemName: "paperplane")
            Spacer()
            Image(systemName: "bookmark")
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(Color.stacksInk)
        .padding(.horizontal, 14)
        .frame(height: 37)
    }
}

private struct BouncingStickerCollage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasBlasted = false
    @State private var isFloating = false

    private let stickers: [(OnboardingStickerAsset, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (.blueCap, 0.19, 0.24, 80, 10, -9),
        (.nyApple, 0.73, 0.21, 67, -11, 9),
        (.vinyl, 0.49, 0.45, 82, 9, 11),
        (.yellowTaxi, 0.81, 0.68, 86, -12, -8),
        (.eightBall, 0.23, 0.72, 67, 11, 8),
        (.lipstick, 0.56, 0.78, 63, -8, -11),
        (.brooklynBall, 0.76, 0.42, 58, 8, 10)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(stickers.enumerated()), id: \.offset) { index, sticker in
                    Image(sticker.0.rawValue)
                        .resizable()
                        .scaledToFit()
                        .frame(width: sticker.3, height: sticker.3)
                        .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 5)
                        .rotationEffect(.degrees(isFloating ? Double(sticker.4) : -Double(sticker.4)))
                        .scaleEffect(hasBlasted ? 1 : 0.12)
                        .position(x: proxy.size.width * sticker.1, y: proxy.size.height * sticker.2)
                        .offset(
                            x: isFloating ? sticker.4 : -sticker.4,
                            y: isFloating ? sticker.5 : -sticker.5
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.65).delay(Double(index) * 0.055), value: hasBlasted)
                        .animation(.easeInOut(duration: 1.5 + Double(index) * 0.13).repeatForever(autoreverses: true), value: isFloating)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            hasBlasted = true
            if !reduceMotion { isFloating = true }
        }
    }
}

private struct AbstractShareBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.14, y: height * 0.02))
        path.addCurve(
            to: CGPoint(x: width * 0.83, y: height * 0.04),
            control1: CGPoint(x: width * 0.39, y: -height * 0.035),
            control2: CGPoint(x: width * 0.67, y: height * 0.075)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.28),
            control1: CGPoint(x: width * 0.96, y: height * 0.045),
            control2: CGPoint(x: width * 1.02, y: height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.92, y: height * 0.74),
            control1: CGPoint(x: width * 0.965, y: height * 0.47),
            control2: CGPoint(x: width * 1.015, y: height * 0.64)
        )
        path.addLine(to: CGPoint(x: width * 0.985, y: height))
        path.addCurve(
            to: CGPoint(x: width * 0.72, y: height * 0.98),
            control1: CGPoint(x: width * 0.91, y: height * 0.90),
            control2: CGPoint(x: width * 0.80, y: height * 1.01)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.025, y: height * 0.82),
            control1: CGPoint(x: width * 0.53, y: height * 1.01),
            control2: CGPoint(x: width * 0.10, y: height * 0.985)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.035, y: height * 0.29),
            control1: CGPoint(x: -width * 0.005, y: height * 0.66),
            control2: CGPoint(x: width * 0.005, y: height * 0.43)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.14, y: height * 0.02),
            control1: CGPoint(x: width * 0.035, y: height * 0.14),
            control2: CGPoint(x: width * 0.07, y: height * 0.04)
        )
        return path
    }
}

private struct ShareMessageBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.14, y: height * 0.02))
        path.addCurve(
            to: CGPoint(x: width * 0.88, y: height * 0.04),
            control1: CGPoint(x: width * 0.39, y: -height * 0.04),
            control2: CGPoint(x: width * 0.68, y: height * 0.07)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.24),
            control1: CGPoint(x: width * 0.97, y: height * 0.05),
            control2: CGPoint(x: width, y: height * 0.14)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.93, y: height * 0.82),
            control1: CGPoint(x: width * 0.94, y: height * 0.40),
            control2: CGPoint(x: width * 1.02, y: height * 0.66)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.17, y: height * 0.91),
            control1: CGPoint(x: width * 0.73, y: height * 0.93),
            control2: CGPoint(x: width * 0.41, y: height * 0.86)
        )
        path.addLine(to: CGPoint(x: width * 0.05, y: height))
        path.addCurve(
            to: CGPoint(x: width * 0.10, y: height * 0.78),
            control1: CGPoint(x: width * 0.10, y: height * 0.89),
            control2: CGPoint(x: width * 0.07, y: height * 0.85)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.03, y: height * 0.26),
            control1: CGPoint(x: -width * 0.02, y: height * 0.59),
            control2: CGPoint(x: width * 0.01, y: height * 0.39)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.14, y: height * 0.02),
            control1: CGPoint(x: width * 0.04, y: height * 0.13),
            control2: CGPoint(x: width * 0.07, y: height * 0.04)
        )
        return path
    }
}

private struct ExplainerScreen<Visual: View>: View {
    let title: String
    let visual: Visual
    let primaryTitle: String
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let titleSize: CGFloat = isCompact ? 46 : 52
            let visualHeight: CGFloat = isCompact ? 338 : 390

            VStack(spacing: 0) {
                Spacer(minLength: isCompact ? 18 : 34)

                Text(title)
                    .font(.stacksOnboardingSerif(size: titleSize))
                    .foregroundStyle(Color.stacksInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .lineSpacing(-6)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    // The title must receive a real width constraint before it
                    // chooses its line breaks; fixedSize here made longer titles
                    // keep one line and run beyond the right edge.
                    .frame(maxWidth: min(360, proxy.size.width - 48))
                    .padding(.horizontal, 24)

                visual
                    .frame(width: max(1, proxy.size.width - 20))
                    .frame(height: visualHeight)
                    .padding(.top, isCompact ? 10 : 16)
                    .clipped()

                Spacer(minLength: 4)

                VStack(spacing: 12) {
                    PrimaryButton(title: primaryTitle, systemImage: "arrow.right", action: onPrimary)
                    OnboardingSkipButton(action: onSkip)
                }
                .frame(width: max(1, proxy.size.width - 48))
                .padding(.bottom, 28)
            }
            // SaveFromAnywhereReference is a very wide source image. Give the
            // whole composition the device's exact width so no child can expand
            // the VStack and push the centered content offscreen.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct ProductPhotoCloud: View {
    @State private var isFloating = false

    private let items: [(String, CGFloat, CGFloat, CGFloat, Double)] = [
        ("Red Sneakers", -112, -34, 132, -7),
        ("Chrome Task Lamp", 92, -126, 116, 8),
        ("Dot Grid Notebook", 104, 76, 118, -10),
        ("Camera", -94, 96, 122, 6),
        ("Watch", 0, -2, 134, 11),
        ("Tote Bag", 8, -188, 102, -8)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ProductObjectImage(title: item.0)
                    .frame(width: item.3, height: item.3)
                    .padding(8)
                    .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 10)
                    .rotationEffect(.degrees(item.4 + (isFloating ? 3 : -3)))
                    .offset(
                        x: item.1,
                        y: item.2 + (isFloating ? CGFloat(index.isMultiple(of: 2) ? -12 : 12) : CGFloat(index.isMultiple(of: 2) ? 8 : -8))
                    )
                    .animation(.easeInOut(duration: 2.4 + Double(index) * 0.1).repeatForever(autoreverses: true), value: isFloating)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { isFloating = true }
    }
}

/// The hero cutouts fire upward as the second screen appears. Device tilt then
/// supplies the directional force, so the finds eventually collect at the
/// physical bottom edge of the phone.
private struct MagneticStackingField: View {
    @Environment(\.appServices) private var services

    var assets: [OnboardingBurstAsset] = OnboardingHeroAsset.allCases.map(OnboardingBurstAsset.wardrobe)
    var burstMultiplier = 1
    var burstID = 0

    @State private var particles: [OnboardingPhysicsParticle] = []
    @State private var motionManager = OnboardingTiltMotionManager()
    @State private var tilt = CGVector.zero
    @State private var lastWallImpact = Date.distantPast

    private let frameTicker = Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                ForEach(particles) { particle in
                    BurstCutout(asset: particle.asset)
                        .frame(width: particle.size, height: particle.size)
                        .rotationEffect(.degrees(particle.rotation))
                        .position(particle.position)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                launch(in: size)
                motionManager.start { tilt in
                    self.tilt = tilt
                }
            }
            .onDisappear { motionManager.stop() }
            .onChange(of: size) { _, newSize in
                if particles.isEmpty {
                    launch(in: newSize)
                }
            }
            .onChange(of: burstID) { _, _ in
                launch(in: size)
            }
            .onReceive(frameTicker) { _ in
                advanceParticles(in: size)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Products falling into a Stack")
        }
    }

    private func launch(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        services.haptics.impact(.heavy)

        let scale = min(1, max(0.78, size.width / 390))
        let definitions = assets.map { ($0, $0.burstSize, $0.burstRotation) }

        let copies = max(1, min(burstMultiplier, 4))
        particles = (0 ..< copies).flatMap { (copy: Int) -> [OnboardingPhysicsParticle] in
            let copyOffset = CGFloat(copy) - CGFloat(copies - 1) / 2
            let copyScale = max(0.66, 1 - CGFloat(copy) * 0.10)
            let cannon = CGPoint(
                x: size.width * 0.5,
                y: size.height * 0.5
            )

            return definitions.enumerated().map { (index: Int, definition) -> OnboardingPhysicsParticle in
                let indexOffset = CGFloat(index - 4)
                let fraction: CGFloat = CGFloat(index) / CGFloat(max(1, definitions.count))
                let angle: CGFloat = fraction * .pi * 2 - .pi / 2 + copyOffset * 0.16
                let speed: CGFloat = 640 + CGFloat(index % 3) * 90 + abs(copyOffset) * 70
                return OnboardingPhysicsParticle(
                    asset: definition.0,
                    size: definition.1 * scale * copyScale,
                    position: CGPoint(x: cannon.x + indexOffset * 3, y: cannon.y + copyOffset * 4),
                    velocity: CGVector(
                        dx: cos(angle) * speed,
                        dy: sin(angle) * speed
                    ),
                    rotation: definition.2 + Double(copyOffset * 9),
                    angularVelocity: Double(index.isMultiple(of: 2) ? 18 : -18) + Double(copyOffset * 6)
                )
            }
        }
    }

    private func advanceParticles(in size: CGSize) {
        guard !particles.isEmpty, size.width > 0, size.height > 0 else { return }

        // The small resting force keeps the products moving when the phone is
        // flat; tilting produces a stronger, physical pull toward an edge.
        let gravity = CGVector(dx: tilt.dx * 1_050, dy: 250 + tilt.dy * 1_050)
        let delta: CGFloat = 1 / 60

        var strongestWallImpact: CGFloat = 0
        for index in particles.indices {
            particles[index].velocity.dx += gravity.dx * delta
            particles[index].velocity.dy += gravity.dy * delta
            particles[index].velocity.dx *= 0.988
            particles[index].velocity.dy *= 0.988
            particles[index].position.x += particles[index].velocity.dx * delta
            particles[index].position.y += particles[index].velocity.dy * delta
            particles[index].rotation += particles[index].angularVelocity * Double(delta)
            particles[index].angularVelocity *= 0.992
            strongestWallImpact = max(strongestWallImpact, constrainParticle(at: index, in: size))
        }

        resolveParticleCollisions()
        playWallImpactIfNeeded(speed: strongestWallImpact)
    }

    private func constrainParticle(at index: Int, in size: CGSize) -> CGFloat {
        let radius = particles[index].collisionRadius
        let horizontalRange = (radius + 4)...max(radius + 4, size.width - radius - 4)
        let verticalRange = (radius + 4)...max(radius + 4, size.height - radius - 4)
        var impactSpeed: CGFloat = 0

        if particles[index].position.x < horizontalRange.lowerBound {
            impactSpeed = max(impactSpeed, abs(particles[index].velocity.dx))
            particles[index].position.x = horizontalRange.lowerBound
            particles[index].velocity.dx = abs(particles[index].velocity.dx) * 0.35
        } else if particles[index].position.x > horizontalRange.upperBound {
            impactSpeed = max(impactSpeed, abs(particles[index].velocity.dx))
            particles[index].position.x = horizontalRange.upperBound
            particles[index].velocity.dx = -abs(particles[index].velocity.dx) * 0.35
        }

        if particles[index].position.y < verticalRange.lowerBound {
            impactSpeed = max(impactSpeed, abs(particles[index].velocity.dy))
            particles[index].position.y = verticalRange.lowerBound
            particles[index].velocity.dy = abs(particles[index].velocity.dy) * 0.32
        } else if particles[index].position.y > verticalRange.upperBound {
            impactSpeed = max(impactSpeed, abs(particles[index].velocity.dy))
            particles[index].position.y = verticalRange.upperBound
            particles[index].velocity.dy = -abs(particles[index].velocity.dy) * 0.32
        }
        return impactSpeed
    }

    private func playWallImpactIfNeeded(speed: CGFloat) {
        guard speed > 120,
              Date().timeIntervalSince(lastWallImpact) > 0.14 else { return }
        lastWallImpact = Date()
        services.haptics.impact(speed > 600 ? .medium : .light)
    }

    private func resolveParticleCollisions() {
        guard particles.count > 1 else { return }

        for firstIndex in particles.indices {
            for secondIndex in particles.indices.dropFirst(firstIndex + 1) {
                let deltaX = particles[secondIndex].position.x - particles[firstIndex].position.x
                let deltaY = particles[secondIndex].position.y - particles[firstIndex].position.y
                let distance = max(0.001, hypot(deltaX, deltaY))
                let targetDistance = particles[firstIndex].collisionRadius + particles[secondIndex].collisionRadius
                guard distance < targetDistance else { continue }

                let normalX = deltaX / distance
                let normalY = deltaY / distance
                let overlap = (targetDistance - distance) * 0.5
                particles[firstIndex].position.x -= normalX * overlap
                particles[firstIndex].position.y -= normalY * overlap
                particles[secondIndex].position.x += normalX * overlap
                particles[secondIndex].position.y += normalY * overlap

                let relativeVelocity = (particles[secondIndex].velocity.dx - particles[firstIndex].velocity.dx) * normalX
                    + (particles[secondIndex].velocity.dy - particles[firstIndex].velocity.dy) * normalY
                guard relativeVelocity < 0 else { continue }

                let impulse = -relativeVelocity * 0.55
                particles[firstIndex].velocity.dx -= impulse * normalX
                particles[firstIndex].velocity.dy -= impulse * normalY
                particles[secondIndex].velocity.dx += impulse * normalX
                particles[secondIndex].velocity.dy += impulse * normalY
            }
        }
    }
}

private final class OnboardingTiltMotionManager {
    private let manager = CMMotionManager()
    private var referenceRoll: Double?
    private var referencePitch: Double?

    func start(onTilt: @escaping (CGVector) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else {
            onTilt(.zero)
            return
        }

        referenceRoll = nil
        referencePitch = nil
        manager.deviceMotionUpdateInterval = 1 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            if self.referenceRoll == nil {
                self.referenceRoll = motion.attitude.roll
                self.referencePitch = motion.attitude.pitch
                onTilt(.zero)
                return
            }

            let roll = self.normalized(motion.attitude.roll - (self.referenceRoll ?? 0))
            let pitch = self.normalized(motion.attitude.pitch - (self.referencePitch ?? 0))
            onTilt(CGVector(dx: roll, dy: pitch))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        referenceRoll = nil
        referencePitch = nil
    }

    private func normalized(_ value: Double) -> CGFloat {
        CGFloat(max(-1, min(1, value / 0.42)))
    }
}

private struct BurstCutout: View {
    let asset: OnboardingBurstAsset

    var body: some View {
        Image(asset.imageName)
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 4)
            .shadow(color: .white.opacity(0.88), radius: 2, x: 0, y: 0)
            .accessibilityLabel(asset.accessibilityLabel)
            .accessibilityHidden(true)
    }
}

private struct OnboardingPhysicsParticle: Identifiable {
    let id = UUID()
    let asset: OnboardingBurstAsset
    let size: CGFloat
    var position: CGPoint
    var velocity: CGVector
    var rotation: Double
    var angularVelocity: Double

    var collisionRadius: CGFloat { size * 0.30 }
}

private struct StackItVisual: View {
    var body: some View {
        MagneticStackingField()
    }
}

private struct MagneticGlassOrb: View {
    let focusPoint: CGPoint?
    let rippleProgress: CGFloat
    let isComplete: Bool

    @State private var isBreathing = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let diameter = min(max(width * 1.22, 360), 520)
            let center = CGPoint(x: width * 0.5, y: height * 1.13)
            let focusedRimPoint = projectedRimPoint(from: focusPoint, center: center, diameter: diameter)
            let idleGlow = isComplete ? 0.20 : (isBreathing ? 0.42 : 0.28)

            ZStack {
                Circle()
                    .fill(.white.opacity(isComplete ? 0.10 : 0.16))
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.52), .clear, .white.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .frame(width: diameter, height: diameter)
                    .position(center)

                Circle()
                    .stroke(.white.opacity(idleGlow), lineWidth: 16)
                    .blur(radius: 12)
                    .frame(width: diameter, height: diameter)
                    .position(center)

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.64),
                                .cyan.opacity(0.42),
                                .blue.opacity(0.34),
                                .purple.opacity(0.28),
                                .pink.opacity(0.24),
                                .yellow.opacity(0.24),
                                .white.opacity(0.64)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.25
                    )
                    .blur(radius: 0.2)
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(isBreathing ? 6 : -6))
                    .position(center)

                Capsule()
                    .fill(.white.opacity(0.34))
                    .frame(width: diameter * 0.48, height: diameter * 0.075)
                    .blur(radius: 13)
                    .rotationEffect(.degrees(-25))
                    .position(x: center.x - diameter * 0.16, y: center.y - diameter * 0.24)

                Capsule()
                    .fill(.cyan.opacity(0.11))
                    .frame(width: diameter * 0.52, height: diameter * 0.06)
                    .blur(radius: 18)
                    .rotationEffect(.degrees(18))
                    .position(x: center.x + diameter * 0.12, y: center.y - diameter * 0.05)

                if let focusedRimPoint {
                    Circle()
                        .fill(.white.opacity(0.68))
                        .frame(width: 28 + rippleProgress * 20, height: 28 + rippleProgress * 20)
                        .blur(radius: 14)
                        .position(focusedRimPoint)

                    Circle()
                        .stroke(.white.opacity(0.68 * rippleProgress), lineWidth: 1.4)
                        .frame(width: diameter * (0.18 + rippleProgress * 0.22), height: diameter * (0.18 + rippleProgress * 0.22))
                        .scaleEffect(1 + rippleProgress * 0.35)
                        .opacity(rippleProgress)
                        .position(focusedRimPoint)
                }
            }
            .compositingGroup()
            .scaleEffect(1 + rippleProgress * 0.018, anchor: .bottom)
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isBreathing)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: rippleProgress)
            .onAppear { isBreathing = true }
        }
    }

    private func projectedRimPoint(from point: CGPoint?, center: CGPoint, diameter: CGFloat) -> CGPoint? {
        guard let point else { return nil }
        let deltaX = point.x - center.x
        let deltaY = point.y - center.y
        let distance = max(1, hypot(deltaX, deltaY))
        let radius = diameter * 0.47
        return CGPoint(x: center.x + (deltaX / distance) * radius, y: center.y + (deltaY / distance) * radius)
    }
}

private struct ShareItVisual: View {
    var body: some View {
        TiltShareStackPreview()
    }
}

private struct TiltShareStackPreview: View {
    @State private var motionManager = OnboardingTiltMotionManager()
    @State private var tilt = CGVector.zero

    private let products: [(OnboardingHeroAsset, CGFloat, CGFloat, CGFloat, Double, CGFloat)] = [
        (.tShirt, 0.23, 0.41, 104, -5, 1.0),
        (.shorts, 0.55, 0.40, 112, 4, 0.7),
        (.earrings, 0.82, 0.43, 52, 8, 1.2),
        (.wine, 0.21, 0.71, 128, -4, 1.4),
        (.wallet, 0.47, 0.61, 72, -11, 1.8),
        (.sneaker, 0.64, 0.68, 104, -2, 1.3),
        (.tote, 0.80, 0.75, 116, 5, 2.0)
    ]

    var body: some View {
        GeometryReader { proxy in
            let previewSize = CGSize(
                width: min(proxy.size.width - 26, 348),
                height: max(286, min(proxy.size.height - 16, 360))
            )

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.stacksInk.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 12)

                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .position(x: previewSize.width * 0.91, y: previewSize.height * 0.10)

                StackTitle(text: "Summer")
                    .frame(width: previewSize.width * 0.74)
                    .position(x: previewSize.width * 0.5, y: previewSize.height * 0.21)

                ForEach(Array(products.enumerated()), id: \.offset) { _, product in
                    ProductCutout(asset: product.0)
                        .frame(width: product.3, height: product.3)
                        .rotationEffect(.degrees(product.4 + Double(tilt.dx * product.5 * 4)))
                        .offset(
                            x: tilt.dx * product.5 * 15,
                            y: tilt.dy * product.5 * 12
                        )
                        .position(
                            x: previewSize.width * product.1,
                            y: previewSize.height * product.2
                        )
                }

                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.stacksInk, in: Circle())
                    .position(x: previewSize.width * 0.88, y: previewSize.height * 0.88)
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .rotation3DEffect(
                .degrees(-Double(tilt.dx) * 3.4),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.7
            )
            .rotation3DEffect(
                .degrees(Double(tilt.dy) * 2.8),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.7
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .onAppear {
                motionManager.start { tilt in
                    self.tilt = tilt
                }
            }
            .onDisappear { motionManager.stop() }
        }
    }
}

private struct MiniDiscoverCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.white
                ProductObjectImage(title: title == "Desk" ? "Chrome Task Lamp" : "Tote Bag")
                    .frame(width: 82, height: 82)
                    .rotationEffect(.degrees(title == "Desk" ? -8 : 9))
            }
            .frame(width: 142, height: 146)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(title)
                .font(.stacksDisplay(size: 22, weight: .bold))
                .foregroundStyle(Color.stacksInk)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct ProductObjectImage: View {
    let title: String

    var body: some View {
        AsyncImage(url: DemoProductImageCatalog.url(for: title)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .tint(Color.stacksInk)
            case .failure:
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.stacksInk.opacity(0.72))
            @unknown default:
                EmptyView()
            }
        }
    }
}
