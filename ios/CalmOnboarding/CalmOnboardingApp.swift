import SwiftUI

@main
struct CalmOnboardingApp: App {
    @AppStorage("hasAuthenticated") private var hasAuthenticated = false

    var body: some Scene {
        WindowGroup {
            if hasAuthenticated && SessionTokenStore.load() != nil {
                RegisteredHomeView()
            } else {
                OnboardingScreen()
            }
        }
    }
}
