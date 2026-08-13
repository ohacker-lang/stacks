import SwiftUI
import UIKit
import CoreMotion

private enum OnboardingStage: Equatable {
    case hero
    case stackIt
    case shareIt
    case firstStack
}

private enum FirstStackStep: Equatable {
    case name
    case readiness
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
    @Environment(\.appServices) private var services
    @State private var stage: OnboardingStage = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-preview-onboarding-stickers") {
            .stackIt
        } else if ProcessInfo.processInfo.arguments.contains("-preview-first-stack-name") {
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
    @State private var firstStackStep: FirstStackStep = .name
    @State private var firstItemImageData: Data?
    @State private var onboardingProfile: UserProfile?
    @State private var firstItemImportSheet: FirstItemImportSheet?
    @State private var isShowingFirstItemCamera = false
    @State private var isShowingFirstItemPhotoLibrary = false
    @State private var isAuthenticating = false
    @State private var isShowingEmailCheckAlert = false
    @State private var burstMultiplier = 1
    @State private var burstID = 0
    @Namespace private var firstStackCanvasNamespace

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            switch stage {
            case .hero:
                hero
            case .stackIt:
                PhysicsExplainerScreen(
                    title: "Stack your finds",
                    assets: .stacking,
                    burstMultiplier: burstMultiplier,
                    burstID: burstID,
                    primaryTitle: "Next",
                    onPrimary: advanceToShareIt,
                    onSkip: completeOnboarding
                )
            case .shareIt:
                PhysicsExplainerScreen(
                    title: "Share your taste",
                    assets: .sharing,
                    burstMultiplier: burstMultiplier,
                    burstID: burstID,
                    primaryTitle: "Make your first Stack",
                    showsSharedStackPreview: true,
                    onPrimary: advanceToFirstStack,
                    onSkip: completeOnboarding
                )
            case .firstStack:
                firstStackPrompt
            }

            if isShowingFirstItemCamera {
                ProductCameraCaptureView(
                    onCapture: { data in
                        isShowingFirstItemCamera = false
                        openFirstItemImport(.photo, imageData: data)
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
                        isShowingFirstItemCamera = false
                    },
                    onboardingHint: "Other ways to add"
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(2)
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .email:
                EmailSignInSheet(onSubmit: { email in
                    let didSignIn = await session.signInWithEmail(email)
                    if didSignIn {
                        if session.pendingEmailSignIn {
                            isShowingEmailCheckAlert = true
                        } else {
                            advanceToStackIt()
                        }
                    }
                    return didSignIn
                }, onCancel: returnToHeroAfterCancelledSignIn)
                .presentationDetents([.height(194)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .fullScreenCover(isPresented: $isShowingFirstItemPhotoLibrary) {
            ProductPhotoLibraryPicker(
                onCapture: { data in
                    isShowingFirstItemPhotoLibrary = false
                    openFirstItemImport(.photo, imageData: data)
                },
                onCancel: {
                    isShowingFirstItemPhotoLibrary = false
                }
            )
            .ignoresSafeArea()
        }
        .alert("Check your email", isPresented: $isShowingEmailCheckAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open the secure Stacks sign-in link we sent you. You’ll return here automatically.")
        }
        .fullScreenCover(item: $firstItemImportSheet) { importSheet in
            if let onboardingProfile {
                switch importSheet {
                case .link:
                    ProductLinkImportSheet(
                        user: onboardingProfile,
                        locksDestination: true,
                        initialNewStackTitle: resolvedFirstStackTitle,
                        onSaved: finishFirstItemImport
                    )
                case .photo:
                    PhotoProductImportSheet(
                        initialImageData: firstItemImageData,
                        navigationTitle: "Review Product",
                        user: onboardingProfile,
                        locksDestination: true,
                        initialNewStackTitle: resolvedFirstStackTitle,
                        onSaved: finishFirstItemImport
                    )
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            }
        }
    }

    private var hero: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let heroScale = min(1, max(0.88, proxy.size.height / 852))
            let titleSize = min((isCompact ? 48 : 54) * heroScale, proxy.size.width * 0.142)
            let titleHeight = (isCompact ? 98 : 108) * heroScale
            let productHeight = min(max(proxy.size.height * 0.50, 340), isCompact ? 366 : 410)
            let ctaBottomInset = max(isCompact ? 22 : 26, proxy.safeAreaInsets.bottom + 12)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    (Text("Collect ").font(.stacksOnboardingSerif(size: titleSize))
                        + Text("your").font(.stacksOnboardingSerif(size: titleSize)).italic()
                        + Text("\ninternet").font(.stacksOnboardingSerif(size: titleSize)))
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
                            let didSignIn = await session.signInWithApple()
                            isAuthenticating = false
                            if didSignIn {
                                advanceToStackIt()
                            }
                        }
                    }

                    Button("Continue with email") {
                        guard !isAuthenticating else { return }
                        services.haptics.impact(.light)
                        sheet = .email
                    }
                    .buttonStyle(.plain)
                    .font(.stacksText(size: 14, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk)
                    .disabled(isAuthenticating)
                }
                .padding(.horizontal, isCompact ? 24 : 28)
                .padding(.bottom, ctaBottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
        }
    }

    private var firstStackPrompt: some View {
        GeometryReader { proxy in
            if firstStackStep == .name {
                FirstStackNameQuestion(
                    title: $firstStackTitle,
                    namespace: firstStackCanvasNamespace,
                    onContinue: {
                        advanceFirstStackStep(to: .readiness)
                    },
                    onSkip: completeOnboarding
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color.white.ignoresSafeArea())
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: goBackInFirstStackFlow) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(Color.stacksInk)

                        Spacer()
                    }
                    .padding(.top, max(8, proxy.safeAreaInsets.top))

                    Spacer(minLength: 18)

                    firstStackStepContent
                        .id(firstStackStep)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    Spacer(minLength: 0)

                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.stacksText(size: 16, weight: .semibold))
                    .foregroundStyle(Color.stacksMutedInk)
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 12))
                .animation(.easeInOut(duration: 0.24), value: firstStackStep)
                .background(Color.white.ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private var firstStackStepContent: some View {
        switch firstStackStep {
        case .name:
            EmptyView()

        case .readiness:
            FirstFindPrompt(namespace: firstStackCanvasNamespace) {
                services.haptics.impact(.medium)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isShowingFirstItemCamera = true
                } else {
                    isShowingFirstItemPhotoLibrary = true
                }
            }

        }
    }

    private var resolvedFirstStackTitle: String {
        let title = firstStackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "First Stack" : title
    }

    private func openFirstItemImport(
        _ importSheet: FirstItemImportSheet,
        imageData: Data? = nil
    ) {
        if let imageData {
            firstItemImageData = imageData
        }

        Task {
            guard case .onboarding(let authSession) = session.state else { return }
            do {
                onboardingProfile = try await services.profiles.currentProfile(for: authSession)
                firstItemImportSheet = importSheet
            } catch {
                services.haptics.notification(.error)
            }
        }
    }

    private func finishFirstItemImport(_ stack: Stack) {
        completeOnboarding()
    }

    private func advanceFirstStackStep(to step: FirstStackStep) {
        withAnimation(.easeInOut(duration: 0.24)) {
            firstStackStep = step
        }
    }

    private func goBackInFirstStackFlow() {
        switch firstStackStep {
        case .name:
            break
        case .readiness:
            advanceFirstStackStep(to: .name)
        }
    }

    private func completeOnboarding() {
        Task {
            await session.completeOnboarding()
        }
    }

    private func advanceToStackIt() {
        guard stage == .hero else { return }
        // Keep the stage swap immediate. The physics field is the transition:
        // the same hero products launch into the newly visible Stack canvas.
        burstMultiplier = 1
        burstID += 1
        stage = .stackIt
    }

    private func advanceToShareIt() {
        guard stage == .stackIt else { return }
        burstMultiplier = min(burstMultiplier * 2, 4)
        burstID += 1
        stage = .shareIt
    }

    private func advanceToFirstStack() {
        guard stage == .shareIt else { return }
        stage = .firstStack
    }

    private func returnToHeroAfterCancelledSignIn() {
        if stage != .hero {
            withAnimation(.easeOut(duration: 0.2)) { stage = .hero }
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

private struct FirstFindPrompt: View {
    let namespace: Namespace.ID
    let onAdd: () -> Void

    private let focusedBlob = StackPlaceholderBlob.featured

    var body: some View {
        VStack(spacing: 0) {
            Text("Show us what you’ve got")
                .font(.stacksOnboardingSerif(size: 46))
                .foregroundStyle(Color.stacksInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Text("Start with a photo. We’ll help with the rest.")
                .font(.stacksText(size: 16, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Button(action: onAdd) {
                PlaceholderProductBlob(blob: focusedBlob)
                    .matchedGeometryEffect(id: focusedBlob.id, in: namespace)
                    .frame(width: 260, height: 330)
                    .overlay(alignment: .bottom) {
                        Label("Open camera", systemImage: "camera.fill")
                            .font(.stacksText(size: 16, weight: .semibold))
                            .foregroundStyle(Color.stacksInk)
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 14)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the camera to add your first product")
            .padding(.top, 34)
        }
    }
}

private struct FirstStackNameQuestion: View {
    @Binding var title: String
    let namespace: Namespace.ID
    let onContinue: () -> Void
    let onSkip: () -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                EmptyStackNameCanvas(
                    title: $title,
                    namespace: namespace,
                    titleTopInset: proxy.safeAreaInsets.top + 56
                )

                OnboardingStackChrome()
                    .padding(.horizontal, 17)
                    .padding(.top, proxy.safeAreaInsets.top + 3)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    PrimaryButton(title: "Continue", systemImage: "arrow.right", action: onContinue)
                        .disabled(trimmedTitle.isEmpty)

                    Button("Skip") {
                        onSkip()
                    }
                    .font(.stacksText(size: 16, weight: .semibold))
                    .foregroundStyle(Color.stacksMutedInk)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 8))
            }
        }
    }
}

private struct OnboardingStackChrome: View {
    var body: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.system(size: 25, weight: .regular))
                .frame(width: 34, height: 34)

            Spacer()

            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .regular))
                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .regular))
            }
            .frame(height: 34)
        }
        .foregroundStyle(Color.stacksInk.opacity(0.25))
        .accessibilityHidden(true)
    }
}

