import SwiftUI

@main
struct HomeyDevWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchRootView()
            }
            .environment(store)
            .tint(Watch.accent)
            .task { store.activate() }
        }
    }
}
