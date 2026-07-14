import SwiftUI
import AppKit

@main
struct AnyPortApp: App {
    @StateObject private var store = SSHConfigStore()
    @StateObject private var orderManager = HostOrderManager()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store, orderManager: orderManager)
        } label: {
            Image(systemName: "terminal.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var store: SSHConfigStore
    @ObservedObject var orderManager: HostOrderManager
    @State private var searchText = ""
    @State private var selectedHost: SSHHost?

    var body: some View {
        NavigationStack {
            HostListView(store: store, orderManager: orderManager, searchText: $searchText, selectedHost: $selectedHost)
                .navigationDestination(item: $selectedHost) { host in
                    HostEditorView(host: host, store: store, orderManager: orderManager)
                }
        }
        .frame(width: 360, height: 500)
        .onAppear {
            store.loadHosts()
        }
    }
}