private struct EmptyStackNameCanvas: View {
    @Binding var title: String
    let namespace: Namespace.ID
    let titleTopInset: CGFloat

    private let blobs: [StackPlaceholderBlob] = [
        .featured,
        StackPlaceholderBlob(id: "cap", imageName: "StickerBlueCap", x: 0.76, y: 0.31, width: 118, height: 82, rotation: 6),
        StackPlaceholderBlob(id: "shorts", imageName: "OnboardingShorts", x: 0.70, y: 0.47, width: 130, height: 96, rotation: -4),
        StackPlaceholderBlob(id: "wallet", imageName: "OnboardingWallet", x: 0.22, y: 0.48, width: 98, height: 76, rotation: -8),
        StackPlaceholderBlob(id: "watch", imageName: "OnboardingWatch", x: 0.44, y: 0.64, width: 80, height: 116, rotation: 5),
        StackPlaceholderBlob(id: "tote", imageName: "OnboardingTote", x: 0.74, y: 0.67, width: 118, height: 136, rotation: -5)
    ]

    private var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 390
            let displayTitle = hasTitle ? title : "Name your Stack"
            let titleFontSize = OnboardingEditableTitleMetrics.resolvedFontSize(
                for: displayTitle,
                availableWidth: proxy.size.width - 32
            )

