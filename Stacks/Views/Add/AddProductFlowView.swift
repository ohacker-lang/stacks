import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class AddProductFlowViewModel {
    enum Stage: Equatable {
        case sourcePicker
        case camera
        case photoLibrary
        case linkImport
        case processing
        case editing
        case stackPicker
        case complete
    }

    var stage: Stage = .camera
    var capturedImageData: Data?
}

struct AddProductFlowView: View {
    @State private var viewModel = AddProductFlowViewModel()
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var isShowingFallback = false
    @State private var isShowingPhotoReview = false
    @State private var isShowingLinkImport = false
    @State private var cameraExit: CameraExit?

    let user: UserProfile
    let onComplete: (Stack) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if isShowingCamera {
                ProductCameraCaptureView(
                    onCapture: { data in
                        viewModel.capturedImageData = data
                        viewModel.stage = .processing
                        closeCamera(with: .photoReview)
                    },
                    onPasteLink: {
                        viewModel.stage = .linkImport
                        closeCamera(with: .linkImport)
                    },
                    onChooseFromLibrary: {
                        viewModel.stage = .photoLibrary
                        closeCamera(with: .photoLibrary)
                    },
                    onCancel: {
                        closeCamera(with: .cancel)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(1)
            }
        }
        .task {
            openCamera()
        }
        .fullScreenCover(isPresented: $isShowingPhotoLibrary, onDismiss: continueAfterPhotoLibraryDismissal) {
            ProductPhotoLibraryPicker(
                onCapture: { data in
                    viewModel.capturedImageData = data
                    viewModel.stage = .editing
                    cameraExit = .photoReview
                    isShowingPhotoLibrary = false
                },
                onCancel: {
                    cameraExit = .camera
                    isShowingPhotoLibrary = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingFallback) {
            AddProductFallbackSheet(
                onPhoto: { data in
                    viewModel.capturedImageData = data
                    viewModel.stage = .processing
                    isShowingFallback = false
                    isShowingPhotoReview = true
                },
                onPasteLink: {
                    viewModel.stage = .linkImport
                    isShowingFallback = false
                    isShowingLinkImport = true
                },
                onCancel: onCancel
            )
            .presentationDetents([.height(248)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $isShowingPhotoReview, onDismiss: dismissIfUnfinished) {
            PhotoProductImportSheet(
                initialImageData: viewModel.capturedImageData,
                navigationTitle: "Add From Photo",
                user: user
            ) { stack in
                viewModel.stage = .complete
                onComplete(stack)
            }
        }
        .fullScreenCover(isPresented: $isShowingLinkImport, onDismiss: dismissIfUnfinished) {
            ProductLinkImportSheet(user: user) { stack in
                viewModel.stage = .complete
                onComplete(stack)
            }
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            viewModel.stage = .sourcePicker
            isShowingFallback = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isShowingCamera = true
                    } else {
                        viewModel.stage = .sourcePicker
                        isShowingFallback = true
                    }
                }
            }
        case .denied, .restricted:
            viewModel.stage = .sourcePicker
            isShowingFallback = true
        @unknown default:
            viewModel.stage = .sourcePicker
            isShowingFallback = true
        }
    }

    private func continueAfterCameraDismissal() {
        switch cameraExit {
        case .photoReview:
            viewModel.stage = .editing
            isShowingPhotoReview = true
        case .linkImport:
            isShowingLinkImport = true
        case .photoLibrary:
            isShowingPhotoLibrary = true
        case .camera:
            openCamera()
        case .cancel, nil:
            onCancel()
        }
        cameraExit = nil
    }

    private func closeCamera(with exit: CameraExit) {
        cameraExit = exit
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingCamera = false
        }
        DispatchQueue.main.async {
            continueAfterCameraDismissal()
        }
    }

