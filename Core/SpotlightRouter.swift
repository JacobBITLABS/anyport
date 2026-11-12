import Foundation
import AppKit
import CoreSpotlight
import SwiftUI

@MainActor
final class SpotlightRouter: ObservableObject {
    @Published var pendingAlias: String?
    @Published var pendingTarget: ConnectTarget = .terminal
    @Published var pendingPort: String?

    func handleSelection(alias: String) {
        pendingAlias = alias
    }

    func clear() {
        pendingAlias = nil
        pendingTarget = .terminal
        pendingPort = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var connectWindow: NSWindow?
    private var isShowingMenu = false

    let store = SSHConfigStore()
    let orderManager = HostOrderManager()
    let spotlightRouter = SpotlightRouter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let statusIcon = NSImage(named: "StatusBarIcon")
            statusIcon?.isTemplate = true
            button.image = statusIcon
                ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "SSH Port Bar")
            button.setAccessibilityLabel("SSH Port Bar")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        // Debug: `-PersistentPopover` keeps the popover open (visual QA — no outside-click dismissal).
        if ProcessInfo.processInfo.arguments.contains("-PersistentPopover") {
            popover.behavior = .applicationDefined
        }
        popover.contentSize = NSSize(width: 360, height: 500)
        // Debug: `-TallPopover` raises the popover for full-list visual QA.
        if ProcessInfo.processInfo.arguments.contains("-TallPopover") {
            popover.contentSize = NSSize(width: 360, height: 860)
        }
        popover.contentViewController = NSHostingController(
            rootView: ContentView(
                store: store,
                orderManager: orderManager,
                spotlightRouter: spotlightRouter
            )
        )

        store.loadHosts()
        SpotlightIndexer.reindexHosts(store.hosts)

        // Debug: `-ShowPopoverOnLaunch` opens the popover automatically (used for visual QA).
        if ProcessInfo.processInfo.arguments.contains("-ShowPopoverOnLaunch"),
           let button = statusItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.togglePopover(button)
            }
        }
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if isShowingMenu { return }

        let event = NSApp.currentEvent
        let isControlClick = event?.modifierFlags.contains(.control) ?? false
        let isRightClick = event?.type == .rightMouseUp

        if isControlClick || isRightClick {
            if popover.isShown {
                popover.performClose(sender)
            }
            showQuitMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func showQuitMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit SSHPortBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        isShowingMenu = true
        statusItem.menu = menu
        sender.performClick(nil)
        DispatchQueue.main.async {
            self.statusItem.menu = nil
            self.isShowingMenu = false
        }
    }

    private func togglePopover(_ sender: AnyObject) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openConnectWindow() {
        guard let alias = spotlightRouter.pendingAlias,
              let host = store.hosts.first(where: { $0.alias == alias }) else { return }

        connectWindow?.close()

        let hostingController = NSHostingController(
            rootView: SpotlightConnectView(
                host: host,
                store: store,
                orderManager: orderManager,
                onDismiss: { [weak self] in
                    self?.connectWindow?.close()
                }
            )
        )

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.center()
        connectWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func application(_ application: NSApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let alias = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return false }

        handleSpotlightSelection(alias: alias)
        return true
    }

    /// Connects to a host picked in macOS Spotlight. Lives here (not in the
    /// popover's SwiftUI tree) so it works even while the popover is closed —
    /// and when Spotlight launches the app cold.
    private func handleSpotlightSelection(alias: String) {
        if store.hosts.isEmpty {
            store.loadHosts()
        }

        guard let host = store.hosts.first(where: { $0.alias == alias }) else { return }

        let portModeKey = "port_mode_\(alias)"
        let isAdaptive = UserDefaults.standard.string(forKey: portModeKey) == "adaptive"

        spotlightRouter.pendingAlias = alias

        if isAdaptive {
            openConnectWindow()
        } else {
            let port = host.port ?? "22"
            try? store.updatePort(alias: alias, port: port)
            orderManager.recordVisit(alias: alias)

            let defaultTerminal = UserDefaults.standard.string(forKey: "default_terminal") ?? "terminal"
            switch defaultTerminal {
            case "iterm":
                _ = Connector.openInITerm(alias: alias)
            case "vscode":
                let pathKey = "vscode_path_\(alias)"
                let remotePath = UserDefaults.standard.string(forKey: pathKey) ?? "~"
                _ = Connector.openInVSCode(alias: alias, remotePath: remotePath)
            default:
                _ = Connector.openInTerminal(alias: alias)
            }
        }
    }
}
