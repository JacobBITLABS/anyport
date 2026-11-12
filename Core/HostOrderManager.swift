import Foundation

struct HostGroup: Identifiable, Codable, Equatable {
    let id: String
    var name: String
}

/// One slot in the top-level stream: an ungrouped host or a group section.
/// Host slots stay in place when the host joins a group (dormant) and the
/// host reappears there when it leaves the group again.
enum TopEntry: Codable, Equatable {
    case host(String)
    case group(String)
}

/// View-facing wrapper with stable identity for ForEach and scroll targets.
struct StreamEntry: Identifiable, Equatable {
    enum Kind { case host; case group }
    let id: String
    let kind: Kind
    let ref: String
}

@MainActor
final class HostOrderManager: ObservableObject {
    @Published var pinnedAliases: [String] = []
    @Published var lastVisited: [String: TimeInterval] = [:]
    @Published var groups: [HostGroup] = []
    @Published var membership: [String: String] = [:]
    @Published var hostOrder: [String] = []
    @Published var topLevelOrder: [TopEntry] = []

    private let defaults: UserDefaults
    private let pinnedKey = "pinned_host_aliases"
    private let lastVisitedKey = "last_visited_hosts"
    private let groupsKey = "host_groups"
    private let membershipKey = "host_group_membership"
    private let hostOrderKey = "host_order"
    private let topLevelKey = "top_level_order"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        pinnedAliases = defaults.stringArray(forKey: pinnedKey) ?? []
        lastVisited = defaults.dictionary(forKey: lastVisitedKey) as? [String: TimeInterval] ?? [:]
        hostOrder = defaults.stringArray(forKey: hostOrderKey) ?? []
        if let data = defaults.data(forKey: topLevelKey) {
            topLevelOrder = (try? JSONDecoder().decode([TopEntry].self, from: data)) ?? []
        }

        if let data = defaults.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([HostGroup].self, from: data) {
            groups = decoded
        }

