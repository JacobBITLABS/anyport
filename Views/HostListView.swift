import SwiftUI
import AppKit

struct HostListView: View {
    @ObservedObject var store: SSHConfigStore
    @ObservedObject var orderManager: HostOrderManager
    @Binding var searchText: String
    @Binding var selectedHost: SSHHost?

    @State private var hoveredAlias: String?
    @State private var dropRowAlias: String?
    @State private var dropGroupID: String?
    @State private var collapsedGroups: Set<String> = []
    @State private var adaptiveHost: SSHHost?
    @State private var adaptivePortInput: String = ""
    @State private var pendingTarget: ConnectTarget?
    @State private var creatingGroup = false
    @State private var newGroupName = ""
    @State private var pendingNewGroupMembers: [String] = []
    @State private var renamingGroupID: String?
    @State private var renameGroupName = ""
    @FocusState private var newGroupFieldFocused: Bool
    @FocusState private var renameFieldFocused: Bool
    @State private var scrollTarget: String?
    @State private var toastMessage: String?
    @State private var toastIsError = false

    private var searchMatches: [SSHHost] {
        guard !searchText.isEmpty else { return store.hosts }
        return store.hosts.filter { host in
            host.alias.localizedCaseInsensitiveContains(searchText)
                || (host.hostName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var ungroupedHosts: [SSHHost] {
        store.hosts.filter { orderManager.groupID(for: $0.alias) == nil }
    }

    private var pinnedHosts: [SSHHost] {
        orderManager.sortedPinnedHosts(ungroupedHosts).filterBySearch(searchText)
    }

    var body: some View {
        Group {
            if store.hosts.isEmpty && store.error == nil {
                ContentUnavailableView(
                    "No Hosts Found",
                    systemImage: "server.rack",
                    description: Text("Add SSH hosts to **~/.ssh/config** to see them here.")
                )
            } else if searchMatches.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No hosts match \"\(searchText)\"")
                )
            } else {
                VStack(spacing: 0) {
                    headerBar

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                if creatingGroup {
                                    newGroupRow
                                        .id("newGroupRow")
                                }

                                ForEach(pinnedHosts, id: \.id) { host in
                                    hostRow(host)
                                }

                                ForEach(orderManager.streamEntries) { entry in
                                    switch entry.kind {
                                    case .host:
                                        if let host = store.hosts.first(where: { $0.alias == entry.ref }) {
                                            hostRow(host)
                                        }
                                    case .group:
                                        if let group = orderManager.groups.first(where: { $0.id == entry.ref }) {
                                            groupSection(group)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                        }
                        .onChange(of: scrollTarget) { target in
                            guard let target else { return }
                            scrollTarget = nil
                            // Wait one layout pass so the target id is registered before scrolling.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(target, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .overlay {
            adaptiveCardOverlay
        }
        .animation(.spring(duration: 0.35), value: adaptiveHost)
        .animation(.easeInOut(duration: 0.25), value: toastMessage)
        .onChange(of: store.hosts.map(\.alias)) { aliases in
            orderManager.syncStructure(aliases: aliases)
        }
        .onDisappear {
            adaptiveHost = nil
            pendingTarget = nil
            dropRowAlias = nil
            dropGroupID = nil
        }
        .onAppear {
            orderManager.syncStructure(aliases: store.hosts.map(\.alias))
            // Debug/QA hooks — only active when passed explicitly on launch.
            if ProcessInfo.processInfo.arguments.contains("-DebugNewGroup") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    beginNewGroup(members: [])
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-DebugSeedGroups") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    seedGroupsForQA()
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-DebugCommitGroup") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    newGroupName = "QA Group"
                    createGroup()
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-DebugRenameGroup") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if let first = orderManager.groups.first {
                        beginRename(first)
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-DebugClearGroups") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    for group in orderManager.groups {
                        orderManager.deleteGroup(id: group.id)
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-DebugHoverRow") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    hoveredAlias = store.hosts.first?.alias
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-DebugAdaptivePrompt") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard let host = store.hosts.first else { return }
                    adaptiveHost = host
                    adaptivePortInput = ""
                    pendingTarget = .terminal
                }
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var toastOverlay: some View {
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(toastIsError ? Color.red : Color.green)
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var adaptiveCardOverlay: some View {
        if let host = adaptiveHost {
            AdaptivePortCard(
                alias: host.alias,
                port: $adaptivePortInput,
                onCancel: { adaptiveHost = nil },
                onConnect: {
                    guard let target = pendingTarget, !adaptivePortInput.isEmpty else { return }
                    let h = host
                    adaptiveHost = nil
                    performConnect(h, target: target, port: adaptivePortInput)
                }
            )
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Design.fieldShape.fill(.quaternary.opacity(0.6)))

            headerButton("plus", "New Group") {
                beginNewGroup(members: [])
            }

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
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func headerButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Ungrouped section

    // MARK: - Group sections

    @ViewBuilder
    private func groupSection(_ group: HostGroup) -> some View {
        let members = orderManager.hostsInGroup(group.id, from: store.hosts).filterBySearch(searchText)
        let isCollapsed = collapsedGroups.contains(group.id)

        VStack(spacing: 0) {
            groupHeader(group, memberCount: members.count, isCollapsed: isCollapsed)

            if !isCollapsed {
                if members.isEmpty {
                    emptyGroupRow(group)
                } else {
                    ForEach(members, id: \.id) { host in
                        hostRow(host)
                    }
                }
            }
        }
    }

    private func groupHeader(_ group: HostGroup, memberCount: Int, isCollapsed: Bool) -> some View {
        let isDropTarget = dropGroupID == group.id
        return HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "folder" : "folder.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)

            if renamingGroupID == group.id {
                TextField("Group name", text: $renameGroupName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .labelsHidden()
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(group) }
                    .onExitCommand { renamingGroupID = nil }
                    .frame(maxWidth: 160)
            } else {
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))

                Text("\(memberCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.7)))
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isDropTarget {
                Capsule().fill(Color.accentColor.opacity(0.15))
            }
        }
        .glassEffect(.regular, in: Capsule())
        .overlay {
            if isDropTarget {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .padding(.top, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            // Commit an in-progress rename instead of collapsing.
            if renamingGroupID == group.id {
                commitRename(group)
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                if isCollapsed {
                    collapsedGroups.remove(group.id)
                } else {
                    collapsedGroups.insert(group.id)
                }
            }
        }
        .contextMenu {
            Button("Rename…") {
                beginRename(group)
            }
            Button("Move Up") {
                _ = orderManager.moveGroup(id: group.id, up: true)
            }
            Button("Move Down") {
                _ = orderManager.moveGroup(id: group.id, up: false)
            }
            Divider()
            Button("Delete Group", role: .destructive) {
                orderManager.deleteGroup(id: group.id)
                showToast(message: "Group deleted — machines moved to Ungrouped", isError: false)
            }
        }
        .draggable("group::\(group.id)") {
            groupDragPreview(group)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            if payload.hasPrefix("group::") {
                return orderManager.moveGroup(id: String(payload.dropFirst("group::".count)), before: group.id)
            }
            orderManager.addToGroupAtTop(alias: payload, groupID: group.id)
            showToast(message: "Moved to \(group.name)", isError: false)
            return true
        } isTargeted: { hovering in
            dropGroupID = hovering ? group.id : nil
        }
    }

    private func emptyGroupRow(_ group: HostGroup) -> some View {
        Design.microLabel("Empty — drop machines here")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Design.rowShape.strokeBorder(
                    Color.secondary.opacity(dropGroupID == group.id ? 0.8 : 0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4])
                )
            )
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let alias = items.first else { return false }
                return moveToGroup(alias: alias, group: group)
            } isTargeted: { hovering in
                dropGroupID = hovering ? group.id : nil
            }
    }

    // MARK: - Host rows

    @ViewBuilder
    private func hostRow(_ host: SSHHost) -> some View {
        HostRow(
            host: host,
            isPinned: orderManager.isPinned(alias: host.alias),
            isHovered: hoveredAlias == host.alias,
            isDropTargeted: dropRowAlias == host.alias,
            lastVisitedLabel: Self.relativeTime(orderManager.lastVisited[host.alias]),
            onTogglePin: { orderManager.togglePin(alias: host.alias) },
            onConnect: { target in quickConnect(host: host, target: target) },
            onTap: { selectedHost = host }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredAlias = hovering ? host.alias : nil
            }
        }
        .contextMenu {
            rowContextMenu(host)
        }
        .draggable(host.alias) {
            dragPreview(for: host)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first, dragged != host.alias, !dragged.hasPrefix("group::") else { return false }
            return handleRowDrop(payload: dragged, onto: host)
        } isTargeted: { hovering in
            dropRowAlias = hovering ? host.alias : nil
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ host: SSHHost) -> some View {
        if orderManager.groups.isEmpty {
            Button("New Group…") {
                beginNewGroup(members: [host.alias])
            }
        } else {
            Menu("Add to Group") {
                ForEach(orderManager.groups) { group in
                    Button(group.name) {
                        _ = moveToGroup(alias: host.alias, group: group)
                    }
                }
                Divider()
                Button("New Group…") {
                    beginNewGroup(members: [host.alias])
                }
            }
            if orderManager.groupID(for: host.alias) != nil {
                Divider()
                Button("Remove from Group") {
                    _ = ungroup(alias: host.alias)
                }
            }
        }
    }

    private func dragPreview(for host: SSHHost) -> some View {
        HStack(spacing: 6) {
            Image(systemName: orderManager.isPinned(alias: host.alias) ? "pin.fill" : "server.rack")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(host.alias)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Design.chipShape)
    }

    private func groupDragPreview(_ group: HostGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
            Text(group.name)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Design.chipShape)
    }

    // MARK: - Drag & drop handling

    /// Drop dispatcher for rows. Payload is either a host alias or "group::<id>".
    ///
    /// - Group payload onto a top-level row: the whole group section moves
    ///   directly before that row (mixed rows-and-groups arrangement).
    /// - Host onto a pinned row: pin semantics (reorder within the pin block,
    ///   or pin the dragged host directly before the target).
    /// - Host onto a group member: reorder inside that group, carrying
    ///   membership along when containers differ.
    /// - Host onto a top-level row: dragged host becomes top-level too
    ///   (ungrouped) and takes the position directly before the target.
    private func handleRowDrop(payload: String, onto target: SSHHost) -> Bool {
        // Group payloads: the section slots in before a top-level, unpinned row
        // (pinned rows render in the pin block, not at their stream slot).
        if payload.hasPrefix("group::") {
            guard store.hosts.contains(where: { $0.alias == target.alias }),
                  orderManager.groupID(for: target.alias) == nil,
                  !orderManager.isPinned(alias: target.alias)
            else { return false }
            return orderManager.moveGroup(id: String(payload.dropFirst("group::".count)), beforeHost: target.alias)
        }

        let dragged = payload
        guard store.hosts.contains(where: { $0.alias == dragged }),
              dragged != target.alias
        else { return false }

        let wasPinned = orderManager.isPinned(alias: dragged)
        let draggedGroupID = orderManager.groupID(for: dragged)
        let targetGroupID = orderManager.groupID(for: target.alias)

        if orderManager.isPinned(alias: target.alias) {
            // Pin block: reorder pins / pin the dragged host before the target.
            _ = orderManager.moveHost(dragged, before: target.alias)
            if !wasPinned {
                showToast(message: "Pinned \(dragged)", isError: false)
            }
            return true
        }

        if let targetGroupID {
            // Target lives inside a group: take that position, carry membership.
            _ = orderManager.moveHost(dragged, before: target.alias)
            if draggedGroupID != targetGroupID {
                orderManager.setGroup(alias: dragged, groupID: targetGroupID)
                if let group = orderManager.groups.first(where: { $0.id == targetGroupID }) {
                    showToast(message: "Moved to \(group.name)", isError: false)
                }
            }
        } else {
            // Target is a top-level row: dragged host joins the top level.
            if draggedGroupID != nil {
                orderManager.setGroup(alias: dragged, groupID: nil)
                showToast(message: "Removed from group", isError: false)
            }
            _ = orderManager.moveHost(dragged, before: target.alias)
            if !orderManager.isPinned(alias: dragged) {
                orderManager.moveTopLevel(alias: dragged, before: target.alias)
            }
        }

        if wasPinned, !orderManager.isPinned(alias: dragged) {
            showToast(message: "Unpinned \(dragged)", isError: false)
        }
        return true
    }

    @discardableResult
    private func moveToGroup(alias: String, group: HostGroup) -> Bool {
        guard store.hosts.contains(where: { $0.alias == alias }),
              orderManager.groupID(for: alias) != group.id
        else { return false }
        orderManager.setGroup(alias: alias, groupID: group.id)
        showToast(message: "Moved to \(group.name)", isError: false)
        return true
    }

    @discardableResult
    private func ungroup(alias: String) -> Bool {
        guard store.hosts.contains(where: { $0.alias == alias }),
              orderManager.groupID(for: alias) != nil
        else { return false }
        orderManager.setGroup(alias: alias, groupID: nil)
        showToast(message: "Removed from group", isError: false)
        return true
    }

    // MARK: - Groups: create / rename

    private func beginNewGroup(members: [String]) {
        renamingGroupID = nil
        pendingNewGroupMembers = members
        newGroupName = ""
        if !creatingGroup {
            withAnimation(.easeInOut(duration: 0.2)) {
                creatingGroup = true
            }
            scrollTarget = "newGroupRow"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            newGroupFieldFocused = true
        }
    }

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let group = orderManager.createGroup(name: trimmed) else {
            creatingGroup = false
            pendingNewGroupMembers = []
            return
        }
        for alias in pendingNewGroupMembers {
            orderManager.setGroup(alias: alias, groupID: group.id)
        }
        if pendingNewGroupMembers.count > 1 {
            showToast(message: "Added \(pendingNewGroupMembers.count) machines to \(group.name)", isError: false)
        } else if let first = pendingNewGroupMembers.first {
            showToast(message: "Added \(first) to \(group.name)", isError: false)
        }
        pendingNewGroupMembers = []
        collapsedGroups.remove(group.id)
        creatingGroup = false
        newGroupFieldFocused = false
        // Reveal the new capsule even when it lands below the fold.
        scrollTarget = "group::\(group.id)"
    }

    private func beginRename(_ group: HostGroup) {
        renameGroupName = group.name
        renamingGroupID = group.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            renameFieldFocused = true
        }
    }

    private func commitRename(_ group: HostGroup) {
        let trimmed = renameGroupName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != group.name {
            orderManager.renameGroup(id: group.id, name: trimmed)
        }
        renamingGroupID = nil
        renameFieldFocused = false
    }

    /// Inline "New Group" row shown in the list while creating a group.
    private var newGroupRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)

            TextField("Group name", text: $newGroupName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .labelsHidden()
                .focused($newGroupFieldFocused)
                .onSubmit { createGroup() }
                .onExitCommand { creatingGroup = false }

            Button {
                createGroup()
            } label: {
                Text("Create")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)

            Button {
                creatingGroup = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: Capsule())
        .padding(.top, 10)
    }

    /// Seeds sample groups (QA only, via -DebugSeedGroups).
    private func seedGroupsForQA() {
        guard orderManager.groups.isEmpty else { return }
        if let web = orderManager.createGroup(name: "Web Servers") {
            for alias in store.hosts.prefix(2).map(\.alias) {
                orderManager.setGroup(alias: alias, groupID: web.id)
            }
        }
        if let db = orderManager.createGroup(name: "Databases") {
            if let third = store.hosts.dropFirst(2).first {
                orderManager.setGroup(alias: third.alias, groupID: db.id)
            }
        }
    }

    // MARK: - Connect

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
                showToast(message: "Opened in \(appName)", isError: false)
            } else {
                showToast(message: "\(appName) could not be launched", isError: true)
            }
        } catch {
            showToast(message: error.localizedDescription, isError: true)
        }
    }

    // MARK: - Toast

    private func showToast(message: String, isError: Bool) {
        toastIsError = isError
        toastMessage = message
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

private extension HostListView {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter
    }()

    static func relativeTime(_ interval: TimeInterval?) -> String? {
        guard let interval, interval > 0 else { return nil }
        return relativeFormatter.localizedString(
            for: Date(timeIntervalSince1970: interval),
            relativeTo: Date()
        )
    }
}

