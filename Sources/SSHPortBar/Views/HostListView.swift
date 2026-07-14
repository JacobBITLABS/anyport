import SwiftUI
import AppKit

private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 42
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HostListView: View {
    @ObservedObject var store: SSHConfigStore
    @ObservedObject var orderManager: HostOrderManager
    @Binding var searchText: String
    @Binding var selectedHost: SSHHost?

    @State private var hoveredAlias: String?
    @State private var draggingAlias: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragSwapCount: Int = 0
    @State private var rowHeight: CGFloat = 42
    @State private var adaptiveHost: SSHHost?
    @State private var adaptivePortInput: String = ""
    @State private var pendingTarget: ConnectTarget?
    @State private var toastMessage: String?
    @State private var toastIsError = false

    private var pinnedHosts: [SSHHost] {
        let hosts = orderManager.sortedPinnedHosts(store.hosts)
        if searchText.isEmpty { return hosts }
        return hosts.filter { host in
            host.alias.localizedCaseInsensitiveContains(searchText)
                || (host.hostName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var unpinnedHosts: [SSHHost] {
        let hosts = orderManager.sortedUnpinnedHosts(store.hosts)
        if searchText.isEmpty { return hosts }
        return hosts.filter { host in
            host.alias.localizedCaseInsensitiveContains(searchText)
                || (host.hostName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var effectiveOffset: CGFloat {
        dragTranslation - CGFloat(dragSwapCount) * rowHeight
    }

    var body: some View {
        Group {
            if store.hosts.isEmpty && store.error == nil {
                ContentUnavailableView(
                    "No Hosts Found",
                    systemImage: "server.rack",
                    description: Text("Add SSH hosts to **~/.ssh/config** to see them here.")
                )
            } else if pinnedHosts.isEmpty && unpinnedHosts.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No hosts match \"\(searchText)\"")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !pinnedHosts.isEmpty {
                            sectionHeader("Pinned", icon: "pin.fill", color: .orange)

                            ForEach(pinnedHosts, id: \.id) { host in
                                pinnedRow(host)
                            }
                        }

                        if !unpinnedHosts.isEmpty {
                            if !pinnedHosts.isEmpty {
                                sectionHeader("Hosts", icon: nil, color: .secondary)
                            }

                            ForEach(unpinnedHosts, id: \.id) { host in
                                unpinnedRow(host)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search hosts")
        .navigationTitle("AnyPort")
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                if let error = store.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 4)
                }
                if let toast = toastMessage {
                    HStack(spacing: 6) {
                        Image(systemName: toastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(toastIsError ? .red : .green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toastMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Reload Hosts") {
                        store.loadHosts()
                    }
                    Divider()
                    Button("Quit AnyPort") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onDisappear {
            adaptiveHost = nil
            pendingTarget = nil
        }
        .onPreferenceChange(RowHeightKey.self) { h in
            if h > 0 { rowHeight = h }
        }
        .sheet(isPresented: Binding(
            get: { adaptiveHost != nil },
            set: { if !$0 { adaptiveHost = nil } }
        )) {
            if let host = adaptiveHost {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: 28))
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse)

                        Text(host.alias)
                            .font(.system(size: 15, weight: .semibold))

                        Text("Enter Port")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                    TextField("22", text: $adaptivePortInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 32, weight: .light, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary.opacity(0.5))
                        )
                        .padding(.horizontal, 32)
                        .onAppear { adaptivePortInput = "" }

                    HStack(spacing: 12) {
                        Button {
                            adaptiveHost = nil
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)

                        Button {
                            guard let target = pendingTarget, !adaptivePortInput.isEmpty else { return }
                            let h = host
                            adaptiveHost = nil
                            performConnect(h, target: target, port: adaptivePortInput)
                        } label: {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.tint)
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                        .disabled(adaptivePortInput.isEmpty)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                }
                .frame(width: 320)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    @ViewBuilder
    private func pinnedRow(_ host: SSHHost) -> some View {
        HostRow(
            host: host,
            isPinned: true,
            isHovered: hoveredAlias == host.alias,
            isDragging: draggingAlias == host.alias,
            onTogglePin: { orderManager.togglePin(alias: host.alias) },
            onConnect: { target in quickConnect(host: host, target: target) },
            onTap: { selectedHost = host }
        )
        .offset(y: draggingAlias == host.alias ? effectiveOffset : 0)
        .zIndex(draggingAlias == host.alias ? 1 : 0)
        .scaleEffect(draggingAlias == host.alias ? 1.03 : 1)
        .opacity(draggingAlias != nil && draggingAlias != host.alias ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard draggingAlias == nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredAlias = hovering ? host.alias : nil
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    if draggingAlias == nil {
                        draggingAlias = host.alias
                        dragSwapCount = 0
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    dragTranslation = value.translation.height
                    let eff = value.translation.height - CGFloat(dragSwapCount) * rowHeight
                    let threshold = rowHeight * 0.6

                    if eff > threshold {
                        var moved = false
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            moved = orderManager.movePinnedDown(alias: host.alias)
                        }
                        if moved {
                            dragSwapCount += 1
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    } else if eff < -threshold {
                        var moved = false
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            moved = orderManager.movePinnedUp(alias: host.alias)
                        }
                        if moved {
                            dragSwapCount -= 1
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        draggingAlias = nil
                        dragSwapCount = 0
                        dragTranslation = 0
                    }
                }
        )

        Divider()
    }

    @ViewBuilder
    private func unpinnedRow(_ host: SSHHost) -> some View {
        HostRow(
            host: host,
            isPinned: false,
            isHovered: hoveredAlias == host.alias,
            isDragging: false,
            onTogglePin: { orderManager.togglePin(alias: host.alias) },
            onConnect: { target in quickConnect(host: host, target: target) },
            onTap: { selectedHost = host }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            guard draggingAlias == nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredAlias = hovering ? host.alias : nil
            }
        }

        Divider()
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 10))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private func quickConnect(host: SSHHost, target: ConnectTarget) {
        let portModeKey = "port_mode_\(host.alias)"
        let isAdaptive = UserDefaults.standard.string(forKey: portModeKey) == "adaptive"

        if isAdaptive {
            adaptiveHost = host
            adaptivePortInput = ""
            pendingTarget = target
            return
        }

        let port = host.port ?? "22"
        guard !port.isEmpty else { return }
        performConnect(host, target: target, port: port)
    }

    private func performConnect(_ host: SSHHost, target: ConnectTarget, port: String) {
        do {
            try store.updatePort(alias: host.alias, port: port)
            orderManager.recordVisit(alias: host.alias)
            var success = false
            var appName = ""
            switch target {
            case .terminal:
                appName = "Terminal"
                success = Connector.openInTerminal(alias: host.alias)
            case .iterm:
                appName = "iTerm"
                success = Connector.openInITerm(alias: host.alias)
            case .vscode:
                appName = "VS Code"
                let pathKey = "vscode_path_\(host.alias)"
                let remotePath = UserDefaults.standard.string(forKey: pathKey) ?? "~"
                success = Connector.openInVSCode(alias: host.alias, remotePath: remotePath)
            }
            if success {
                toastIsError = false
                toastMessage = "Opened in \(appName)"
            } else {
                toastIsError = true
                toastMessage = "\(appName) could not be launched"
            }
        } catch {
            toastIsError = true
            toastMessage = error.localizedDescription
        }
        showToast()
    }

    private func showToast() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    toastMessage = nil
                }
            }
        }
    }
}

enum ConnectTarget {
    case terminal, iterm, vscode
}

private struct HostRow: View {
    let host: SSHHost
    let isPinned: Bool
    let isHovered: Bool
    let isDragging: Bool
    let onTogglePin: () -> Void
    let onConnect: (ConnectTarget) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon

            VStack(alignment: .leading, spacing: 1) {
                Text(host.alias)
                    .font(.system(size: 14, weight: .medium))
                Text(host.displaySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if isHovered && !isDragging {
                HStack(spacing: 2) {
                    actionButton(icon: "terminal", label: "Terminal") {
                        onConnect(.terminal)
                    }
                    if FileManager.default.fileExists(atPath: "/Applications/iTerm.app") || FileManager.default.fileExists(atPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/iTerm.app") {
                        actionButton(icon: "terminal.fill", label: "iTerm") {
                            onConnect(.iterm)
                        }
                    }
                    actionButton(icon: "chevron.left.forwardslash.chevron.right", label: "VS Code") {
                        onConnect(.vscode)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        }
        .shadow(color: isDragging ? .black.opacity(0.15) : .clear, radius: isDragging ? 6 : 0, y: isDragging ? 3 : 0)
        .onTapGesture { onTap() }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: RowHeightKey.self, value: geo.size.height)
            }
        )
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if isDragging {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.secondary)
                .font(.system(size: 14))
                .frame(width: 20)
        } else if isPinned {
            Button(action: onTogglePin) {
                Image(systemName: isHovered ? "pin.slash" : "pin.fill")
                    .foregroundStyle(isHovered ? Color.secondary : .orange)
                    .font(.system(size: 14))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin host" : "Pin host to top")
        } else {
            Button(action: onTogglePin) {
                Image(systemName: isHovered ? "pin" : "server.rack")
                    .foregroundStyle(isHovered ? .orange : Color.secondary)
                    .font(.system(size: 14))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin host" : "Pin host to top")
        }
    }

    private var backgroundFill: AnyShapeStyle {
        if isDragging {
            return AnyShapeStyle(.ultraThinMaterial)
        } else if isHovered {
            return AnyShapeStyle(.quaternary)
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
                    .background(
                        Circle()
                            .fill(.quaternary.opacity(0.6))
                    )
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