        let validGroupIDs = Set(groups.map(\.id))
        membership = (defaults.dictionary(forKey: membershipKey) as? [String: String] ?? [:])
            .filter { validGroupIDs.contains($0.value) }
    }

    // MARK: - Manual host order

    /// Keeps the persisted structures in step with the current config:
    /// prunes removed aliases/groups, appends new ones.
    func syncStructure(aliases: [String]) {
        var order = hostOrder.filter { aliases.contains($0) }
        for alias in aliases where !order.contains(alias) {
            order.append(alias)
        }

        var top = topLevelOrder.filter { entry in
            switch entry {
            case .host(let alias): aliases.contains(alias)
            case .group(let groupID): groups.contains(where: { $0.id == groupID })
            }
        }
        func topHasHost(_ alias: String) -> Bool {
            top.contains { if case .host(let a) = $0 { return a == alias } else { return false } }
        }
        for alias in aliases where !topHasHost(alias) {
            top.append(.host(alias))
        }
        for group in groups where !top.contains(where: { $0 == .group(group.id) }) {
            top.append(.group(group.id))
        }

        if order != hostOrder {
            hostOrder = order
            defaults.set(hostOrder, forKey: hostOrderKey)
        }
        if top != topLevelOrder {
            topLevelOrder = top
            persistTopLevel()
        }
    }

    /// The top-level stream: ungrouped, unpinned hosts and group sections in
    /// their free arrangement. Pinned hosts float in the pin block instead;
    /// grouped hosts render nested inside their group.
    var streamEntries: [StreamEntry] {
        topLevelOrder.compactMap { entry in
            switch entry {
            case .host(let alias):
                guard membership[alias] == nil, !pinnedAliases.contains(alias) else { return nil }
                return StreamEntry(id: "host::\(alias)", kind: .host, ref: alias)
            case .group(let groupID):
                guard groups.contains(where: { $0.id == groupID }) else { return nil }
                return StreamEntry(id: "group::\(groupID)", kind: .group, ref: groupID)
            }
        }
    }

    private func orderIndex(_ alias: String) -> Int {
        hostOrder.firstIndex(of: alias) ?? Int.max
    }

    /// Moves an ungrouped host's top-level slot directly before another
    /// top-level host (mixed rows-and-groups arrangement).
    func moveTopLevel(alias: String, before targetAlias: String) {
        guard alias != targetAlias else { return }
        topLevelOrder.removeAll { $0 == .host(alias) }
        if let targetIndex = topLevelOrder.firstIndex(of: .host(targetAlias)) {
            topLevelOrder.insert(.host(alias), at: targetIndex)
        } else {
            topLevelOrder.append(.host(alias))
        }
        persistTopLevel()
    }

    /// Moves a group section directly before a top-level host row.
    @discardableResult
    func moveGroup(id: String, beforeHost targetAlias: String) -> Bool {
        guard membership[targetAlias] == nil,
              let targetIndex = topLevelOrder.firstIndex(of: .host(targetAlias)),
              let groupIndex = topLevelOrder.firstIndex(of: .group(id)),
              groupIndex != targetIndex
        else { return false }

        let entry = topLevelOrder.remove(at: groupIndex)
        let adjustedIndex = topLevelOrder.firstIndex(of: .host(targetAlias)) ?? targetIndex
        topLevelOrder.insert(entry, at: adjustedIndex)
        persistTopLevel()
        return true
    }

    /// Moves a host so it appears directly before the target row. Handles pin
    /// transitions: dropping onto a pinned row pins the dragged host, dropping a
    /// pinned host onto an unpinned row unpins it.
    @discardableResult
    func moveHost(_ alias: String, before targetAlias: String) -> Bool {
        guard alias != targetAlias else { return false }

        let draggedPinned = pinnedAliases.contains(alias)
        let targetPinned = pinnedAliases.contains(targetAlias)

        if draggedPinned && targetPinned {
            return movePinned(alias: alias, before: targetAlias)
        }
        if targetPinned && !draggedPinned {
            if let targetIndex = pinnedAliases.firstIndex(of: targetAlias) {
                pinnedAliases.insert(alias, at: targetIndex)
                persistPins()
            }
        } else if draggedPinned && !targetPinned {
            pinnedAliases.removeAll { $0 == alias }
            persistPins()
        }

        hostOrder.removeAll { $0 == alias }
        if let targetIndex = hostOrder.firstIndex(of: targetAlias) {
            hostOrder.insert(alias, at: targetIndex)
        } else {
            hostOrder.append(alias)
        }
        defaults.set(hostOrder, forKey: hostOrderKey)
        return true
    }

    // MARK: - Pinning

    func togglePin(alias: String) {
        if let index = pinnedAliases.firstIndex(of: alias) {
            pinnedAliases.remove(at: index)
        } else {
            pinnedAliases.append(alias)
        }
        persistPins()
    }

    func isPinned(alias: String) -> Bool {
        pinnedAliases.contains(alias)
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        var aliases = pinnedAliases
        let moved = source.sorted().map { aliases[$0] }
        for index in source.sorted().reversed() {
            aliases.remove(at: index)
        }
        let insertionIndex = destination - source.filter { $0 < destination }.count
        aliases.insert(contentsOf: moved, at: insertionIndex)
        pinnedAliases = aliases
        persistPins()
    }

    @discardableResult
    func movePinnedUp(alias: String) -> Bool {
        guard let index = pinnedAliases.firstIndex(of: alias), index > 0 else { return false }
        pinnedAliases.swapAt(index, index - 1)
        persistPins()
        return true
    }

    @discardableResult
    func movePinnedDown(alias: String) -> Bool {
        guard let index = pinnedAliases.firstIndex(of: alias), index < pinnedAliases.count - 1 else { return false }
        pinnedAliases.swapAt(index, index + 1)
        persistPins()
        return true
    }

    /// Moves a pinned host so it appears directly before another pinned host.
    @discardableResult
    func movePinned(alias: String, before targetAlias: String) -> Bool {
        guard alias != targetAlias,
              pinnedAliases.contains(alias),
              pinnedAliases.contains(targetAlias)
        else { return false }

        pinnedAliases.removeAll { $0 == alias }
        if let targetIndex = pinnedAliases.firstIndex(of: targetAlias) {
            pinnedAliases.insert(alias, at: targetIndex)
        } else {
            pinnedAliases.append(alias)
        }
        persistPins()
        return true
    }

    private func persistPins() {
        defaults.set(pinnedAliases, forKey: pinnedKey)
    }

    func recordVisit(alias: String) {
        lastVisited[alias] = Date().timeIntervalSince1970
        defaults.set(lastVisited, forKey: lastVisitedKey)
    }

    // MARK: - Sorting

    func sortedHosts(_ hosts: [SSHHost]) -> [SSHHost] {
        sortedPinnedHosts(hosts) + sortedUnpinnedHosts(hosts)
    }

    func sortedPinnedHosts(_ hosts: [SSHHost]) -> [SSHHost] {
        pinnedAliases.compactMap { alias in
            hosts.first { $0.alias == alias }
        }
    }

    /// Non-pinned hosts in manual display order (new aliases follow).
    func sortedUnpinnedHosts(_ hosts: [SSHHost]) -> [SSHHost] {
        hosts.filter { !pinnedAliases.contains($0.alias) }
            .sorted { a, b in
                let indexA = orderIndex(a.alias)
                let indexB = orderIndex(b.alias)
                if indexA != indexB { return indexA < indexB }
                return a.alias.localizedStandardCompare(b.alias) == .orderedAscending
            }
    }

    /// Pinned hosts first (in pin order), then the manual display order.
    func sortedByPriority(_ hosts: [SSHHost]) -> [SSHHost] {
        sortedPinnedHosts(hosts) + sortedUnpinnedHosts(hosts)
    }

    // MARK: - Groups

    func groupID(for alias: String) -> String? {
        guard let groupID = membership[alias],
              groups.contains(where: { $0.id == groupID })
        else { return nil }
        return groupID
    }

    func group(named name: String) -> HostGroup? {
        groups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Hosts belonging to the given group (nil = ungrouped), sorted pinned-first.
    func hostsInGroup(_ groupID: String?, from hosts: [SSHHost]) -> [SSHHost] {
        sortedByPriority(hosts.filter { membership[$0.alias] == groupID })
    }

    @discardableResult
    func createGroup(name: String) -> HostGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let group = HostGroup(id: UUID().uuidString, name: trimmed)
        groups.append(group)
        topLevelOrder.append(.group(group.id))
        persistGroups()
        persistTopLevel()
        return group
    }

    func renameGroup(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let index = groups.firstIndex(where: { $0.id == id })
        else { return }
        groups[index].name = trimmed
        persistGroups()
    }

    func deleteGroup(id: String) {
        groups.removeAll { $0.id == id }
        topLevelOrder.removeAll { $0 == .group(id) }
        for (alias, group) in membership where group == id {
            membership.removeValue(forKey: alias)
        }
        persistGroups()
        persistTopLevel()
        persistMembership()
    }

    @discardableResult
    func moveGroup(id: String, up: Bool) -> Bool {
        guard let index = topLevelOrder.firstIndex(of: .group(id)) else { return false }
        var neighbor = up ? index - 1 : index + 1
        while topLevelOrder.indices.contains(neighbor) {
            if case .group = topLevelOrder[neighbor] {
                topLevelOrder.swapAt(index, neighbor)
                persistTopLevel()
                return true
            }
            neighbor += up ? -1 : 1
        }
        return false
    }

    /// Moves a group so it appears directly before another group in the stream.
    @discardableResult
    func moveGroup(id: String, before targetID: String) -> Bool {
        guard id != targetID,
              topLevelOrder.contains(where: { $0 == .group(id) }),
              let targetIndex = topLevelOrder.firstIndex(of: .group(targetID))
        else { return false }

        let sourceIndex = topLevelOrder.firstIndex(of: .group(id))!
        let entry = topLevelOrder.remove(at: sourceIndex)
        let adjustedIndex = topLevelOrder.firstIndex(of: .group(targetID)) ?? targetIndex
        topLevelOrder.insert(entry, at: adjustedIndex)
        persistTopLevel()
        return true
    }

    /// Assigns a host to a group; passing nil removes it from any group.
    func setGroup(alias: String, groupID: String?) {
        if let groupID, groups.contains(where: { $0.id == groupID }) {
            membership[alias] = groupID
        } else {
            membership.removeValue(forKey: alias)
        }
        persistMembership()
    }

    /// Joins a group and takes the top slot among its members (drop on header).
    func addToGroupAtTop(alias: String, groupID: String) {
        setGroup(alias: alias, groupID: groupID)
        guard let firstMember = hostOrder.first(where: { $0 != alias && membership[$0] == groupID }) else { return }
        hostOrder.removeAll { $0 == alias }
        if let index = hostOrder.firstIndex(of: firstMember) {
            hostOrder.insert(alias, at: index)
        }
        defaults.set(hostOrder, forKey: hostOrderKey)
    }

    private func persistGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            defaults.set(data, forKey: groupsKey)
        }
    }

    private func persistMembership() {
        defaults.set(membership, forKey: membershipKey)
    }

    private func persistTopLevel() {
        if let data = try? JSONEncoder().encode(topLevelOrder) {
            defaults.set(data, forKey: topLevelKey)
        }
    }
}
