import SwiftUI

struct EmailSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isSubmitting = false
    @State private var didFinish = false
    @FocusState private var isEmailFocused: Bool

    let onSubmit: (String) async -> Void
    let onCancel: () -> Void

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.stacksInk.opacity(0.07), in: Circle())
                }
                .foregroundStyle(Color.stacksInk)

                Spacer()

                Text("Continue with Email")
                    .font(.stacksText(size: 17, weight: .semibold))
                    .foregroundStyle(Color.stacksInk)

                Spacer()

                Color.clear
                    .frame(width: 36, height: 36)
            }

            HStack(spacing: 10) {
                TextField("Email", text: $email)
                    .font(.stacksText(size: 17, weight: .regular))
                    .foregroundStyle(Color.stacksInk)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.continue)
                    .focused($isEmailFocused)
                    .onSubmit { submit() }

                Button(action: submit) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white)
                    .background(Color.stacksInk, in: Circle())
                }
                .disabled(!canSubmit || isSubmitting)
                .opacity(canSubmit || isSubmitting ? 1 : 0.34)
                .accessibilityLabel(isSubmitting ? "Sending sign-in link" : "Continue")
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 58)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
            }
            .padding(.top, 22)

            Text("We’ll send you a secure sign-in link.")
                .font(.stacksText(size: 13, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isEmailFocused = true
            }
        }
        .onDisappear {
            guard !didFinish else { return }
            onCancel()
        }
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await onSubmit(email.trimmingCharacters(in: .whitespacesAndNewlines))
            isSubmitting = false
            didFinish = true
            dismiss()
        }
    }

    private func cancel() {
        didFinish = true
        onCancel()
        dismiss()
    }
}