    private func continueAfterPhotoLibraryDismissal() {
        switch cameraExit {
        case .photoReview:
            isShowingPhotoReview = true
        case .camera:
            openCamera()
        case .linkImport:
            isShowingLinkImport = true
        case .photoLibrary, .cancel, nil:
            onCancel()
        }
        cameraExit = nil
    }

    private func dismissIfUnfinished() {
        guard viewModel.stage != .complete else { return }
        onCancel()
    }
}

private enum CameraExit {
    case photoReview
    case linkImport
    case photoLibrary
    case camera
    case cancel
}

private struct AddProductFallbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    let onPhoto: (Data) -> Void
    let onPasteLink: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Add a product")
                .font(.stacksHeader(size: 21))
                .tracking(-0.25)

            PhotosPicker(selection: $photoItem, matching: .images) {
                AddProductActionRow(title: "Photos", systemImage: "photo.on.rectangle")
            }

            Button(action: onPasteLink) {
                AddProductActionRow(title: "Paste link", systemImage: "link")
            }
            .buttonStyle(.plain)

            Button("Cancel", role: .cancel) {
                dismiss()
                onCancel()
            }
            .font(.stacksText(size: 15))
        }
        .padding(20)
        .task(id: photoItem) {
            guard let photoItem,
                  let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            onPhoto(data)
        }
    }
}

struct ProductCameraCaptureView: View {
    let onCapture: (Data) -> Void
    let onPasteLink: () -> Void
    let onChooseFromLibrary: () -> Void
    let onCancel: () -> Void
    var onboardingHint: String? = nil
    @State private var camera = InlineCameraController()
    @State private var isUnavailable = false
    @State private var shutterFood = CameraShutterFruit.allCases.randomElement() ?? .strawberry

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 30, 410)
            let height = min(max(width * 1.28, 455), proxy.size.height - 72)

            ZStack {
                Color.black.opacity(0.07)
                    .ignoresSafeArea()

                ZStack {
                    InlineCameraPreview(session: camera.session)

                    if isUnavailable {
                        Color.black
                    }

                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .black.opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    cameraControls

                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 16)
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height - (height / 2) - max(2, proxy.safeAreaInsets.bottom - 14)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            camera.start(
                onCapture: onCapture,
                onUnavailable: { isUnavailable = true }
            )
        }
        .onDisappear { camera.stop() }
    }

    private var cameraControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CameraCardIconButton(systemImage: "xmark", accessibilityLabel: "Cancel", action: onCancel)

                Spacer(minLength: 0)

                if let onboardingHint {
                    HStack(spacing: 7) {
                        Text(onboardingHint)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.stacksText(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(0.24), lineWidth: 1)
                        }
                }

                Menu {
                    Button("Choose from Photos", systemImage: "photo.on.rectangle", action: onChooseFromLibrary)
                    Button("Paste product link", systemImage: "link", action: onPasteLink)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                        }
                }
                .accessibilityLabel("More ways to add")
            }
            .padding(.horizontal, 17)
            .padding(.top, 18)

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Color.clear.frame(width: 46, height: 46)

                Spacer(minLength: 0)

                Button {
                    camera.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.96))

                        Image(shutterFood.rawValue)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 74, height: 74)
                            .clipShape(Circle())
                    }
                    .frame(width: 82, height: 82)
                    .overlay {
                        Circle().stroke(.white.opacity(0.92), lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.26), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take photo with \(shutterFood.accessibilityName) shutter")

                Spacer(minLength: 0)

                Color.clear.frame(width: 46, height: 46)
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 19)
        }
    }

}

