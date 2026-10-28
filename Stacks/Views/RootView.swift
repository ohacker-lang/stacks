import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Namespace private var stackTransition
    @Namespace private var productTransition

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-save-anywhere") {
                OnboardingView()
            } else if ProcessInfo.processInfo.arguments.contains("-preview-product") {
                NavigationStack {
                    ProductDetailView(
                        item: stackTitlePreview.items[0],
                        sourceStack: stackTitlePreview,
                        productTransition: productTransition
                    )
                }
            } else if ProcessInfo.processInfo.arguments.contains("-preview-stack") {
                NavigationStack {
                StackDetailView(
                    stack: stackTitlePreview,
                    stackTransition: stackTransition,
                    productTransition: productTransition
                ) { _, _ in }
                }
            } else {
                appContent
            }
#else
            appContent
#endif
        }
        .task {
#if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("-preview-save-anywhere"),
                  !ProcessInfo.processInfo.arguments.contains("-preview-stack"),
                  !ProcessInfo.processInfo.arguments.contains("-preview-product") else { return }
#endif
            if session.state == .launching {
                await session.restore()
            }
        }
    }

#if DEBUG
    private var stackTitlePreview: Stack {
        var stack = MockSeedData().myStacks[0]
        stack.title = "Knots of Anxiety"
        return stack
    }
#endif

    @ViewBuilder
    private var appContent: some View {
        Group {
            switch session.state {
            case .launching:
                LaunchView()
            case .signedOut, .onboarding:
                OnboardingView()
            case .signedIn:
                AppShellView()
                    .dismissKeyboardOnTap()
            }
        }
    }
}

private struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
    }
}

private extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Stacks")
                    .font(.stacksHeader(size: 54))
                    .tracking(-1.5)
                    .foregroundStyle(Color.stacksInk)

                ProgressView()
                    .tint(Color.stacksInk)

                Text("Getting things ready…")
                    .font(.stacksText(size: 14, weight: .regular))
                    .foregroundStyle(Color.stacksMutedInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Stacks is loading")
        }
    }
}