private extension Array where Element == SSHHost {
    func filterBySearch(_ searchText: String) -> [SSHHost] {
        guard !searchText.isEmpty else { return self }
        return filter { host in
            host.alias.localizedCaseInsensitiveContains(searchText)
                || (host.hostName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

private struct HostRow: View {
    let host: SSHHost
    let isPinned: Bool
    let isHovered: Bool
    let isDropTargeted: Bool
    let lastVisitedLabel: String?
    let onTogglePin: () -> Void
    let onConnect: (ConnectTarget) -> Void
    let onTap: () -> Void

    private var itermInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
            || FileManager.default.fileExists(atPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/iTerm.app")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.alias)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let subtitle = host.displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isHovered {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        circleButton(
                            Image(systemName: isPinned ? "pin.slash" : "pin")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isPinned ? Color.secondary : Color.accentColor),
                            isPinned ? "Unpin host" : "Pin host to top"
                        ) {
                            onTogglePin()
                        }
                        circleButton(ConnectTargetIcon(target: .terminal), "Connect in Terminal") {
                            onConnect(.terminal)
                        }
                        if itermInstalled {
                            circleButton(ConnectTargetIcon(target: .iterm), "Connect in iTerm") {
                                onConnect(.iterm)
                            }
                        }
                        circleButton(ConnectTargetIcon(target: .vscode), "Open in VS Code") {
                            onConnect(.vscode)
                        }
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if let lastVisitedLabel {
                Text(lastVisitedLabel)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            Design.rowShape.fill(backgroundFill)
        }
        .overlay {
            if isDropTargeted {
                Design.rowShape.strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .onTapGesture { onTap() }
    }

    private func circleButton(_ icon: some View, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var backgroundFill: Color {
        isHovered ? Color.primary.opacity(0.06) : .clear
    }
}