private struct CameraCardIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct InlineCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> InlineCameraPreviewView {
        let view = InlineCameraPreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: InlineCameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class InlineCameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("InlineCameraPreviewView must use AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class InlineCameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.stacks.inline-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureHandler: ((Data) -> Void)?
    private var unavailableHandler: (() -> Void)?

    func start(onCapture: @escaping (Data) -> Void, onUnavailable: @escaping () -> Void) {
        captureHandler = onCapture
        unavailableHandler = onUnavailable

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                granted ? self?.startSession() : self?.reportUnavailable()
            }
        case .denied, .restricted:
            reportUnavailable()
        @unknown default:
            reportUnavailable()
        }
    }

    func capturePhoto() {
        queue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func stop() {
        queue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.configureSessionIfNeeded() else {
                self.reportUnavailable()
                return
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func configureSessionIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            return false
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        isConfigured = true
        return true
    }

    private func reportUnavailable() {
        DispatchQueue.main.async { [unavailableHandler] in
            unavailableHandler?()
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { [captureHandler] in
            captureHandler?(data)
        }
    }
}

struct ProductPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancel()
                return
            }

            let imageType = UTType.image.identifier
            guard result.itemProvider.hasItemConformingToTypeIdentifier(imageType) else {
                onCancel()
                return
            }

            result.itemProvider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                guard let data else {
                    DispatchQueue.main.async { self.onCancel() }
                    return
                }
                DispatchQueue.main.async { self.onCapture(data) }
            }
        }
    }
}

private final class CameraOverlayView: UIView {
    private let onCancel: () -> Void
    private let onShutter: () -> Void
    private let onPhotos: () -> Void
    private let onPasteLink: () -> Void
    private let onboardingHint: String?

