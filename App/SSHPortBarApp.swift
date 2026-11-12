import SwiftUI
import AppKit
import CoreSpotlight

@main
struct AnyPortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: SSHConfigStore
    @ObservedObject var orderManager: HostOrderManager
    @ObservedObject var spotlightRouter: SpotlightRouter
    @State private var searchText = ""
    @State private var selectedHost: SSHHost?

    var body: some View {
        NavigationStack {
            HostListView(store: store, orderManager: orderManager, searchText: $searchText, selectedHost: $selectedHost)
                .navigationDestination(item: $selectedHost) { host in
                    HostEditorView(host: host, store: store, orderManager: orderManager)
                }
        }
        .frame(width: 360, height: ProcessInfo.processInfo.arguments.contains("-TallPopover") ? 860 : 500)
        .onAppear {
            store.loadHosts()
            SpotlightIndexer.reindexHosts(store.hosts)
            // Debug: `-ShowEditorOnLaunch` pushes the first host's editor (visual QA).
            if ProcessInfo.processInfo.arguments.contains("-ShowEditorOnLaunch") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    selectedHost = store.hosts.first
                }
            }
        }
    }
}
