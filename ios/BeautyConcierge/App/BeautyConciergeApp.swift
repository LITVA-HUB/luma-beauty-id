import SwiftUI

@main
struct BeautyConciergeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .task { await appState.boot() }
        }
    }
}
