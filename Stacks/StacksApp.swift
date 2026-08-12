import SwiftUI

@main
struct StacksApp: App {
    @State private var session = AppSession(services: .mock())

    init() {
        StacksFontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.appServices, session.services)
        }
    }
}
