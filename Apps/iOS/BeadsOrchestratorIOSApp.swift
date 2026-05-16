import SwiftUI

@main
struct BeadsOrchestratorIOSApp: App {
    @StateObject private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
