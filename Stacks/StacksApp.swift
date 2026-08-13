import SwiftUI

@main
struct StacksApp: App {
    @State private var session = AppSession(services: .configured())

    init() {
        StacksFontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.appServices, session.services)
                .onOpenURL { url in
                    Task { await session.handleIncomingURL(url) }
                }
        }
    }
}