    private let cancelButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .system)
    private let photosButton = UIButton(type: .system)
    private let logoView = UIImageView(image: UIImage(named: "StacksLogo")?.withRenderingMode(.alwaysTemplate))
    private let onboardingHintView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let onboardingHintLabel = UILabel()

    init(
        onCancel: @escaping () -> Void,
        onShutter: @escaping () -> Void,
        onPhotos: @escaping () -> Void,
        onPasteLink: @escaping () -> Void,
        onboardingHint: String? = nil
    ) {
        self.onCancel = onCancel
        self.onShutter = onShutter
        self.onPhotos = onPhotos
        self.onPasteLink = onPasteLink
        self.onboardingHint = onboardingHint
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        configureControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let top = max(safeAreaInsets.top, 16) + 18
        cancelButton.frame = CGRect(x: 22, y: top, width: 48, height: 48)
        moreButton.frame = CGRect(x: bounds.width - 70, y: top, width: 48, height: 48)
        onboardingHintView.frame = CGRect(x: max(86, bounds.width - 254), y: top + 3, width: 170, height: 42)
        onboardingHintLabel.frame = onboardingHintView.bounds.insetBy(dx: 12, dy: 6)

        // Center the mark below the action line so it stays clear of the
        // Dynamic Island and never clips at the top of the camera preview.
        logoView.frame = CGRect(x: (bounds.width - 56) / 2, y: top + 34, width: 56, height: 56)

        let bottom = max(safeAreaInsets.bottom, 28) + 38
        shutterButton.frame = CGRect(x: (bounds.width - 92) / 2, y: bounds.height - bottom - 92, width: 92, height: 92)
        photosButton.frame = CGRect(x: bounds.width - 70, y: bounds.height - bottom - 70, width: 48, height: 48)
    }

    private func configureControls() {
        configureRoundButton(cancelButton, image: "xmark", accessibilityLabel: "Cancel")
        configureRoundButton(moreButton, image: "plus", accessibilityLabel: "More ways to add a product")
        configureRoundButton(photosButton, image: "photo.on.rectangle", accessibilityLabel: "Choose from Camera Roll")

        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        photosButton.addTarget(self, action: #selector(didTapPhotos), for: .touchUpInside)

        moreButton.menu = UIMenu(children: [
            UIAction(title: "Choose from Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
                self?.onPhotos()
            },
            UIAction(title: "Paste product link", image: UIImage(systemName: "link")) { [weak self] _ in
                self?.onPasteLink()
            }
        ])
        moreButton.showsMenuAsPrimaryAction = true

        let fruit = CameraShutterFruit.allCases.randomElement() ?? .strawberry
        shutterButton.setImage(UIImage(named: fruit.rawValue)?.withRenderingMode(.alwaysOriginal), for: .normal)
        shutterButton.imageView?.contentMode = .scaleAspectFill
        shutterButton.imageView?.clipsToBounds = true
        shutterButton.tintColor = .clear
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 46
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        shutterButton.layer.borderWidth = 3
        shutterButton.layer.shadowColor = UIColor.black.cgColor
        shutterButton.layer.shadowOpacity = 0.32
        shutterButton.layer.shadowRadius = 12
        shutterButton.layer.shadowOffset = CGSize(width: 0, height: 7)
        shutterButton.clipsToBounds = true
        shutterButton.accessibilityLabel = "Take photo with (fruit.accessibilityName) shutter"
        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)

        logoView.contentMode = .scaleAspectFit
        logoView.tintColor = .white
        logoView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        logoView.layer.cornerRadius = 17
        logoView.layer.borderColor = UIColor.white.withAlphaComponent(0.34).cgColor
        logoView.layer.borderWidth = 1
        logoView.layer.shadowColor = UIColor.black.cgColor
        logoView.layer.shadowOpacity = 0.35
        logoView.layer.shadowRadius = 12
        logoView.layer.shadowOffset = CGSize(width: 0, height: 5)
        logoView.clipsToBounds = true
        logoView.isAccessibilityElement = false

        onboardingHintView.layer.cornerRadius = 18
        onboardingHintView.clipsToBounds = true
        onboardingHintView.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        onboardingHintView.layer.borderWidth = 1
        onboardingHintView.layer.shadowColor = UIColor.black.cgColor
        onboardingHintView.layer.shadowOpacity = 0.26
        onboardingHintView.layer.shadowRadius = 12
        onboardingHintView.layer.shadowOffset = CGSize(width: 0, height: 5)
        onboardingHintView.isHidden = onboardingHint == nil

        onboardingHintLabel.text = onboardingHint
        onboardingHintLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        onboardingHintLabel.textColor = .white
        onboardingHintLabel.textAlignment = .center
        onboardingHintLabel.numberOfLines = 1
        onboardingHintView.contentView.addSubview(onboardingHintLabel)

        [cancelButton, moreButton, shutterButton, photosButton, logoView, onboardingHintView].forEach(addSubview)
    }

    private func configureRoundButton(_ button: UIButton, image: String, accessibilityLabel: String) {
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        button.layer.cornerRadius = 24
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        button.layer.borderWidth = 1
        button.accessibilityLabel = accessibilityLabel
    }

    @objc private func didTapCancel() { onCancel() }
    @objc private func didTapShutter() { onShutter() }
    @objc private func didTapPhotos() { onPhotos() }
}

private enum CameraShutterFruit: String, CaseIterable {
    case strawberry = "FruitStrawberry"
    case kiwi = "FruitKiwi"
    case orange = "FruitOrange"
    case pomegranate = "FruitPomegranate"
    case dragonFruit = "FruitDragon"
    case lime = "FruitLime"
    case papaya = "FruitPapaya"
    case peach = "FruitPeach"
    case watermelon = "FruitWatermelon"
    case lemon = "FruitLemon"
    case grapefruit = "FruitGrapefruit"
    case blueberry = "FruitBlueberry"
    case plum = "FruitPlum"
    case coconut = "FruitCoconut"
    case pineapple = "FruitPineapple"

    var accessibilityName: String {
        switch self {
        case .dragonFruit: "dragon fruit"
        default: rawValue.replacingOccurrences(of: "Fruit", with: "").lowercased()
        }
    }
}

private struct AddProductActionRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.stacksHeader(size: 17))
            .tracking(-0.2)
            .foregroundStyle(Color.stacksInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .stacksGlass(cornerRadius: 18, interactive: true)
    }
}
