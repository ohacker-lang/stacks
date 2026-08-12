import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Namespace private var stackTransition
    @Namespace private var productTransition

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-product") {
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
            guard !ProcessInfo.processInfo.arguments.contains("-preview-stack"),
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
            }
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        Color.white.ignoresSafeArea()
    }
}
