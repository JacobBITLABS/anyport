import Foundation

@MainActor
final class HostOrderManager: ObservableObject {
    @Published var pinnedAliases: [String] = []
    @Published var lastVisited: [String: TimeInterval] = [:]

    private let pinnedKey = "pinned_host_aliases"
    private let lastVisitedKey = "last_visited_hosts"

    init() {
        load()
    }

    func load() {
        pinnedAliases = UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
        lastVisited = UserDefaults.standard.dictionary(forKey: lastVisitedKey) as? [String: TimeInterval] ?? [:]
    }

    func togglePin(alias: String) {
        if let index = pinnedAliases.firstIndex(of: alias) {
            pinnedAliases.remove(at: index)
        } else {
            pinnedAliases.append(alias)
        }
        UserDefaults.standard.set(pinnedAliases, forKey: pinnedKey)
    }

    func isPinned(alias: String) -> Bool {
        pinnedAliases.contains(alias)
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        pinnedAliases.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(pinnedAliases, forKey: pinnedKey)
    }

    @discardableResult
    func movePinnedUp(alias: String) -> Bool {
        guard let index = pinnedAliases.firstIndex(of: alias), index > 0 else { return false }
        pinnedAliases.swapAt(index, index - 1)
        UserDefaults.standard.set(pinnedAliases, forKey: pinnedKey)
        return true
    }

    @discardableResult
    func movePinnedDown(alias: String) -> Bool {
        guard let index = pinnedAliases.firstIndex(of: alias), index < pinnedAliases.count - 1 else { return false }
        pinnedAliases.swapAt(index, index + 1)
        UserDefaults.standard.set(pinnedAliases, forKey: pinnedKey)
        return true
    }

    func recordVisit(alias: String) {
        lastVisited[alias] = Date().timeIntervalSince1970
        UserDefaults.standard.set(lastVisited, forKey: lastVisitedKey)
    }

    func sortedHosts(_ hosts: [SSHHost]) -> [SSHHost] {
        sortedPinnedHosts(hosts) + sortedUnpinnedHosts(hosts)
    }

    func sortedPinnedHosts(_ hosts: [SSHHost]) -> [SSHHost] {
        pinnedAliases.compactMap { alias in
            hosts.first { $0.alias == alias }
        }
    }

    func sortedUnpinnedHosts(_ hosts: [SSHHost]) -> [SSHHost] {
        hosts.filter { !pinnedAliases.contains($0.alias) }
            .sorted { a, b in
                let timeA = lastVisited[a.alias] ?? 0
                let timeB = lastVisited[b.alias] ?? 0
                return timeA > timeB
            }
    }
}