            ZStack(alignment: .top) {
                Color.white

                ForEach(blobs) { blob in
                    PlaceholderProductBlob(blob: blob)
                        .matchedGeometryEffect(id: blob.id, in: namespace)
                        .frame(width: blob.width * scale, height: blob.height * scale)
                        .rotationEffect(.degrees(blob.rotation))
                        .position(
                            x: proxy.size.width * blob.x,
                            y: proxy.size.height * blob.y
                        )
                }

                // Keep the placeholder mounted after typing begins. Removing it
                // changes the ZStack's child identity and causes UIKit to discard
                // the active text field after the first character.
                ShimmeringStackTitle(text: "Name your Stack", fontSize: titleFontSize)
                    .opacity(hasTitle ? 0 : 1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, titleTopInset)
                    .allowsHitTesting(false)

                OnboardingStackTitleField(
                    text: $title,
                    fontSize: titleFontSize,
                    isVisible: hasTitle
                )
                    // Keep the editable masthead constrained to one line rather
                    // than allowing the input control to occupy the full canvas.
                    .frame(maxWidth: .infinity)
                    .frame(height: max(76, titleFontSize * 1.22))
                    .padding(.horizontal, 16)
                    .padding(.top, titleTopInset)
                    .accessibilityLabel("Name your Stack")
            }
            .clipShape(Rectangle())
        }
    }
}

private enum OnboardingEditableTitleMetrics {
    static let maximumFontSize = StackTitleTokens.stackTitleMaximumFontSize
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
        .accessibilityLabel("Name your Stack")
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
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = StackTitleTokens.stackTitleMinimumFontSize
        field.textAlignment = .center
        field.autocapitalizationType = .none
        field.autocorrectionType = .yes
        field.spellCheckingType = .yes
        field.keyboardType = .default
        field.returnKeyType = .done
        field.textContentType = nil
        field.clearButtonMode = .never
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = textColor
        field.tintColor = UIColor(Color.stacksInk)
        field.defaultTextAttributes = [
            .kern: fontSize * OnboardingEditableTitleMetrics.trackingRatio
        ]
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) { _text = text }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            text = current.replacingCharacters(in: swiftRange, with: string)
            return true
        }
    }
}

