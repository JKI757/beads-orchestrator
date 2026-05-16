import SwiftUI

@main
struct BeadsOrchestratorMacApp: App {
    @StateObject private var store: BoardStore
    @StateObject private var server: BeadsHTTPServer

    init() {
        let store = BoardStore()
        let server = BeadsHTTPServer()
        server.configure(store: store)
        server.start()
        _store = StateObject(wrappedValue: store)
        _server = StateObject(wrappedValue: server)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(server)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
        }
    }
}
