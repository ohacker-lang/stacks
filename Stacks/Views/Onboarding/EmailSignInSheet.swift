import SwiftUI

enum EmailSignInOutcome {
    case signedIn
    case codeSent
    case failed(String?)
}

/// Email sign-in in two steps: send a link and code, then either tap the link
/// on this iPhone or type the code. The code covers mail apps whose own
/// browser won't hand the link back to Stacks, and reading mail elsewhere.
struct EmailSignInSheet: View {
    private enum Step: Equatable {
        case email
        case code(String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.email
    @State private var email = ""
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var didFinish = false
    @State private var errorMessage: String?
    @State private var resendNotice: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, code
    }

    let onSubmit: (String) async -> EmailSignInOutcome
    let onVerifyCode: (String, String) async -> String?
    let onCancel: () -> Void

    private var canSubmitEmail: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    private var codeDigits: String {
        code.filter(\.isNumber)
    }

    private var canSubmitCode: Bool {
        (6...10).contains(codeDigits.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            switch step {
            case .email:
                emailStep
            case .code(let sentTo):
                codeStep(sentTo: sentTo)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.stacksText(size: 13, weight: .medium))
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .presentationDetents([step == .email ? .height(errorMessage == nil ? 194 : 228) : .height(370)])
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                focusedField = .email
            }
        }
        .onDisappear {
            focusedField = nil
            guard !didFinish else { return }
            onCancel()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                if case .code = step {
                    withAnimation { step = .email }
                    code = ""
                    errorMessage = nil
                    resendNotice = nil
                    focusedField = .email
                } else {
                    cancel()
                }
            } label: {
                Image(systemName: step == .email ? "xmark" : "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.stacksInk.opacity(0.07), in: Circle())
            }
            .foregroundStyle(Color.stacksInk)
            .accessibilityLabel(step == .email ? "Close" : "Use a different email")

            Spacer()

            Text(step == .email ? "Continue with Email" : "Check your email")
                .font(.stacksText(size: 17, weight: .semibold))
                .foregroundStyle(Color.stacksInk)

            Spacer()

            Color.clear
                .frame(width: 36, height: 36)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
    }

    private var emailStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Email", text: $email)
                    .font(.stacksText(size: 17, weight: .regular))
                    .foregroundStyle(Color.stacksInk)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.continue)
                    .focused($focusedField, equals: .email)
                    .onSubmit { submitEmail() }
                    .onChange(of: email) { errorMessage = nil }

                Button(action: submitEmail) {
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
                .disabled(!canSubmitEmail || isSubmitting)
                .opacity(canSubmitEmail || isSubmitting ? 1 : 0.34)
                .accessibilityLabel(isSubmitting ? "Sending sign-in email" : "Continue")
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

            Text("We’ll email you a sign-in link and code.")
                .font(.stacksText(size: 13, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
                .padding(.top, 12)
                .onTapGesture {
                    focusedField = nil
                }
        }
    }

    private func codeStep(sentTo: String) -> some View {
        VStack(spacing: 0) {
            Text("We sent a link and a code to **\(sentTo)**. Tap the link on this iPhone, or enter the code here.")
                .font(.stacksText(size: 14, weight: .regular))
                .foregroundStyle(Color.stacksMutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            TextField("Code", text: $code)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.stacksInk)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .frame(height: 64)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                }
                .padding(.top, 18)
                .onChange(of: code) { oldValue, _ in
                    errorMessage = nil
                    if codeDigits.count > 10 {
                        code = String(codeDigits.prefix(10))
                    }
                    // A whole code arriving at once is AutoFill from Mail or
                    // a paste, so sign in without another tap.
                    let added = codeDigits.count - oldValue.filter(\.isNumber).count
                    if added >= 6, canSubmitCode {
                        submitCode(email: sentTo)
                    }
                }
                .accessibilityLabel("Sign-in code")

            PrimaryButton(title: "Sign in", isLoading: isSubmitting) {
                submitCode(email: sentTo)
            }
            .disabled(!canSubmitCode || isSubmitting)
            .opacity(canSubmitCode || isSubmitting ? 1 : 0.4)
            .padding(.top, 14)

            Button {
                resend(to: sentTo)
            } label: {
                Text(resendNotice ?? "Send a new code")
                    .font(.stacksText(size: 14, weight: .medium))
                    .foregroundStyle(Color.stacksMutedInk)
                    .frame(height: 36)
            }
            .disabled(isSubmitting || resendNotice != nil)
            .padding(.top, 6)
        }
    }

    private func submitEmail() {
        guard canSubmitEmail, !isSubmitting else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        errorMessage = nil
        Task {
            let outcome = await onSubmit(address)
            isSubmitting = false
            switch outcome {
            case .signedIn:
                didFinish = true
                dismiss()
            case .codeSent:
                withAnimation { step = .code(address) }
                focusedField = .code
            case .failed(let message):
                errorMessage = message ?? "We couldn’t send the email. Please try again."
            }
        }
    }

    private func submitCode(email: String) {
        guard canSubmitCode, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            let message = await onVerifyCode(codeDigits, email)
            isSubmitting = false
            if let message {
                errorMessage = message
            } else {
                didFinish = true
                dismiss()
            }
        }
    }

    private func resend(to email: String) {
        isSubmitting = true
        errorMessage = nil
        Task {
            let outcome = await onSubmit(email)
            isSubmitting = false
            switch outcome {
            case .signedIn:
                didFinish = true
                dismiss()
            case .codeSent:
                code = ""
                resendNotice = "New code sent"
            case .failed(let message):
                errorMessage = message ?? "We couldn’t send the email. Please try again."
            }
        }
    }

    private func cancel() {
        didFinish = true
        onCancel()
        dismiss()
    }
}
