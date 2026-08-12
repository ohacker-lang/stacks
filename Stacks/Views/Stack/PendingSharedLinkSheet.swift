import SwiftUI

struct PendingSharedLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    @State private var stacks: [Stack] = []
    @State private var selectedStack: Stack?
    @State private var newStackTitle = ""
    @State private var newStackWishlistMode = false
    @State private var isLoadingStacks = true
    @State private var isCreatingStack = false
    @State private var isPresentingNewStack = false
    @State private var isPresentingDiscardConfirmation = false
    @State private var errorMessage: String?

    let link: PendingSharedLink
    let user: UserProfile
    let onSaved: (Stack) -> Void
    let onDeferred: () -> Void
    let onDiscarded: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What do you want to do with this link?")
                            .font(.stacksHeader(size: 22))
                            .tracking(-0.4)
                            .foregroundStyle(Color.stacksInk)

                        Text("Choose where to put it before continuing.")
                            .font(.stacksText(size: 15, weight: .regular))
                            .foregroundStyle(Color.stacksMutedInk)
                            .padding(.bottom, 8)

                        Text(link.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? link.title! : link.url.host ?? "Shared link")
                            .font(.stacksText(size: 17))
                            .foregroundStyle(Color.stacksInk)
                            .lineLimit(2)
                        Text(link.url.host ?? link.url.absoluteString)
                            .font(.stacksText(size: 14))
                            .foregroundStyle(Color.stacksMutedInk)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }

                Section("Add to a Stack") {
                    if isLoadingStacks {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading your Stacks")
                                .font(.stacksText(size: 16))
                        }
                    } else {
                        ForEach(stacks) { stack in
                            Button {
                                selectedStack = stack
                            } label: {
                                HStack {
                                    Text(stack.displayTitle)
                                        .font(.stacksText(size: 18))
                                        .foregroundStyle(Color.stacksInk)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(Color.stacksMutedInk)
                                }
                            }
                        }

                        Button {
                            isPresentingNewStack = true
                        } label: {
                            Label("New Stack", systemImage: "plus")
                                .font(.stacksText(size: 17))
                        }
                    }
                }
            }
            .navigationTitle("Shared Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isPresentingDiscardConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Discard shared link")
                }
            }
            .task {
                await loadStacks()
            }
            .sheet(isPresented: $isPresentingNewStack) {
                newStackSheet
            }
            .confirmationDialog("Discard this shared link?", isPresented: $isPresentingDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Link", role: .destructive) {
                    PendingSharedLinkStore.remove(link)
                    onDiscarded()
                    dismiss()
                }
            } message: {
                Text("This removes the link from your pending Stacks imports.")
            }
            .alert("Could not create Stack", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .fullScreenCover(item: $selectedStack) { stack in
            ProductLinkImportSheet(
                initialURL: link.url,
                user: user,
                preferredStack: stack,
                locksDestination: true
            ) { savedStack in
                PendingSharedLinkStore.remove(link)
                onSaved(savedStack)
                dismiss()
            }
        }
    }

    private var newStackSheet: some View {
        NavigationStack {
            Form {
                Section("Stack") {
                    TextField("Title", text: $newStackTitle)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                    Toggle("Wishlist mode", isOn: $newStackWishlistMode)
                }
            }
            .navigationTitle("New Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresentingNewStack = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createStack()
                    }
                    .disabled(isCreatingStack || newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func loadStacks() async {
        isLoadingStacks = true
        defer { isLoadingStacks = false }
        do {
            let loadedStacks = try await services.stacks.fetchMyStacks(for: user.id)
            stacks = loadedStacks.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createStack() {
        guard !isCreatingStack else { return }
        isCreatingStack = true
        let title = newStackTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            defer { isCreatingStack = false }
            do {
                let stack = try await services.stacks.createStack(
                    title: title,
                    wishlistMode: newStackWishlistMode,
                    owner: user
                )
                services.haptics.notification(.success)
                isPresentingNewStack = false
                selectedStack = stack
            } catch {
                errorMessage = error.localizedDescription
                services.haptics.notification(.error)
            }
        }
    }
}