private struct StackPlaceholderBlob: Identifiable {
    static let featured = StackPlaceholderBlob(
        id: "featured-blob",
        imageName: "OnboardingTShirt",
        x: 0.27,
        y: 0.33,
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
                    TextField("Name your Stack", text: $title)
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
        ProductPlacement(asset: .coffeeMachine, x: 0.20, y: 0.22, width: 142, rotation: -4),
        ProductPlacement(asset: .foldingCrate, x: 0.64, y: 0.17, width: 146, rotation: 3),
        ProductPlacement(asset: .discoBall, x: 0.89, y: 0.18, width: 78, rotation: 7),
        ProductPlacement(asset: .stripedCup, x: 0.65, y: 0.38, width: 116, rotation: -4),
        ProductPlacement(asset: .blueLamp, x: 0.34, y: 0.46, width: 108, rotation: 6),
        ProductPlacement(asset: .orangeLamp, x: 0.20, y: 0.64, width: 122, rotation: -5),
        ProductPlacement(asset: .mokaPot, x: 0.84, y: 0.58, width: 104, rotation: 5),
        ProductPlacement(asset: .orangeChair, x: 0.33, y: 0.86, width: 148, rotation: -6)
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
    case keys = "OnboardingKeys"
    case tote = "OnboardingTote"
    case coffeeMachine = "HeroCoffeeMachine"
    case foldingCrate = "HeroFoldingCrate"
    case stripedCup = "HeroStripedCup"
    case orangeLamp = "HeroOrangeLamp"
    case mokaPot = "HeroMokaPot"
    case discoBall = "HeroDiscoBall"
    case blueLamp = "HeroBlueLamp"
    case orangeChair = "HeroOrangeChair"
    case blueBlanket = "HeroBlueBlanket"

    var accessibilityLabel: String {
        switch self {
        case .tShirt: "T-shirt"
        case .shorts: "Shorts"
        case .earrings: "Earrings"
        case .watch: "Watch"
        case .wine: "Wine bottle"
        case .wallet: "Leather pouch"
        case .sneaker: "Sneaker"
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
            [.coffeeMachine, .foldingCrate, .stripedCup, .orangeLamp, .mokaPot, .discoBall, .blueLamp, .orangeChair]
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
        case .sticker(.everySecond): 146
        case .sticker(.callMe): 136
        case .sticker(.pocketWatch): 92
        case .sticker(.blueCap): 114
        case .sticker(.vinyl): 88
        case .sticker(.nyApple): 132
        case .sticker(.eightBall): 88
        case .sticker(.brooklynBall): 94
        case .sticker(.lipstick): 88
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
        case .sticker(.everySecond): -4
        case .sticker(.callMe): 5
        case .sticker(.pocketWatch): -8
        case .sticker(.blueCap): 12
        case .sticker(.vinyl): -6
        case .sticker(.nyApple): 8
        case .sticker(.eightBall): -9
        case .sticker(.brooklynBall): 5
        case .sticker(.lipstick): -7
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

                        Button("Skip") {
                            onSkip()
                        }
                        .font(.stacksText(size: 16, weight: .semibold))
                        .foregroundStyle(Color.stacksMutedInk)
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

private struct SharedStackPreview: View {
    private let previewAssets = ["RunningSneaker", "RunningCap", "RunningHeadphones"]

    var body: some View {
        ZStack {
            AbstractShareBubbleShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.48, blue: 0.73),
                            Color(red: 0.16, green: 0.39, blue: 0.64)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    AbstractShareBubbleShape()
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.17), radius: 20, x: 0, y: 10)

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

                    Text("Run Club")
                        .font(.stacksMasthead(size: 21))
                        .tracking(-0.45)
                        .foregroundStyle(.white)
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
                    Text("stacks.app/owen/runclub")
                        .font(.stacksText(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 19)
            .padding(.top, 17)
            .padding(.bottom, 22)
        }
        .frame(height: 188)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 24)

                visual
                    .frame(maxWidth: .infinity)
                    .frame(height: visualHeight)
                    .padding(.horizontal, 10)
                    .padding(.top, isCompact ? 10 : 16)

                Spacer(minLength: 4)

                VStack(spacing: 12) {
                    PrimaryButton(title: primaryTitle, systemImage: "arrow.right", action: onPrimary)
                    Button("Skip") {
                        onSkip()
                    }
                    .font(.stacksText(size: 16, weight: .semibold))
                    .foregroundStyle(Color.stacksMutedInk)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        particles = (0 ..< copies).flatMap { copy in
            let copyOffset = CGFloat(copy) - CGFloat(copies - 1) / 2
            let copyScale = max(0.66, 1 - CGFloat(copy) * 0.10)
            let cannon = CGPoint(
                x: size.width * 0.5,
                y: size.height * 0.5
            )

            return definitions.enumerated().map { index, definition in
                let indexOffset = CGFloat(index - 4)
                let angle = (CGFloat(index) / CGFloat(max(1, definitions.count))) * .pi * 2
                    - .pi / 2
                    + copyOffset * 0.16
                let speed = 640 + CGFloat(index % 3) * 90 + abs(copyOffset) * 70
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

                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.stacksInk)
                    .position(x: previewSize.width * 0.09, y: previewSize.height * 0.10)

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
