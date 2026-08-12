import SwiftUI
import UIKit

/// An editorial product page for a single saved sticker. The source Stack is
/// carried through navigation so saving to another Stack is a real copy action.
struct ProductDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss

    let item: StackItem
    let sourceStack: Stack
    let productTransition: Namespace.ID
    let onBack: (() -> Void)?

    @State private var isShowingDestinationPicker = false
    @State private var didCopyLink = false
    @State private var saveMessage: String?

    init(
        item: StackItem,
        sourceStack: Stack,
        productTransition: Namespace.ID,
        onBack: (() -> Void)? = nil
    ) {
        self.item = item
        self.sourceStack = sourceStack
        self.productTransition = productTransition
        self.onBack = onBack
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ProductStickerStage(item: item)
                        .padding(.top, 76)

                    VStack(spacing: 10) {
                        ProductPageTitle(text: item.title)

                        ProductDescription(item: item)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 25)

                    ProductInformation(item: item)
                        .padding(.horizontal, 24)
                        .padding(.top, 26)
                        .padding(.bottom, 26)
                }
            }

            ProductNavigationBar(
                onBack: goBack,
                shareURL: item.purchaseURL,
                onAddToAnotherStack: { isShowingDestinationPicker = true },
                onCopyLink: copyLink
            )
        }
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .navigationTransition(.zoom(sourceID: item.id, in: productTransition))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Link(destination: item.purchaseURL) {
                ProductBuyButton(price: item.formattedPrice)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(height: 1)
            }
        }
        .sheet(isPresented: $isShowingDestinationPicker) {
            if let user = session.currentUser {
                ProductDestinationPicker(
                    item: item,
                    sourceStack: sourceStack,
                    user: user,
                    onSaved: { destination in
                        saveMessage = "Saved to \(destination.displayTitle)"
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                ContentUnavailableView("Sign in required", systemImage: "person.crop.circle")
                    .presentationDetents([.medium])
            }
        }
        .alert("Link Copied", isPresented: $didCopyLink) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("The product link is ready to paste.")
        }
        .alert("Saved", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
    }

    private func copyLink() {
        UIPasteboard.general.url = item.purchaseURL
        services.haptics.notification(.success)
        didCopyLink = true
    }

    private func goBack() {
        services.haptics.impact(.light)
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }
}

private struct ProductPageTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.stacksMasthead(size: 56))
            .tracking(-1.8)
            // Reserve only one line when possible. The former 2...4 range
            // kept a blank title line even for short product names.
            .lineLimit(1...2)
            .minimumScaleFactor(0.62)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.stacksInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct ProductStickerStage: View {
    let item: StackItem

    var body: some View {
        StickerImageView(item: item, size: 350)
            .rotationEffect(.degrees(item.placement.rotationDegrees))
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .padding(.horizontal, 12)
    }
}

private struct ProductNavigationBar: View {
    let onBack: () -> Void
    let shareURL: URL
    let onAddToAnotherStack: () -> Void
    let onCopyLink: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.stacksInk.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("product-detail-back")

            Spacer()

            Menu {
                ShareLink(item: shareURL) {
                    Label("Share Product", systemImage: "square.and.arrow.up")
                }

                Button(action: onAddToAnotherStack) {
                    Label("Add to Another Stack", systemImage: "square.stack.3d.up")
                }

                Button(action: onCopyLink) {
                    Label("Copy Product Link", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)
                    .frame(width: 40, height: 40)
                    .stacksGlass(cornerRadius: 20, interactive: true)
            }
            .accessibilityLabel("Product options")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .zIndex(2)
    }
}

private struct ProductDescription: View {
    let item: StackItem

    private var text: String {
        let description = item.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { return description }
        if !item.brand.isEmpty { return "Saved from \(item.brand)." }
        return "A saved find from your Stack."
    }

    var body: some View {
        Text(text)
            .font(.stacksOnboardingSerif(size: 24))
            .tracking(-0.15)
            .foregroundStyle(Color.stacksInk.opacity(0.72))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
    }
}

private struct ProductInformation: View {
    let item: StackItem

    var body: some View {
        HStack(spacing: 0) {
            ProductInfoCell(label: "Brand", value: item.brand.isEmpty ? "Saved item" : item.brand)
            Divider().frame(height: 36)
            ProductInfoCell(label: "Price", value: item.formattedPrice)
            Divider().frame(height: 36)
            ProductInfoCell(label: "Stack", value: "Saved")
        }
        .padding(.vertical, 16)
        .stacksGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 1)
        }
    }
}

private struct ProductInfoCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .default))
                .tracking(0.7)
                .foregroundStyle(Color.stacksMutedInk)
            Text(value)
                .font(.stacksText(size: 14, weight: .semibold))
                .foregroundStyle(Color.stacksInk)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProductBuyButton: View {
    let price: String

    var body: some View {
        HStack(spacing: 10) {
            Text("Buy")
            Spacer()
            Text(price)
        }
        .font(.stacksText(size: 18, weight: .semibold))
        .tracking(-0.25)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(height: 62)
        .background(Color.stacksInk, in: Capsule())
        .contentShape(Capsule())
    }
}

private struct ProductDestinationPicker: View {
    @Environment(\.appServices) private var services
    @Environment(\.dismiss) private var dismiss

    let item: StackItem
    let sourceStack: Stack
    let user: UserProfile
    let onSaved: (Stack) -> Void

    @State private var stacks: [Stack] = []
    @State private var errorMessage: String?
    @State private var savingID: UUID?

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
                        description: Text("You can save (item.title) there once it exists.")
                    )
                } else {
                    List(destinations) { destination in
                        Button {
                            Task { await save(item, to: destination) }
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
                                    Text("(destination.items.count) items")
                                        .font(.stacksText(size: 13, weight: .regular))
                                        .foregroundStyle(Color.stacksMutedInk)
                                }

                                Spacer()
                                if savingID == destination.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.stacksInk.opacity(0.54))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(savingID != nil)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Add to Stack")
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

    private func save(_ item: StackItem, to destination: Stack) async {
        savingID = destination.id
        let copiedItem = StackItem(
            id: UUID(),
            stackID: destination.id,
            title: item.title,
            brand: item.brand,
            shortDescription: item.shortDescription,
            price: item.price,
            currencyCode: item.currencyCode,
            sourceURL: item.sourceURL,
            buyURL: item.buyURL,
            affiliateURL: item.affiliateURL,
            originalImageURL: item.originalImageURL,
            removedBackgroundImageURL: item.removedBackgroundImageURL,
            removalStatus: item.removalStatus,
            placement: item.placement,
            hasCustomPlacement: item.hasCustomPlacement,
            addSource: item.addSource,
            claimStatus: item.claimStatus,
            demoGlyph: item.demoGlyph,
            isBookmarked: item.isBookmarked
        )

        do {
            _ = try await services.stacks.addItem(copiedItem, to: destination.id)
            services.haptics.notification(.success)
            onSaved(destination)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        savingID = nil
    }
}
